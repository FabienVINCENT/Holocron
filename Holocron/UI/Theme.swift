import SwiftUI

/// Dark, notch-native visual language. The panel always renders dark (it
/// visually extends the notch), regardless of the system appearance.
enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let surfaceHighlight = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let textPrimary = Color(white: 0.96)
    static let textSecondary = Color(white: 0.62)
    static let textTertiary = Color(white: 0.42)
    static let accent = Color(red: 0.42, green: 0.62, blue: 1.0)

    static let cornerRadius: CGFloat = 18

    static func color(for status: SessionStatus) -> Color {
        switch status {
        case .running: return Color(red: 0.35, green: 0.78, blue: 0.5)
        case .waitingPermission: return Color(red: 1.0, green: 0.36, blue: 0.34)
        case .waitingQuestion: return Color(red: 1.0, green: 0.72, blue: 0.25)
        case .waitingInput: return Color(red: 0.42, green: 0.62, blue: 1.0)
        case .idle: return Color(white: 0.45)
        case .done: return Color(white: 0.3)
        }
    }

    static func label(for status: SessionStatus) -> String {
        switch status {
        case .running: return "running"
        case .waitingPermission: return "permission"
        case .waitingQuestion: return "question"
        case .waitingInput: return "your turn"
        case .idle: return "idle"
        case .done: return "done"
        }
    }
}

extension TimeInterval {
    /// "2h 04m", "7m 12s", "43s"
    var compactDuration: String {
        let seconds = Int(self)
        if seconds >= 3600 {
            return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
        }
        if seconds >= 60 {
            return String(format: "%dm %02ds", seconds / 60, seconds % 60)
        }
        return "\(max(seconds, 0))s"
    }
}
