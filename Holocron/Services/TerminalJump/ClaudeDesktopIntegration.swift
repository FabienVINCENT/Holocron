import Foundation

/// Sessions spawned by the official Claude desktop app (they inherit its
/// `__CFBundleIdentifier`). The app exposes no per-conversation deep links
/// (see docs/CLAUDE-DESKTOP-FEASIBILITY.md), so jump = activate the app.
struct ClaudeDesktopIntegration: TerminalIntegration {
    let name = "Claude desktop"

    func canHandle(_ attachment: TerminalAttachment?) -> Bool {
        attachment?.isClaudeDesktopApp == true
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?) throws {
        guard let bundleId = attachment?.bundleIdentifier else {
            throw TerminalJumpError.sessionNotFound("no bundle id recorded")
        }
        try AppActivator.open(bundleId: bundleId)
    }
}
