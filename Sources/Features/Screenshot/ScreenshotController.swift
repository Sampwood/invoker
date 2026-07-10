import AppKit
import Foundation

@MainActor
final class ScreenshotController {
    private let capturer: ScreenshotCapturing
    private let startDelayNanoseconds: UInt64
    private let presentSuccess: @MainActor () -> Void
    private let presentFailure: @MainActor (Error) -> Void
    private(set) var isCaptureInProgress = false

    init(
        capturer: ScreenshotCapturing = SystemScreenshotCapturer(),
        startDelayNanoseconds: UInt64 = 120_000_000,
        presentSuccess: @escaping @MainActor () -> Void = ScreenshotController.presentDefaultSuccess,
        presentFailure: @escaping @MainActor (Error) -> Void = ScreenshotController.presentDefaultFailure
    ) {
        self.capturer = capturer
        self.startDelayNanoseconds = startDelayNanoseconds
        self.presentSuccess = presentSuccess
        self.presentFailure = presentFailure
    }

    func captureSelectionToClipboard() async {
        guard !isCaptureInProgress else {
            return
        }

        isCaptureInProgress = true
        defer {
            isCaptureInProgress = false
        }

        if startDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: startDelayNanoseconds)
        }

        do {
            switch try await capturer.captureInteractiveSelectionToClipboard() {
            case .captured:
                presentSuccess()
            case .cancelled:
                break
            }
        } catch {
            presentFailure(error)
        }
    }

    private static func presentDefaultSuccess() {
        let alert = NSAlert()
        alert.messageText = "截图已复制到剪贴板"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func presentDefaultFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "截图失败"
        alert.informativeText = "请确认系统截图/屏幕录制权限可用后重试。\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
