import Foundation

/// Where a session's status comes from, in increasing priority:
/// transcript inference < hook signals (exact).
enum SessionStatus: String, Sendable {
    /// Claude is thinking or a tool is executing.
    case running
    /// A PreToolUse permission request is pending in Holocron.
    case waitingPermission
    /// An AskUserQuestion / plan review is pending in Holocron.
    case waitingQuestion
    /// Claude finished its turn; the user has the keyboard.
    case waitingInput
    /// No activity for a while.
    case idle
    /// Session ended (SessionEnd hook or transcript went quiet for good).
    case done

    var needsAttention: Bool {
        self == .waitingPermission || self == .waitingQuestion
    }
}

enum AgentKind: String, Sendable {
    case claudeCode
    case orca
    case unknown
}

struct TokenTotals: Sendable, Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheCreation = 0

    mutating func add(_ usage: TokenUsage) {
        input += usage.inputTokens ?? 0
        output += usage.outputTokens ?? 0
        cacheRead += usage.cacheReadInputTokens ?? 0
        cacheCreation += usage.cacheCreationInputTokens ?? 0
    }

    var total: Int { input + output + cacheRead + cacheCreation }
}

/// A live tool invocation extracted from the transcript.
struct ToolActivity: Sendable, Equatable {
    let toolUseId: String
    let name: String
    /// Human-oriented one-liner: the Bash command, the file path…
    let detail: String
    let startedAt: Date?
}

/// Aggregated, UI-ready view of one Claude Code session, derived purely from
/// its transcript. Hook-driven state (pending permissions/questions, terminal
/// identity) is layered on top by `SessionStore`.
struct AgentSession: Identifiable, Sendable {
    let id: String                 // sessionId
    var transcriptURL: URL
    var cwd: String?
    var gitBranch: String?
    var agentKind: AgentKind = .unknown
    var model: String?
    var startedAt: Date?
    var lastActivityAt: Date?
    var lastAssistantText: String?
    var lastUserPrompt: String?
    var runningTools: [ToolActivity] = []
    var recentFiles: [String] = []       // most recent last, capped
    var recentCommands: [String] = []    // most recent last, capped
    var lastStopReason: String?
    var lastLineType: String?
    var usage = TokenTotals()
    var endedByHook = false
    var isPartialParse = false

    var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "?" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Status inferred from the transcript alone (see SessionStore for the
    /// hook overlay). Rules, in order:
    /// 1. ended → done
    /// 2. a tool_use has no tool_result yet → running (tool executing)
    /// 3. last line is a user prompt / tool_result → running (Claude thinking)
    /// 4. last assistant turn completed (stop_reason present) → waitingInput
    /// 5. anything stale beyond `idleAfter` → idle
    func inferredStatus(now: Date, idleAfter: TimeInterval) -> SessionStatus {
        if endedByHook { return .done }
        guard let last = lastActivityAt else { return .idle }
        let age = now.timeIntervalSince(last)
        if age > idleAfter { return .idle }

        if !runningTools.isEmpty { return .running }
        switch lastLineType {
        case "user", "queue-operation", "last-prompt":
            return .running
        case "assistant":
            if lastStopReason != nil { return .waitingInput }
            return .running
        default:
            return age < 120 ? .running : .waitingInput
        }
    }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (lastActivityAt ?? startedAt).timeIntervalSince(startedAt)
    }
}
