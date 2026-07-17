import SwiftUI

struct SettingsView: View {
    let state: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(state: state)
                .tabItem { Label("General", systemImage: "gearshape") }
            PermissionSettingsTab(state: state)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            SoundSettingsTab(state: state)
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            AdvancedSettingsTab(state: state)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var settings: AppSettings
    let state: AppState
    @State private var extraDirsText: String

    init(state: AppState) {
        self.state = state
        self.settings = state.settings
        _extraDirsText = State(initialValue: state.settings.additionalTranscriptDirs.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("Sessions") {
                Stepper("Idle after \(settings.idleAfterMinutes) min without activity",
                        value: $settings.idleAfterMinutes, in: 5...240, step: 5)
                Stepper("Hide sessions after \(settings.retentionHours) h",
                        value: $settings.retentionHours, in: 1...72)
            }
            Section {
                TextEditor(text: $extraDirsText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 70)
                Button("Apply directories") {
                    settings.additionalTranscriptDirs = extraDirsText
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    state.store.reloadRoots()
                }
            } header: {
                Text("Additional session directories")
            } footer: {
                Text("One absolute path per line. Use this if Orca stores Claude Code transcripts outside ~/.claude/projects.")
                    .font(.caption)
            }
            Section("Shortcuts") {
                Toggle("⌃⌥H toggles the notch panel", isOn: $settings.panelHotkeyEnabled)
                Toggle("⌘Y/⌘N and ⌘1…⌘4 while a card is pending (captured system-wide during that window)",
                       isOn: $settings.decisionHotkeysEnabled)
            }
            Section("Alerts") {
                Toggle("macOS notification when a card appears", isOn: $settings.systemNotifications)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionSettingsTab: View {
    @Bindable var settings: AppSettings
    let state: AppState

    init(state: AppState) {
        self.state = state
        self.settings = state.settings
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Claude Code hooks") {
                    HStack {
                        Circle()
                            .fill(state.hooksInstalled ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(state.hooksInstalled ? "Installed" : "Not installed")
                        Spacer()
                        if state.hooksInstalled {
                            Button("Reinstall") { state.installHooks() }
                            Button("Uninstall") { state.uninstallHooks() }
                        } else {
                            Button("Install") { state.installHooks() }
                        }
                    }
                }
                if let error = state.hookServerError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            } footer: {
                Text("Hooks are written to ~/.claude/settings.json (existing content preserved, backup created). The helper binary lives in ~/Library/Application Support/Holocron/bin.")
                    .font(.caption)
            }

            Section("Interception") {
                Toggle("Route permission prompts to the notch", isOn: $settings.interceptPermissions)
                TextField("Intercepted tools (hook matcher)", text: $settings.interceptMatcher)
                    .font(.system(size: 11, design: .monospaced))
                Toggle("Answer AskUserQuestion from the notch", isOn: $settings.answerQuestionsFromNotch)
                Text("Question answers travel back as structured deny-feedback (hooks have no official answer API). Changing the matcher requires Reinstall.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Timeout") {
                Stepper("Auto-resolve cards after \(settings.decisionTimeoutSeconds)s",
                        value: $settings.decisionTimeoutSeconds, in: 10...570, step: 10)
                Picker("On timeout", selection: $settings.timeoutAction) {
                    Text("Hand back to terminal prompt (safe)").tag(HookReply.Action.passthrough)
                    Text("Deny the tool call").tag(HookReply.Action.deny)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SoundSettingsTab: View {
    @Bindable var settings: AppSettings
    let state: AppState

    init(state: AppState) {
        self.state = state
        self.settings = state.settings
    }

    var body: some View {
        Form {
            Section("8-bit alerts") {
                Slider(value: $settings.soundMasterVolume, in: 0...1) {
                    Text("Volume")
                }
                soundRow("Permission requested", isOn: $settings.soundOnPermission, alert: .permissionRequested)
                soundRow("Question asked", isOn: $settings.soundOnQuestion, alert: .questionAsked)
                soundRow("Turn / session done", isOn: $settings.soundOnDone, alert: .sessionDone)
                soundRow("Error", isOn: $settings.soundOnError, alert: .error)
            }
        }
        .formStyle(.grouped)
    }

    private func soundRow(_ label: String, isOn: Binding<Bool>, alert: SoundEngine.Alert) -> some View {
        HStack {
            Toggle(label, isOn: isOn)
            Spacer()
            Button {
                state.sound.volume = settings.soundMasterVolume
                state.sound.play(alert)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct AdvancedSettingsTab: View {
    let state: AppState

    var body: some View {
        Form {
            Section {
                Button("Check for updates…") { state.updater?.checkForUpdates() }
            } header: {
                Text("Updates (Sparkle)")
            } footer: {
                Text("Updates are EdDSA-signed and served from GitHub Releases. The app is not notarized yet — see the README for the Gatekeeper note.")
                    .font(.caption)
            }

            Section {
                Button("Probe Claude desktop app surfaces") { state.runDesktopProbe() }
                ForEach(state.probeFindings) { finding in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: finding.exists ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(finding.exists ? .green : .secondary)
                                .font(.caption)
                            Text(finding.surface).font(.caption.bold())
                        }
                        Text(finding.path).font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(finding.detail).font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Claude desktop app (investigation)")
            } footer: {
                Text("Read-only survey of what the official desktop app exposes locally. Monitoring it is NOT part of v1 — see docs/CLAUDE-DESKTOP-FEASIBILITY.md.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
