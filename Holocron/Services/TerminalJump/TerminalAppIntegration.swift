import Foundation

/// Terminal.app: match the session's tty across windows/tabs.
struct TerminalAppIntegration: TerminalIntegration {
    let name = "Terminal"

    func canHandle(_ attachment: TerminalAttachment?) -> Bool {
        attachment?.termProgram == "Apple_Terminal"
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?) throws {
        guard let tty = AppleScriptRunner.sanitize(attachment?.tty) else {
            throw TerminalJumpError.sessionNotFound("no tty recorded for this Terminal session")
        }
        try jump(tty: tty)
    }

    func jump(tty: String) throws {
        guard let tty = AppleScriptRunner.sanitize(tty) else {
            throw TerminalJumpError.sessionNotFound("invalid tty")
        }
        let script = """
        on run
            tell application "Terminal"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "notfound"
        end run
        """
        let result = try AppleScriptRunner.run(script, appName: "Terminal")
        if result == "notfound" {
            throw TerminalJumpError.sessionNotFound("no Terminal tab owns \(tty)")
        }
    }
}
