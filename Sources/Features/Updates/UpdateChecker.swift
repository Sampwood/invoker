import Sparkle

@MainActor
final class UpdateChecker {
    private let standardController: SPUStandardUpdaterController

    init() {
        standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        standardController.updater.checkForUpdates()
    }
}
