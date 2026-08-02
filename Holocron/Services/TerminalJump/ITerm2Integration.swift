import AppKit
import Foundation

/// Jumps to the exact iTerm2 window/tab/split of a session.
///
/// Matching strategy (in order):
/// 1. **Session GUID** — the hook binary inherits `ITERM_SESSION_ID`
///    (`w0t2p0:GUID`) from the shell that launched `claude`; the GUID equals
///    the AppleScript `id` of the iTerm2 session. Exact, survives tab moves.
/// 2. **tty** — the hook also records its controlling terminal
///    (`/dev/ttys0NN`), matched against each session's `tty`.
/// 3. **cwd-discovered tty** — hook-free fallback resolved by
///    `TerminalJumpService` via ProcessLocator.
struct ITerm2Integration: TerminalIntegration {
    let name = "iTerm2"

    func canHandle(_ attachment: TerminalAttachment?) -> Bool {
        guard let attachment else { return false }
        return attachment.termProgram == "iTerm.app" || attachment.itermGUID != nil
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?) throws {
        try jump(to: attachment, cwd: cwd, discoveredTTY: nil)
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?, discoveredTTY: String?) throws {
        let guid = AppleScriptRunner.sanitize(attachment?.itermGUID)
        var tty = AppleScriptRunner.sanitize(attachment?.tty ?? discoveredTTY)
        if guid == nil, tty == nil, let cwd {
            tty = AppleScriptRunner.sanitize(ProcessLocator.ttyOfClaudeProcess(cwd: cwd))
        }
        guard guid != nil || tty != nil else {
            throw TerminalJumpError.sessionNotFound(
                "no ITERM_SESSION_ID/tty recorded and no running claude process matches "
                + (cwd ?? "this session"))
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

        let result = try AppleScriptRunner.run(script, appName: "iTerm2")
        if result == "notfound" {
            throw TerminalJumpError.sessionNotFound(
                "no iTerm2 session matches (tab closed?)")
        }
    }
}
