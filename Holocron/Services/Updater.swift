import Foundation
import Sparkle

/// Sparkle auto-updates. Feed = appcast.xml attached to the latest GitHub
/// Release; updates are EdDSA-signed (no Apple Developer ID for now — see
/// README for the Gatekeeper note and the notarization TODO).
final class Updater {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
