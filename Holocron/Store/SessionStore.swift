import Foundation
import Observation

/// Aggregates every detected Claude Code session and feeds the UI.
/// Transcript parsing runs in `TranscriptPipeline` (background queue); only
/// finished snapshots cross onto the main actor.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [AgentSession] = []
    private(set) var attachments: [String: TerminalAttachment] = [:]

    let settings: AppSettings

    @ObservationIgnored private var watcher: TranscriptWatcher
    @ObservationIgnored private let pipeline = TranscriptPipeline()
    @ObservationIgnored private var refreshTimer: Timer?

    private var attachmentsFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Holocron/attachments.json")
    }

    init(settings: AppSettings) {
        self.settings = settings
        self.watcher = TranscriptWatcher(rootDirectories: settings.transcriptRoots)
        loadAttachments()
    }

    func start() {
        pipeline.onSnapshot = { snapshot in
            Task { @MainActor [weak self] in
                self?.sessions = snapshot
            }
        }
        let pipeline = self.pipeline
        watcher.onTranscriptsChanged = { urls in
            pipeline.ingest(urls: urls)
        }
        watcher.start()
        pipeline.ingest(urls: watcher.scanExistingTranscripts())

        // Time-based statuses (idle, retention) need a slow heartbeat.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sessions = self.sessions  // re-publish for time-derived UI
            }
        }
    }

    func stop() {
        watcher.stop()
        refreshTimer?.invalidate()
    }

    func reloadRoots() {
        watcher.updateRoots(settings.transcriptRoots)
        pipeline.ingest(urls: watcher.scanExistingTranscripts())
    }

    // MARK: - Hook-driven updates (called by InteractionCenter, main actor)

    func attachTerminal(sessionId: String, context: HookProcessContext) {
        attachments[sessionId] = TerminalAttachment(context: context)
        saveAttachments()
    }

    func markSessionEnded(sessionId: String) {
        pipeline.markEnded(sessionId: sessionId)
    }

    func session(withId id: String) -> AgentSession? {
        sessions.first { $0.id == id }
    }

    // MARK: - Display helpers

    /// Sessions worth showing, most urgent first.
    func displaySessions(pendingSessionIds: Set<String>, now: Date = Date()) -> [AgentSession] {
        let retention = TimeInterval(settings.retentionHours) * 3600
        let idleAfter = TimeInterval(settings.idleAfterMinutes) * 60
        return sessions
            .filter { session in
                guard let last = session.lastActivityAt else { return false }
                return now.timeIntervalSince(last) < retention
            }
            .sorted { a, b in
                let aPending = pendingSessionIds.contains(a.id)
                let bPending = pendingSessionIds.contains(b.id)
                if aPending != bPending { return aPending }
                let aRunning = a.inferredStatus(now: now, idleAfter: idleAfter) == .running
                let bRunning = b.inferredStatus(now: now, idleAfter: idleAfter) == .running
                if aRunning != bRunning { return aRunning }
                return (a.lastActivityAt ?? .distantPast) > (b.lastActivityAt ?? .distantPast)
            }
    }

    func status(of session: AgentSession, pending: PendingInteraction?, now: Date = Date()) -> SessionStatus {
        if let pending {
            switch pending.kind {
            case .question, .planReview: return .waitingQuestion
            case .permission, .terminalPrompt: return .waitingPermission
            }
        }
        let idleAfter = TimeInterval(settings.idleAfterMinutes) * 60
        return session.inferredStatus(now: now, idleAfter: idleAfter)
    }

    // MARK: - Attachment persistence

    private func loadAttachments() {
        guard let data = try? Data(contentsOf: attachmentsFileURL),
              let decoded = try? JSONDecoder().decode([String: TerminalAttachment].self, from: data)
        else { return }
        attachments = decoded
    }

    private func saveAttachments() {
        let url = attachmentsFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(attachments) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
