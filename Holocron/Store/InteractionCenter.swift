import Foundation
import Observation

/// Receives hook envelopes from `HookServer`, applies the passthrough policy,
/// owns the queue of pending cards, and guarantees every blocked hook gets an
/// answer (user decision or timeout).
@MainActor
@Observable
final class InteractionCenter {
    private(set) var pending: [PendingInteraction] = []
    /// Rolling journal of hook traffic + decisions, surfaced in Settings →
    /// Advanced and mirrored to logs/hook-app.log for bug reports.
    private(set) var recentHookEvents: [String] = []

    /// Side-effect taps, wired by the app delegate. Invoked on the main actor.
    @ObservationIgnored var onCardAppeared: (@MainActor (PendingInteraction) -> Void)?
    @ObservationIgnored var onCardResolved: (@MainActor (PendingInteraction) -> Void)?
    @ObservationIgnored var onTurnEnded: (@MainActor (String) -> Void)?      // sessionId
    @ObservationIgnored var onSessionError: (@MainActor (String) -> Void)?   // message

    private let settings: AppSettings
    private let store: SessionStore
    @ObservationIgnored private var timeoutTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var ruleMirror: PermissionRuleMirror?
    @ObservationIgnored private var ruleMirrorLoadedAt = Date.distantPast
    @ObservationIgnored private var ruleMirrorCwd: String?

    init(settings: AppSettings, store: SessionStore) {
        self.settings = settings
        self.store = store
    }

    var pendingSessionIds: Set<String> { Set(pending.map(\.sessionId)) }

    func interaction(forSession sessionId: String) -> PendingInteraction? {
        pending.first { $0.sessionId == sessionId }
    }

    /// The card currently shown front-and-center (oldest first: FIFO fairness).
    var frontCard: PendingInteraction? { pending.first }

    // MARK: - Envelope entry point

    private func trace(_ line: String) {
        recentHookEvents.append(line)
        if recentHookEvents.count > 30 {
            recentHookEvents.removeFirst(recentHookEvents.count - 30)
        }
        HookDebugLog.append(line, to: "hook-app.log")
    }

    func handle(_ envelope: HookEnvelope, reply: @escaping @Sendable (HookReply) -> Void) {
        let sessionId = envelope.payload["session_id"]?.stringValue ?? "unknown"
        let toolName = envelope.payload["tool_name"]?.stringValue
        trace("recv \(envelope.event.rawValue)\(toolName.map { " tool=\($0)" } ?? "") session=\(sessionId.prefix(8))")
        // Every hook event refreshes the terminal identity of the session:
        // cheap, and self-heals if the user moves the session between tabs.
        if envelope.context.itermSessionId != nil || envelope.context.tty != nil {
            store.attachTerminal(sessionId: sessionId, context: envelope.context)
        }

        switch envelope.event {
        case .preToolUse:
            handlePreToolUse(envelope, sessionId: sessionId, reply: reply)
        case .postToolUse:
            // Tool executed → any degraded-mode card for this session is stale.
            resolveCards(sessionId: sessionId, onlyTerminalPrompts: true)
        case .notification:
            handleNotification(envelope, sessionId: sessionId)
        case .stop:
            resolveCards(sessionId: sessionId, onlyTerminalPrompts: false)
            onTurnEnded?(sessionId)
        case .sessionStart:
            break  // attachment already recorded above
        case .sessionEnd:
            resolveCards(sessionId: sessionId, onlyTerminalPrompts: false)
            store.markSessionEnded(sessionId: sessionId)
        }
    }

    // MARK: - PreToolUse

    private func handlePreToolUse(
        _ envelope: HookEnvelope,
        sessionId: String,
        reply: @escaping @Sendable (HookReply) -> Void
    ) {
        let info = PreToolUseInfo(payload: envelope.payload)

        guard settings.interceptPermissions else {
            trace("pretooluse \(info.toolName): passthrough (interception disabled)")
            reply(.passthrough)
            return
        }
        // Modes where Claude Code will not prompt anyway.
        if info.permissionMode == "bypassPermissions" {
            trace("pretooluse \(info.toolName): passthrough (bypassPermissions mode)")
            reply(.passthrough)
            return
        }
        if info.permissionMode == "acceptEdits",
           ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(info.toolName) {
            trace("pretooluse \(info.toolName): passthrough (acceptEdits mode)")
            reply(.passthrough)
            return
        }
        // Allow-listed by the user's own Claude Code rules (and not vetoed
        // by a deny/ask rule) → no card.
        if case .autoAllowed(let rule) = mirror(for: info.cwd)
            .verdict(toolName: info.toolName, toolInput: info.toolInput) {
            trace("pretooluse \(info.toolName): passthrough (allow rule '\(rule)')")
            reply(.passthrough)
            return
        }

        let kind: PendingInteraction.Kind
        switch info.toolName {
        case "AskUserQuestion":
            guard settings.answerQuestionsFromNotch,
                  let questions = AskUserQuestionInput(toolInput: info.toolInput) else {
                reply(.passthrough)
                return
            }
            kind = .question(questions)
        case "ExitPlanMode":
            let plan = info.toolInput["plan"]?.stringValue ?? "(empty plan)"
            kind = .planReview(plan: plan)
        default:
            kind = .permission(
                toolName: info.toolName,
                detail: SessionReducer.toolDetail(name: info.toolName, input: info.toolInput),
                rawInput: info.toolInput
            )
        }

        let interaction = PendingInteraction(
            id: UUID(),
            sessionId: sessionId,
            cwd: info.cwd,
            receivedAt: Date(),
            kind: kind,
            respond: reply
        )
        trace("pretooluse \(info.toolName): card enqueued (\(interaction.title))")
        enqueue(interaction)
    }

    private func handleNotification(_ envelope: HookEnvelope, sessionId: String) {
        // If a blocking card already exists for this session, the terminal
        // prompt notification is redundant.
        guard interaction(forSession: sessionId) == nil else { return }
        let message = envelope.payload["message"]?.stringValue ?? "Claude Code needs your attention"
        let lowered = message.lowercased()
        // Idle/auth notifications are status noise, not actionable cards.
        guard lowered.contains("permission") || lowered.contains("waiting")
            || lowered.contains("input") || lowered.contains("question") else { return }
        let interaction = PendingInteraction(
            id: UUID(),
            sessionId: sessionId,
            cwd: envelope.payload["cwd"]?.stringValue,
            receivedAt: Date(),
            kind: .terminalPrompt(message: message),
            respond: nil
        )
        enqueue(interaction)
    }

    // MARK: - Card lifecycle

    private func enqueue(_ interaction: PendingInteraction) {
        pending.append(interaction)
        onCardAppeared?(interaction)

        if interaction.respond != nil {
            let timeout = max(10, settings.decisionTimeoutSeconds)
            let id = interaction.id
            timeoutTasks[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.resolve(id: id, with: HookReply(
                    action: self?.settings.timeoutAction ?? .passthrough,
                    reason: "No answer in Holocron within \(timeout)s"
                ))
            }
        }
    }

    /// User decision from the UI (or timeout).
    func resolve(id: UUID, with reply: HookReply) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let interaction = pending.remove(at: index)
        timeoutTasks.removeValue(forKey: id)?.cancel()
        trace("resolve '\(interaction.title)' → \(reply.action.rawValue)")
        interaction.respond?(reply)
        onCardResolved?(interaction)
    }

    func allow(_ interaction: PendingInteraction) {
        resolve(id: interaction.id, with: HookReply(
            action: .allow, reason: "Approved by the user in Holocron"))
    }

    func deny(_ interaction: PendingInteraction) {
        resolve(id: interaction.id, with: HookReply(
            action: .deny, reason: "Denied by the user in Holocron"))
    }

    /// Answer an AskUserQuestion card. There is no official hook API to
    /// answer a question, so the selected labels ride back to Claude in the
    /// deny reason (documented behavior, works well in practice).
    func answer(_ interaction: PendingInteraction, selectedLabels: [String]) {
        let joined = selectedLabels.joined(separator: "; ")
        resolve(id: interaction.id, with: HookReply(
            action: .answer,
            reason: "The user answered via Holocron — proceed with this choice: \(joined). "
                + "Do not re-ask; treat it as the AskUserQuestion result."
        ))
    }

    func dismiss(_ interaction: PendingInteraction) {
        resolve(id: interaction.id, with: .passthrough)
    }

    private func resolveCards(sessionId: String, onlyTerminalPrompts: Bool) {
        let stale = pending.filter { card in
            guard card.sessionId == sessionId else { return false }
            if onlyTerminalPrompts {
                if case .terminalPrompt = card.kind { return true }
                return false
            }
            return true
        }
        for card in stale {
            resolve(id: card.id, with: .passthrough)
        }
    }

    // MARK: - Rule mirror cache

    private func mirror(for cwd: String?) -> PermissionRuleMirror {
        let now = Date()
        if let ruleMirror, ruleMirrorCwd == cwd, now.timeIntervalSince(ruleMirrorLoadedAt) < 10 {
            return ruleMirror
        }
        let loaded = PermissionRuleMirror.load(
            home: FileManager.default.homeDirectoryForCurrentUser,
            projectCwd: cwd
        )
        ruleMirror = loaded
        ruleMirrorLoadedAt = now
        ruleMirrorCwd = cwd
        return loaded
    }
}
