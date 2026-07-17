import SwiftUI

@main
struct HolocronApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let settings = AppState.shared.settings
        MenuBarExtra(isInserted: Binding(
            get: { settings.showMenuBarIcon },
            set: { settings.showMenuBarIcon = $0 }
        )) {
            MenuContent(state: AppState.shared)
        } label: {
            Image(systemName: "circle.hexagongrid.fill")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: a stale twin (e.g. hung after a crash) stacks an
        // invisible panel over ours at the top of the screen and swallows
        // hover/clicks. The newest launch wins.
        let bundleID = Bundle.main.bundleIdentifier ?? "fr.fabien-vincent.holocron"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .forEach { $0.forceTerminate() }

        // LSUIElement app: no Dock icon, notch panel + menu bar item only.
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppState.shared.bootstrap()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            AppState.shared.shutdown()
        }
    }
}

struct MenuContent: View {
    let state: AppState

    var body: some View {
        Button(state.panelController?.isVisible == true ? "Hide notch panel" : "Show notch panel") {
            if state.panelController?.isVisible == true {
                state.panelController?.hide()
            } else {
                state.panelController?.show()
            }
        }
        Button("Toggle expanded (⌃⌥H)") { state.togglePanel() }

        Divider()

        if state.hooksInstalled {
            Button("Uninstall Claude Code hooks") { state.uninstallHooks() }
        } else {
            Button("Install Claude Code hooks") { state.installHooks() }
        }
        if state.updater?.isConfigured == true {
            Button("Check for updates…") { state.updater?.checkForUpdates() }
                .disabled(state.updater?.canCheckForUpdates != true)
        }

        Divider()

        Button("Settings…") { state.openSettings() }
        Button("Quit Holocron") { NSApp.terminate(nil) }
    }
}
