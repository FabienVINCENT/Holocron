import Foundation

/// Terminal/host identity of a session, captured from the hook process
/// environment (SessionStart and every subsequent hook event).
struct TerminalAttachment: Codable, Sendable {
    let itermSessionId: String?   // e.g. "w0t2p0:6BF9A6A4-…"
    let termSessionId: String?
    let tty: String?
    let termProgram: String?      // "iTerm.app", "Apple_Terminal", …
    /// "JetBrains-JediTerm" inside IDE terminals (PhpStorm, IntelliJ…).
    let terminalEmulator: String?
    /// Bundle id of the hosting app (__CFBundleIdentifier), e.g.
    /// com.jetbrains.PhpStorm or com.anthropic.claudefordesktop.
    let bundleIdentifier: String?
    let claudePid: Int32
    let isOrca: Bool

    /// The iTerm2 session GUID used for AppleScript matching.
    var itermGUID: String? {
        guard let raw = itermSessionId ?? termSessionId else { return nil }
        return raw.split(separator: ":").last.map(String.init)
    }

    var isJetBrains: Bool {
        bundleIdentifier?.hasPrefix("com.jetbrains") == true
            || terminalEmulator == "JetBrains-JediTerm"
    }

    var isClaudeDesktopApp: Bool {
        guard let bundleIdentifier else { return false }
        let lowered = bundleIdentifier.lowercased()
        return lowered.contains("anthropic") || lowered.contains("claudefordesktop")
    }

    init(context: HookProcessContext) {
        itermSessionId = context.itermSessionId
        termSessionId = context.termSessionId
        tty = context.tty
        termProgram = context.termProgram
        terminalEmulator = context.terminalEmulator
        bundleIdentifier = context.bundleIdentifier
        claudePid = context.ppid  // the hook's parent is the claude process
        isOrca = context.isOrca
    }
}
