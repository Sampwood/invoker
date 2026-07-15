import XCTest
@testable import Invoker

@MainActor
final class ScreenshotControllerTests: XCTestCase {
    func testScreenshotCommandConfigurationUsesInteractiveClipboardCapture() {
        XCTAssertEqual(
            ScreenshotCommandConfiguration.interactiveSelectionToClipboard.executableURL.path,
            "/usr/sbin/screencapture"
        )
        XCTAssertEqual(ScreenshotCommandConfiguration.interactiveSelectionToClipboard.arguments, ["-i", "-c"])
    }

    func testCompletedCaptureClearsCaptureStateWithoutFailure() async {
        let capturer = FakeScreenshotCapturer(result: .success(()))
        let recorder = ScreenshotPresentationRecorder()
        let controller = ScreenshotController(
            capturer: capturer,
            startDelayNanoseconds: 0,
            presentFailure: recorder.presentFailure
        )

        await controller.captureSelectionToClipboard()

        XCTAssertFalse(controller.isCaptureInProgress)
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertTrue(recorder.failures.isEmpty)
    }

    func testThrownErrorClearsCaptureStateAndPresentsFailure() async {
        let capturer = FakeScreenshotCapturer(result: .failure(ScreenshotTestError.captureFailed))
        let recorder = ScreenshotPresentationRecorder()
        let controller = ScreenshotController(
            capturer: capturer,
            startDelayNanoseconds: 0,
            presentFailure: recorder.presentFailure
        )

        await controller.captureSelectionToClipboard()

        XCTAssertFalse(controller.isCaptureInProgress)
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(recorder.failures.count, 1)
    }

    func testSecondCaptureRequestIsIgnoredWhileFirstCaptureIsInProgress() async {
        let capturer = PendingScreenshotCapturer()
        let recorder = ScreenshotPresentationRecorder()
        let controller = ScreenshotController(
            capturer: capturer,
            startDelayNanoseconds: 0,
            presentFailure: recorder.presentFailure
        )

        let firstCapture = Task { @MainActor in
            await controller.captureSelectionToClipboard()
        }
        while capturer.captureCount == 0 {
            await Task.yield()
        }

        XCTAssertTrue(controller.isCaptureInProgress)
        await controller.captureSelectionToClipboard()

        XCTAssertEqual(capturer.captureCount, 1)

        capturer.finish()
        await firstCapture.value

        XCTAssertFalse(controller.isCaptureInProgress)
        XCTAssertTrue(recorder.failures.isEmpty)
    }
}

@MainActor
private final class FakeScreenshotCapturer: ScreenshotCapturing {
    private let result: Result<Void, Error>
    private(set) var captureCount = 0

    init(result: Result<Void, Error>) {
        self.result = result
    }

    func captureInteractiveSelectionToClipboard() async throws {
        captureCount += 1
        try result.get()
    }
}

@MainActor
private final class PendingScreenshotCapturer: ScreenshotCapturing {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var captureCount = 0

    func captureInteractiveSelectionToClipboard() async throws {
        captureCount += 1
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish() {
        continuation?.resume(returning: ())
        continuation = nil
    }
}

@MainActor
private final class ScreenshotPresentationRecorder {
    private(set) var failures: [Error] = []

    func presentFailure(_ error: Error) {
        failures.append(error)
    }
}

private enum ScreenshotTestError: Error {
    case captureFailed
}
