import Foundation

/// Something a session is blocked on, surfaced as a card in the notch.
struct PendingInteraction: Identifiable, Sendable {
    enum Kind: Sendable {
        /// PreToolUse interception — the hook is blocked waiting for a reply.
        case permission(toolName: String, detail: String, rawInput: JSONValue)
        /// ExitPlanMode interception — plan markdown to review.
        case planReview(plan: String)
        /// AskUserQuestion interception.
        case question(AskUserQuestionInput)
        /// Degraded mode: Claude Code is showing a prompt in the terminal
        /// (Notification hook) — Holocron can only alert + jump.
        case terminalPrompt(message: String)
    }

    let id: UUID
    let sessionId: String
    let cwd: String?
    let receivedAt: Date
    let kind: Kind
    /// Present when the hook is blocked on our answer; nil for fire-and-forget
    /// notifications.
    let respond: (@Sendable (HookReply) -> Void)?

    var isAnswerable: Bool { respond != nil }

    var title: String {
        switch kind {
        case .permission(let toolName, _, _): return "Permission — \(toolName)"
        case .planReview: return "Plan review"
        case .question: return "Question"
        case .terminalPrompt: return "Action needed in terminal"
        }
    }
}
