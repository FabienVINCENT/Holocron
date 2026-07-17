import Foundation

/// Local token accounting across sessions.
///
/// HONEST LIMITATION (see README): Anthropic rate limits (5-hour window,
/// weekly caps) are enforced server-side and are NOT exposed on disk by
/// Claude Code — there is no local file with "remaining quota". What CAN be
/// computed locally, from transcript `usage` blocks, is exactly what this
/// does: tokens consumed per rolling window. It is a burn-rate gauge, not a
/// quota gauge, and the UI labels it as such.
struct UsageAggregator {
    struct Window: Sendable, Equatable {
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheCreation = 0
        var sessionCount = 0

        var total: Int { input + output + cacheRead + cacheCreation }
        /// Output tokens dominate rate-limit weight; shown prominently.
        var totalNonCache: Int { input + output }
    }

    /// Sum usage across sessions active within the trailing `window`.
    /// Session-level granularity (not per-message) keeps this O(sessions);
    /// good enough for a burn gauge.
    static func rollingWindow(
        sessions: [AgentSession],
        window: TimeInterval = 5 * 3600,
        now: Date = Date()
    ) -> Window {
        var result = Window()
        let cutoff = now.addingTimeInterval(-window)
        for session in sessions {
            guard let last = session.lastActivityAt, last >= cutoff else { continue }
            result.input += session.usage.input
            result.output += session.usage.output
            result.cacheRead += session.usage.cacheRead
            result.cacheCreation += session.usage.cacheCreation
            result.sessionCount += 1
        }
        return result
    }

    static func format(tokens: Int) -> String {
        switch tokens {
        case ..<1000: return "\(tokens)"
        case ..<1_000_000: return String(format: "%.1fk", Double(tokens) / 1000)
        default: return String(format: "%.2fM", Double(tokens) / 1_000_000)
        }
    }
}
