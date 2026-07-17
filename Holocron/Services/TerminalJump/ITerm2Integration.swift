import AppKit
import Foundation

/// Jumps to the exact iTerm2 window/tab/split of a session.
///
/// Matching strategy (in order):
/// 1. **Session GUID** — the hook binary inherits `ITERM_SESSION_ID`
///    (`w0t2p0:GUID`) from the shell that launched `claude`; the GUID equals
///    the AppleScript `id` of the iTerm2 session. Exact, survives tab moves.
/// 2. **tty** — the hook also records its controlling terminal
///    (`/dev/ttys0NN`), matched against each session's `tty`. Covers sessions
///    started before Holocron ever saw an ITERM_SESSION_ID.
/// 3. Otherwise fail with a clear message (no fuzzy cwd guessing: wrong-tab
///    jumps are worse than an error).
struct ITerm2Integration: TerminalIntegration {
    let name = "iTerm2"

    func canHandle(_ attachment: TerminalAttachment?) -> Bool {
        guard let attachment else { return false }
        if attachment.termProgram == "iTerm.app" { return true }
        // Older attachments may miss TERM_PROGRAM; try if we have any handle.
        return attachment.itermGUID != nil || attachment.tty != nil
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?) throws {
        guard let attachment else { throw TerminalJumpError.sessionNotFound("no terminal recorded") }
        let guid = sanitize(attachment.itermGUID)
        let tty = sanitize(attachment.tty)
        guard guid != nil || tty != nil else {
            throw TerminalJumpError.sessionNotFound("no GUID or tty recorded yet — run one agent turn first")
        }

        let script = """
        on run
            tell application "iTerm2"
                activate
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set matched to false
                            \(guid.map { "if id of s is \"\($0)\" then set matched to true" } ?? "")
                            \(tty.map { "if tty of s is \"\($0)\" then set matched to true" } ?? "")
                            if matched then
                                select s
                                select t
                                select w
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "notfound"
        end run
        """

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw TerminalJumpError.scriptFailure("could not compile script")
        }
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743: errAEEventNotPermitted (user declined Automation).
            if code == -1743 { throw TerminalJumpError.automationDenied }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "error \(code)"
            throw TerminalJumpError.scriptFailure(message)
        }
        if result.stringValue == "notfound" {
            throw TerminalJumpError.sessionNotFound(
                "tab closed, or session moved to another profile")
        }
    }

    /// AppleScript string-literal hardening: GUIDs and ttys are
    /// alphanumeric/dash/slash; strip anything else defensively.
    private func sanitize(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-/._:"))
        let cleaned = String(value.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? nil : cleaned
    }
}
