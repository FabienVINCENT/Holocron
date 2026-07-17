import SwiftUI

/// Expanded state: pending card (if any) + session list + usage footer.
struct ExpandedPanelView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 10) {
            header
                // Keep the header clear of the hardware notch.
                .padding(.top, state.screenHasNotch ? 34 : 10)

            if let card = state.center.frontCard {
                InteractionCardView(state: state, card: card)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            sessionList

            UsageFooterView(state: state)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.center.pending.count)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(Theme.accent)
                .font(.system(size: 12))
            Text("Holocron")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            if state.center.pending.count > 1 {
                Text("\(state.center.pending.count) pending")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.color(for: .waitingPermission).opacity(0.25)))
                    .foregroundStyle(Theme.color(for: .waitingPermission))
            }
            Spacer()
            if !state.hooksInstalled {
                Button {
                    state.installHooks()
                } label: {
                    Label("Install hooks", systemImage: "link.badge.plus")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.color(for: .waitingQuestion))
                .help("Permissions won't reach the notch until Claude Code hooks are installed.")
            }
            // Not SettingsLink: this view lives in an NSPanel outside the
            // SwiftUI scene hierarchy, where the openSettings action is absent.
            Button {
                state.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionList: some View {
        let sessions = state.store.displaySessions(pendingSessionIds: state.center.pendingSessionIds)
        return Group {
            if sessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No Claude sessions in the last \(state.settings.retentionHours)h")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Start `claude` in a terminal — sessions appear here automatically.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(sessions) { session in
                            SessionRowView(state: state, session: session)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity)
    }
}
