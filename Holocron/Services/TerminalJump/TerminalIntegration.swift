import Foundation

/// A terminal/host Holocron can jump into. Integrations are tried in
/// order; the first whose `canHandle` accepts the attachment wins.
protocol TerminalIntegration {
    var name: String { get }
    /// Can this integration locate the given session host?
    func canHandle(_ attachment: TerminalAttachment?) -> Bool
    /// Bring the right window/tab/split (or app) to front. Throws with a
    /// user-presentable message on failure.
    func jump(to attachment: TerminalAttachment?, cwd: String?) throws
}

enum TerminalJumpError: LocalizedError {
    case noIntegration
    case sessionNotFound(String)
    case scriptFailure(String)
    case automationDenied(String)

    var errorDescription: String? {
        switch self {
        case .noIntegration:
            return "Could not identify where this session runs "
                + "(no terminal/IDE recorded and no matching claude process)."
        case .sessionNotFound(let detail):
            return "Could not locate the session (\(detail))."
        case .scriptFailure(let message):
            return "AppleScript failed: \(message)"
        case .automationDenied(let app):
            return "Automation permission for \(app) was denied. "
                + "Enable it in System Settings → Privacy & Security → Automation → Holocron."
        }
    }
}

@MainActor
final class TerminalJumpService {
    /// Order matters: most specific host markers first. Orca sessions carry
    /// the markers of whatever launched Orca, so they route naturally.
    private let integrations: [TerminalIntegration]

    init(integrations: [TerminalIntegration] = [
        ITerm2Integration(),
        TerminalAppIntegration(),
        JetBrainsIntegration(),
        ClaudeDesktopIntegration(),
    ]) {
        self.integrations = integrations
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?) throws {
        if let integration = integrations.first(where: { $0.canHandle(attachment) }) {
            try integration.jump(to: attachment, cwd: cwd)
            return
        }
        // No host markers at all (hooks not installed / session predates
        // them): locate a running claude process by cwd and try the
        // terminals that can match a tty.
        if let cwd, let tty = ProcessLocator.ttyOfClaudeProcess(cwd: cwd) {
            do {
                try ITerm2Integration().jump(to: nil, cwd: cwd, discoveredTTY: tty)
            } catch {
                try TerminalAppIntegration().jump(tty: tty)
            }
            return
        }
        throw TerminalJumpError.noIntegration
    }
}

/// Shared helper: run an AppleScript source, mapping the Automation-denied
/// error (-1743) to a user-actionable message.
enum AppleScriptRunner {
    @discardableResult
    static func run(_ source: String, appName: String) throws -> String? {
        guard let script = NSAppleScript(source: source) else {
            throw TerminalJumpError.scriptFailure("could not compile script")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 { throw TerminalJumpError.automationDenied(appName) }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "error \(code)"
            throw TerminalJumpError.scriptFailure(message)
        }
        return result.stringValue
    }

    /// Defensive string sanitizer for values interpolated into scripts.
    static func sanitize(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-/._:"))
        let cleaned = String(value.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? nil : cleaned
    }
}

/// Launch/activate helper built on /usr/bin/open.
enum AppActivator {
    /// `open -b <bundleId> [path]` — activates the app; with a path,
    /// JetBrains IDEs focus (or open) the matching project window.
    static func open(bundleId: String, path: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var arguments = ["-b", bundleId]
        if let path { arguments.append(path) }
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw TerminalJumpError.sessionNotFound(
                "could not activate \(bundleId) (is the app installed?)")
        }
    }
}
