import SwiftUI

/// The front pending card: permission request, plan review, question, or a
/// degraded-mode "answer in terminal" alert.
struct InteractionCardView: View {
    let state: AppState
    let card: PendingInteraction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            switch card.kind {
            case .permission(let toolName, let detail, _):
                permissionBody(toolName: toolName, detail: detail)
            case .planReview(let plan):
                planBody(plan: plan)
            case .question(let input):
                questionBody(input: input)
            case .terminalPrompt(let message):
                terminalPromptBody(message: message)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor.opacity(0.6), lineWidth: 1)
                )
        )
    }

    private var accentColor: Color {
        switch card.kind {
        case .question, .planReview: return Theme.color(for: .waitingQuestion)
        case .permission, .terminalPrompt: return Theme.color(for: .waitingPermission)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundStyle(accentColor)
            Text(card.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(projectLabel)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            Button {
                state.center.dismiss(card)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Dismiss — the terminal prompt takes over")
        }
    }

    private var iconName: String {
        switch card.kind {
        case .permission: return "lock.shield"
        case .planReview: return "list.clipboard"
        case .question: return "questionmark.bubble"
        case .terminalPrompt: return "terminal"
        }
    }

    private var projectLabel: String {
        guard let cwd = card.cwd, !cwd.isEmpty else { return "" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    // MARK: - Permission

    private func permissionBody(toolName: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !detail.isEmpty {
                ScrollView {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 110)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.4)))
            }
            decisionButtons
        }
    }

    private func planBody(plan: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                MarkdownBlockView(markdown: plan)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.4)))
            decisionButtons
        }
    }

    private var decisionButtons: some View {
        HStack(spacing: 8) {
            Button {
                state.center.allow(card)
            } label: {
                HStack(spacing: 4) {
                    Text("Allow")
                    shortcutBadge("⌘Y")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DecisionButtonStyle(color: Theme.color(for: .running)))

            Button {
                state.center.deny(card)
            } label: {
                HStack(spacing: 4) {
                    Text("Deny")
                    shortcutBadge("⌘N")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DecisionButtonStyle(color: Theme.color(for: .waitingPermission)))
        }
    }

    // MARK: - Question

    private func questionBody(input: AskUserQuestionInput) -> some View {
        // v1 renders the first question; multi-question calls fall back to the
        // terminal via Dismiss.
        VStack(alignment: .leading, spacing: 8) {
            if let question = input.questions.first {
                Text(question.text)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(question.options.prefix(4).enumerated()), id: \.offset) { index, option in
                    Button {
                        state.center.answer(card, selectedLabels: [option.label])
                    } label: {
                        HStack(spacing: 6) {
                            shortcutBadge("⌘\(index + 1)")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                if let description = option.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceHighlight))
                    }
                    .buttonStyle(.plain)
                }
                if input.questions.count > 1 {
                    Text("+\(input.questions.count - 1) more question(s) — answer in the terminal")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // MARK: - Degraded mode

    private func terminalPromptBody(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
            Button {
                if let session = state.store.session(withId: card.sessionId) {
                    state.jump(to: session)
                }
                state.center.dismiss(card)
            } label: {
                HStack {
                    Image(systemName: "arrow.up.forward.square")
                    Text("Jump to terminal")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DecisionButtonStyle(color: Theme.accent))
        }
    }

    private func shortcutBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)))
            .foregroundStyle(Theme.textSecondary)
    }
}

struct DecisionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(configuration.isPressed ? 0.55 : 0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.5), lineWidth: 1)
            )
    }
}
