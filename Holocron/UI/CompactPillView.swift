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
            // Urgent: fast red pulse with a halo.
            PulsingDot(
                color: Theme.color(for: .waitingPermission),
                size: 9, halo: true, period: 0.55, minScale: 0.8, maxScale: 1.25
            )
            .accessibilityLabel("Waiting for your decision")
        } else if activeCount > 0 {
            // Alive: slow green breathing while agents work.
            PulsingDot(
                color: Theme.color(for: .running),
                size: 7, halo: false, period: 1.3, minScale: 0.8, maxScale: 1.15
            )
        } else {
            Circle()
                .fill(Theme.textTertiary)
                .frame(width: 7, height: 7)
        }
    }
}

/// Breathing status dot — the "alive" signal of the compact pill.
struct PulsingDot: View {
    let color: Color
    let size: CGFloat
    let halo: Bool
    let period: Double
    let minScale: CGFloat
    let maxScale: CGFloat
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if halo {
                Circle()
                    .stroke(color.opacity(pulsing ? 0.15 : 0.55), lineWidth: 3)
                    .frame(width: size + 7, height: size + 7)
                    .scaleEffect(pulsing ? 1.25 : 0.9)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .scaleEffect(pulsing ? maxScale : minScale)
                .opacity(pulsing ? 1 : 0.65)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .onDisappear { pulsing = false }
    }
}
