import Foundation

/// A terminal emulator Holocron can jump into. v1 ships iTerm2 only; add
/// Ghostty / Terminal.app by conforming and appending to
/// `TerminalJumpService.integrations`.
protocol TerminalIntegration {
    var name: String { get }
    /// Can this integration try to locate the given attachment?
    func canHandle(_ attachment: TerminalAttachment?) -> Bool
    /// Bring the right window/tab/split to front. Throws with a
    /// user-presentable message on failure.
    func jump(to attachment: TerminalAttachment?, cwd: String?) throws
}

enum TerminalJumpError: LocalizedError {
    case noIntegration
    case sessionNotFound(String)
    case scriptFailure(String)
    case automationDenied

    var errorDescription: String? {
        switch self {
        case .noIntegration:
            return "No supported terminal found for this session (v1 supports iTerm2)."
        case .sessionNotFound(let detail):
            return "Could not locate the terminal session (\(detail))."
        case .scriptFailure(let message):
            return "AppleScript failed: \(message)"
        case .automationDenied:
            return "Automation permission for iTerm2 was denied. "
                + "Enable it in System Settings → Privacy & Security → Automation → Holocron."
        }
    }
}

@MainActor
final class TerminalJumpService {
    private let integrations: [TerminalIntegration]

    init(integrations: [TerminalIntegration] = [ITerm2Integration()]) {
        self.integrations = integrations
    }

    func jump(to attachment: TerminalAttachment?, cwd: String?) throws {
        guard let integration = integrations.first(where: { $0.canHandle(attachment) }) else {
            throw TerminalJumpError.noIntegration
        }
        try integration.jump(to: attachment, cwd: cwd)
    }
}
