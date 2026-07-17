import SwiftUI

/// Settings rendered inside the notch panel (no separate window).
struct SettingsPanelView: View {
    @Bindable var settings: AppSettings
    let state: AppState
    @State private var extraDirsText: String

    init(state: AppState) {
        self.state = state
        self.settings = state.settings
        _extraDirsText = State(initialValue: state.settings.additionalTranscriptDirs.joined(separator: "\n"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hooksSection
                interceptionSection
                sessionsSection
                soundsSection
                miscSection
                updatesSection
                hookDebugSection
                probeSection
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Building blocks

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        }
    }

    private func row(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textPrimary)
    }

    // MARK: - Sections

    private var hooksSection: some View {
        section("Claude Code hooks") {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.hooksInstalled ? Theme.color(for: .running) : Theme.color(for: .waitingQuestion))
                    .frame(width: 8, height: 8)
                Text(state.hooksInstalled ? "Installed" : "Not installed")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if state.hooksInstalled {
                    Button("Reinstall") { state.installHooks() }
                    Button("Uninstall") { state.uninstallHooks() }
                } else {
                    Button("Install") { state.installHooks() }
                }
            }
            .controlSize(.small)
            if let error = state.hookServerError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.color(for: .waitingPermission))
            }
            Text("Written to ~/.claude/settings.json (backup kept). Helper: ~/Library/Application Support/Holocron/bin.")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var interceptionSection: some View {
        section("Permissions in the notch") {
            row("Route permission prompts to the notch", isOn: $settings.interceptPermissions)
            row("Answer AskUserQuestion from the notch", isOn: $settings.answerQuestionsFromNotch)
            HStack {
                Text("Intercepted tools")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                TextField("matcher", text: $settings.interceptMatcher)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
            }
            Stepper(
                "Card timeout: \(settings.decisionTimeoutSeconds)s",
                value: $settings.decisionTimeoutSeconds, in: 10...570, step: 10
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.textPrimary)
            Picker("On timeout", selection: $settings.timeoutAction) {
                Text("Back to terminal prompt").tag(HookReply.Action.passthrough)
                Text("Deny").tag(HookReply.Action.deny)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            Text("Changing the matcher requires Reinstall. Question answers travel as structured deny-feedback (hooks expose no answer API).")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var sessionsSection: some View {
        section("Sessions") {
            Stepper("Idle after \(settings.idleAfterMinutes) min",
                    value: $settings.idleAfterMinutes, in: 5...240, step: 5)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
            Stepper("Hide after \(settings.retentionHours) h",
                    value: $settings.retentionHours, in: 1...72)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary)
            Text("Additional transcript directories (one per line, e.g. for Orca):")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            TextEditor(text: $extraDirsText)
                .font(.system(size: 10, design: .monospaced))
                .frame(height: 44)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.4)))
            Button("Apply directories") {
                settings.additionalTranscriptDirs = extraDirsText
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                state.store.reloadRoots()
            }
            .controlSize(.small)
        }
    }

    private var soundsSection: some View {
        section("8-bit sounds") {
            HStack {
                Image(systemName: "speaker.wave.1")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: $settings.soundMasterVolume, in: 0...1)
                    .controlSize(.small)
            }
            soundRow("Permission requested", isOn: $settings.soundOnPermission, alert: .permissionRequested)
            soundRow("Question asked", isOn: $settings.soundOnQuestion, alert: .questionAsked)
            soundRow("Turn done", isOn: $settings.soundOnDone, alert: .sessionDone)
            soundRow("Error", isOn: $settings.soundOnError, alert: .error)
        }
    }

    private func soundRow(_ label: String, isOn: Binding<Bool>, alert: SoundEngine.Alert) -> some View {
        HStack {
            row(label, isOn: isOn)
            Spacer()
            Button {
                state.sound.volume = settings.soundMasterVolume
                state.sound.play(alert)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var miscSection: some View {
        section("Shortcuts & alerts") {
            row("⌃⌥H toggles the panel", isOn: $settings.panelHotkeyEnabled)
            row("⌘Y/⌘N & ⌘1…⌘4 while a card is pending", isOn: $settings.decisionHotkeysEnabled)
            row("macOS notification on new card", isOn: $settings.systemNotifications)
            row("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            row("Launch at login", isOn: Binding(
                get: { state.launchAtLoginEnabled },
                set: { state.setLaunchAtLogin($0) }
            ))
        }
    }

    private var updatesSection: some View {
        section("Updates") {
            HStack {
                if state.updater?.isConfigured == true {
                    Button("Check for updates…") { state.updater?.checkForUpdates() }
                        .controlSize(.small)
                        .disabled(state.updater?.canCheckForUpdates != true)
                } else {
                    Text("Updater disabled (no Sparkle key in this build).")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var hookDebugSection: some View {
        section("Hook debug (last events)") {
            let events = Array(state.center.recentHookEvents.suffix(8).reversed())
            if events.isEmpty {
                Text("No hook traffic yet — start a new claude session with hooks installed.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                    Text(event)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Button("Reveal log files") {
                NSWorkspace.shared.open(HookDebugLog.directory())
            }
            .controlSize(.small)
        }
    }

    private var probeSection: some View {
        section("Claude desktop app (investigation)") {
            Button("Probe local surfaces") { state.runDesktopProbe() }
                .controlSize(.small)
            ForEach(state.probeFindings) { finding in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: finding.exists ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(finding.exists ? Theme.color(for: .running) : Theme.textTertiary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.surface)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(finding.detail)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Text("Read-only. See docs/CLAUDE-DESKTOP-FEASIBILITY.md — monitoring the desktop app is not part of v1.")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
