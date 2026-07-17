import SwiftUI

/// Collapsed state: a slim pill around/below the notch showing the number of
/// active sessions and an attention indicator.
///
/// Layout depends on the screen: on a notched MacBook the middle of the pill
/// is hidden behind the hardware notch, so the indicators sit in the "wings"
/// on both sides. On screens without a notch the pill is a compact centered
/// cluster.
struct CompactPillView: View {
    let state: AppState

    var body: some View {
        let sessions = state.store.displaySessions(pendingSessionIds: state.center.pendingSessionIds)
        let activeCount = sessions.filter { session in
            let status = state.store.status(
                of: session,
                pending: state.center.interaction(forSession: session.id)
            )
            return status == .running || status.needsAttention
        }.count
        let needsAttention = !state.center.pending.isEmpty

        Group {
            if state.screenHasNotch {
                HStack {
                    counter(activeCount)
                    Spacer(minLength: 0)  // hidden behind the hardware notch
                    indicator(needsAttention: needsAttention, activeCount: activeCount)
                }
            } else {
                HStack(spacing: 10) {
                    counter(activeCount)
                    indicator(needsAttention: needsAttention, activeCount: activeCount)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func counter(_ count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private func indicator(needsAttention: Bool, activeCount: Int) -> some View {
        if needsAttention {
            ZStack {
                Circle()
                    .fill(Theme.color(for: .waitingPermission))
                    .frame(width: 9, height: 9)
                Circle()
                    .stroke(Theme.color(for: .waitingPermission).opacity(0.5), lineWidth: 3)
                    .frame(width: 15, height: 15)
            }
            .accessibilityLabel("Waiting for your decision")
        } else if activeCount > 0 {
            Circle()
                .fill(Theme.color(for: .running))
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 7, height: 7)
        }
    }
}
