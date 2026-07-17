import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// Composition root: owns every layer and wires them together. Created once
/// at launch; UI reads it via Observation.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let settings: AppSettings
    let store: SessionStore
    let center: InteractionCenter

    @ObservationIgnored let sound = SoundEngine()
    @ObservationIgnored let notifications = NotificationService()
    @ObservationIgnored let hotKeys = HotKeyManager()
    @ObservationIgnored let terminalJump = TerminalJumpService()
    @ObservationIgnored let hookInstaller = HookInstaller()
    @ObservationIgnored private(set) var hookServer: HookServer?
    @ObservationIgnored private(set) var updater: Updater?
    @ObservationIgnored private(set) var panelController: NotchPanelController?

    // UI state shared with the panel controller.
    var panelExpanded = false
    var screenHasNotch = false
    var compactSize = NotchPanelController.compactFallbackSize
    var showingSettings = false
    var hooksInstalled = false
    var hookServerError: String?
    var lastJumpError: String?
    var probeFindings: [ClaudeDesktopProbe.Finding] = []

    @ObservationIgnored private var decisionHotkeyTokens: [UInt32] = []
    @ObservationIgnored private var panelHotkeyToken: UInt32?

    private init() {
        let settings = AppSettings()
        let store = SessionStore(settings: settings)
        self.settings = settings
        self.store = store
        self.center = InteractionCenter(settings: settings, store: store)
    }

    // MARK: - Boot

    func bootstrap() {
        sound.volume = settings.soundMasterVolume
        store.start()
        startHookServer()
        wireInteractionCenter()
        updater = Updater()
        notifications.requestAuthorizationIfNeeded()

        let panel = NotchPanelController(state: self)
        panelController = panel
        panel.show()

        registerPanelHotkey()
        hooksInstalled = hookInstaller.isInstalled
        if hooksInstalled {
            // Keep the installed helper binary in sync with this app version
            // (new hook features ship inside it, e.g. host markers for jump).
            try? hookInstaller.copyHookBinary()
        }
        offerHookInstallOnFirstRun()
    }

    func shutdown() {
        hookServer?.stop()
        store.stop()
    }

    private func startHookServer() {
        let server = HookServer()
        do {
            try server.start()
            server.onEnvelope = { [weak self] envelope, reply in
                self?.center.handle(envelope, reply: reply)
            }
            hookServer = server
        } catch {
            hookServerError = "Hook server failed to start: \(error.localizedDescription)"
        }
    }

    private func wireInteractionCenter() {
        center.onCardAppeared = { [weak self] card in
            guard let self else { return }
            switch card.kind {
            case .permission, .planReview, .terminalPrompt:
                if self.settings.soundOnPermission { self.playSound(.permissionRequested) }
            case .question:
                if self.settings.soundOnQuestion { self.playSound(.questionAsked) }
            }
            self.panelController?.presentAttention()
            self.registerDecisionHotkeys()
            if self.settings.systemNotifications {
                let project = self.store.session(withId: card.sessionId)?.projectName ?? "session"
                self.notifications.post(title: card.title, body: project)
            }
        }
        center.onCardResolved = { [weak self] _ in
            guard let self else { return }
            if self.center.pending.isEmpty {
                self.unregisterDecisionHotkeys()
                // Keep the panel pinned while the settings page is open.
                if !self.showingSettings {
                    self.panelController?.releaseAttention()
                }
            } else {
                self.registerDecisionHotkeys()  // rebind to the new front card
            }
        }
        center.onTurnEnded = { [weak self] _ in
            guard let self else { return }
            if self.settings.soundOnDone { self.playSound(.sessionDone) }
        }
        center.onSessionError = { [weak self] _ in
            guard let self else { return }
            if self.settings.soundOnError { self.playSound(.error) }
        }
    }

    private func playSound(_ alert: SoundEngine.Alert) {
        sound.volume = settings.soundMasterVolume
        sound.play(alert)
    }

    // MARK: - Hooks lifecycle

    private func offerHookInstallOnFirstRun() {
        let key = "didOfferHookInstall"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !hooksInstalled else { return }

        let alert = NSAlert()
        alert.messageText = "Connect Holocron to Claude Code?"
        alert.informativeText = """
        Holocron installs hooks in ~/.claude/settings.json so permission \
        prompts and questions appear in the notch. Your existing settings are \
        preserved and a backup is written. You can uninstall at any time from \
        Settings.
        """
        alert.addButton(withTitle: "Install hooks")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            installHooks()
        }
    }

    func installHooks() {
        do {
            try hookInstaller.install(interceptMatcher: settings.interceptMatcher)
            hooksInstalled = true
            hookServerError = nil
        } catch {
            hooksInstalled = false
            hookServerError = error.localizedDescription
        }
    }

    func uninstallHooks() {
        do {
            try hookInstaller.uninstall()
            hooksInstalled = false
        } catch {
            hookServerError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func jump(to session: AgentSession) {
        lastJumpError = nil
        do {
            try terminalJump.jump(to: store.attachments[session.id], cwd: session.cwd)
        } catch {
            lastJumpError = error.localizedDescription
            if settings.soundOnError { playSound(.error) }
        }
    }

    func runDesktopProbe() {
        probeFindings = ClaudeDesktopProbe.run()
    }

    func togglePanel() {
        panelController?.toggle()
    }

    // MARK: - Launch at login (SMAppService)

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            hookServerError = "Launch at login: \(error.localizedDescription)"
        }
    }

    /// Settings render as a page INSIDE the notch panel — no separate
    /// window, no app activation, nothing to crash. (Separate NSWindows
    /// spawned from the non-activating panel proved crash-prone.)
    func openSettings() {
        showingSettings = true
        panelController?.presentAttention()  // pin the panel open
    }

    func closeSettings() {
        showingSettings = false
        if center.pending.isEmpty {
            panelController?.releaseAttention()
        }
    }

    // MARK: - Hotkeys

    private func registerPanelHotkey() {
        guard settings.panelHotkeyEnabled, panelHotkeyToken == nil else { return }
        panelHotkeyToken = hotKeys.register(
            keyCode: Keys.h,
            carbonModifiers: Keys.controlOption
        ) { [weak self] in
            self?.togglePanel()
        }
    }

    /// ⌘Y / ⌘N / ⌘1…⌘4 — captured system-wide ONLY while a card is pending.
    private func registerDecisionHotkeys() {
        unregisterDecisionHotkeys()
        guard settings.decisionHotkeysEnabled, let card = center.frontCard else { return }

        switch card.kind {
        case .permission, .planReview:
            if card.isAnswerable {
                let id = card.id
                register(Keys.y, Keys.cmd) { [weak self] in
                    guard let self, let card = self.center.pending.first(where: { $0.id == id }) else { return }
                    self.center.allow(card)
                }
                register(Keys.n, Keys.cmd) { [weak self] in
                    guard let self, let card = self.center.pending.first(where: { $0.id == id }) else { return }
                    self.center.deny(card)
                }
            }
        case .question(let input):
            guard card.isAnswerable, let question = input.questions.first else { return }
            let keyCodes = [Keys.one, Keys.two, Keys.three, Keys.four]
            for (index, option) in question.options.prefix(4).enumerated() {
                let id = card.id
                register(keyCodes[index], Keys.cmd) { [weak self] in
                    guard let self, let card = self.center.pending.first(where: { $0.id == id }) else { return }
                    self.center.answer(card, selectedLabels: [option.label])
                }
            }
        case .terminalPrompt:
            break
        }
    }

    private func register(_ keyCode: Int, _ modifiers: Int, handler: @escaping () -> Void) {
        if let token = hotKeys.register(keyCode: keyCode, carbonModifiers: modifiers, handler: handler) {
            decisionHotkeyTokens.append(token)
        }
    }

    private func unregisterDecisionHotkeys() {
        hotKeys.unregisterAll(decisionHotkeyTokens)
        decisionHotkeyTokens.removeAll()
    }
}
