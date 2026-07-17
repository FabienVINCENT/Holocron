import SwiftUI

struct SessionRowView: View {
    let state: AppState
    let session: AgentSession
    @State private var hovering = false

    var body: some View {
        let pending = state.center.interaction(forSession: session.id)
        let status = state.store.status(of: session, pending: pending)
        let attachment = state.store.attachments[session.id]

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.color(for: status))
                    .frame(width: 8, height: 8)

                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if let branch = session.gitBranch, !branch.isEmpty {
                    Text(branch)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                badge(attachment: attachment)

                Spacer()

                Text(Theme.label(for: status))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.color(for: status))

                if let duration = session.duration {
                    Text(duration.compactDuration)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }

                Button {
                    state.jump(to: session)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                        .foregroundStyle(hovering ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Jump to the iTerm2 tab of this session")
            }

            if let text = primaryLine {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            if let activity = activityLine {
                Text(activity)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? Theme.surfaceHighlight : Theme.surface)
        )
        .onHover { hovering = $0 }
        .onTapGesture { state.jump(to: session) }
    }

    private func badge(attachment: TerminalAttachment?) -> some View {
        let isOrca = attachment?.isOrca ?? (session.agentKind == .orca)
        return Text(isOrca ? "orca" : "claude")
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .foregroundStyle(isOrca ? Theme.color(for: .waitingQuestion) : Theme.accent)
    }

    private var primaryLine: String? {
        session.lastAssistantText ?? session.lastUserPrompt
    }

    private var activityLine: String? {
        if let tool = session.runningTools.last {
            return "▶ \(tool.name) \(tool.detail)"
        }
        if let command = session.recentCommands.last {
            return "$ \(command)"
        }
        if let file = session.recentFiles.last {
            return "✎ \((file as NSString).lastPathComponent)"
        }
        return nil
    }
}
