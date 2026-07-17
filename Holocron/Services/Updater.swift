import Combine
import Foundation
import Observation
import Sparkle

/// Sparkle auto-updates, wired the same way as r2-git2: the updater only
/// starts when a real EdDSA public key is present in Info.plist
/// (`SUPublicEDKey`). Without one, `isConfigured` stays false and the UI
/// hides its update controls — instead of Sparkle's "updater failed to
/// start" error dialog.
@Observable
final class Updater {
    /// True once SUPublicEDKey holds a real key (not the placeholder).
    let isConfigured: Bool

    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var cancellable: AnyCancellable?

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        isConfigured = !key.isEmpty && !key.hasPrefix("REPLACE_WITH")

        guard isConfigured else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
