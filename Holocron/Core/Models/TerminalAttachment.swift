import Foundation

/// Terminal identity of a session, captured from the hook process
/// environment (SessionStart and every subsequent hook event).
struct TerminalAttachment: Codable, Sendable {
    let itermSessionId: String?   // e.g. "w0t2p0:6BF9A6A4-…"
    let termSessionId: String?
    let tty: String?
    let termProgram: String?
    let claudePid: Int32
    let isOrca: Bool

    /// The iTerm2 session GUID used for AppleScript matching.
    var itermGUID: String? {
        guard let raw = itermSessionId ?? termSessionId else { return nil }
        return raw.split(separator: ":").last.map(String.init)
    }

    init(context: HookProcessContext) {
        itermSessionId = context.itermSessionId
        termSessionId = context.termSessionId
        tty = context.tty
        termProgram = context.termProgram
        claudePid = context.ppid  // the hook's parent is the claude process
        isOrca = context.isOrca
    }
}
