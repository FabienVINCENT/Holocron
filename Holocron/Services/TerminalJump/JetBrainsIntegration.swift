import Foundation

/// JetBrains IDE terminals (PhpStorm, IntelliJ, WebStorm…): sessions started
/// inside the IDE inherit `__CFBundleIdentifier` (e.g. com.jetbrains.PhpStorm)
/// and `TERMINAL_EMULATOR=JetBrains-JediTerm`.
///
/// Jump = `open -b <ide-bundle> <session-cwd>`: the IDE focuses the window
/// of the already-open matching project (or opens it). There is no public
/// per-terminal-tab addressing in JetBrains IDEs, so window-level focus is
/// the reliable target.
struct JetBrainsIntegration: TerminalIntegration {
    let name = "JetBrains IDE"

    func canHandle(_ attachment: TerminalAttachment?) -> Bool {
        attachment?.isJetBrains == true
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?) throws {
        // Known bundle id when the session was launched from the IDE;
        // PhpStorm as a sensible default for JediTerm without one.
        let bundleId = attachment?.bundleIdentifier?.hasPrefix("com.jetbrains") == true
            ? attachment!.bundleIdentifier!
            : "com.jetbrains.PhpStorm"
        try AppActivator.open(bundleId: bundleId, path: cwd)
    }
}
