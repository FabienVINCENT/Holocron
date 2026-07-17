import SwiftUI

/// Token burn over the trailing 5-hour window (the shape of Anthropic's
/// short rate-limit window). Explicitly a consumption gauge: the actual
/// remaining server-side quota is not available locally (see README).
struct UsageFooterView: View {
    let state: AppState

    var body: some View {
        let window = UsageAggregator.rollingWindow(sessions: state.store.sessions)
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Text("5h: \(UsageAggregator.format(tokens: window.totalNonCache)) tokens")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text("(in \(UsageAggregator.format(tokens: window.input)) · out \(UsageAggregator.format(tokens: window.output)) · cache \(UsageAggregator.format(tokens: window.cacheRead)))")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text("\(window.sessionCount) session\(window.sessionCount > 1 ? "s" : "")")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
        .help("""
        Local burn gauge computed from transcripts. Anthropic's real rate-limit \
        quota is server-side only and not exposed on disk — Holocron shows \
        consumption, not remaining quota.
        """)
        .padding(.horizontal, 4)

        if let error = state.lastJumpError ?? state.hookServerError {
            Text(error)
                .font(.system(size: 9))
                .foregroundStyle(Theme.color(for: .waitingPermission))
                .lineLimit(2)
                .padding(.horizontal, 4)
        }
    }
}
