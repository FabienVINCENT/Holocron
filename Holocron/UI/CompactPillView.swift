import SwiftUI

/// Collapsed state: a slim pill around/below the notch showing the number of
/// active sessions and an attention indicator.
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

        HStack {
            // Left wing
            HStack(spacing: 5) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
                Text("\(activeCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }

            // Middle: hidden behind the hardware notch on notched screens.
            Spacer(minLength: 0)

            // Right wing
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
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 5)
    }
}
