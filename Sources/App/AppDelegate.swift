import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private let inputSourceLock = GlobalInputSourceLock()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        inputSourceLock.start()
        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputSourceLock.stop()
    }
}
