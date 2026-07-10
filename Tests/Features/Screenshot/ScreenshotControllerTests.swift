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

    func testCapturedOutcomeClearsCaptureStateAndPresentsSuccess() async {
        let capturer = FakeScreenshotCapturer(result: .success(.captured))
        let recorder = ScreenshotPresentationRecorder()
        let controller = ScreenshotController(
            capturer: capturer,
            startDelayNanoseconds: 0,
            presentSuccess: recorder.presentSuccess,
            presentFailure: recorder.presentFailure
        )

        await controller.captureSelectionToClipboard()

        XCTAssertFalse(controller.isCaptureInProgress)
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(recorder.successCount, 1)
        XCTAssertTrue(recorder.failures.isEmpty)
    }

    func testCancelledOutcomeClearsCaptureStateWithoutPresentation() async {
        let capturer = FakeScreenshotCapturer(result: .success(.cancelled))
        let recorder = ScreenshotPresentationRecorder()
        let controller = ScreenshotController(
            capturer: capturer,
            startDelayNanoseconds: 0,
            presentSuccess: recorder.presentSuccess,
            presentFailure: recorder.presentFailure
        )

        await controller.captureSelectionToClipboard()

        XCTAssertFalse(controller.isCaptureInProgress)
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(recorder.successCount, 0)
        XCTAssertTrue(recorder.failures.isEmpty)
    }

    func testThrownErrorClearsCaptureStateAndPresentsFailure() async {
        let capturer = FakeScreenshotCapturer(result: .failure(ScreenshotTestError.captureFailed))
        let recorder = ScreenshotPresentationRecorder()
        let controller = ScreenshotController(
            capturer: capturer,
            startDelayNanoseconds: 0,
            presentSuccess: recorder.presentSuccess,
            presentFailure: recorder.presentFailure
        )

        await controller.captureSelectionToClipboard()

        XCTAssertFalse(controller.isCaptureInProgress)
        XCTAssertEqual(capturer.captureCount, 1)
        XCTAssertEqual(recorder.successCount, 0)
        XCTAssertEqual(recorder.failures.count, 1)
    }

    func testSecondCaptureRequestIsIgnoredWhileFirstCaptureIsInProgress() async {
        let capturer = PendingScreenshotCapturer()
        let recorder = ScreenshotPresentationRecorder()
        let controller = ScreenshotController(
            capturer: capturer,
            startDelayNanoseconds: 0,
            presentSuccess: recorder.presentSuccess,
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

        capturer.finish(with: .captured)
        await firstCapture.value

        XCTAssertFalse(controller.isCaptureInProgress)
        XCTAssertEqual(recorder.successCount, 1)
    }
}

@MainActor
private final class FakeScreenshotCapturer: ScreenshotCapturing {
    private let result: Result<ScreenshotCaptureOutcome, Error>
    private(set) var captureCount = 0

    init(result: Result<ScreenshotCaptureOutcome, Error>) {
        self.result = result
    }

    func captureInteractiveSelectionToClipboard() async throws -> ScreenshotCaptureOutcome {
        captureCount += 1
        return try result.get()
    }
}

@MainActor
private final class PendingScreenshotCapturer: ScreenshotCapturing {
    private var continuation: CheckedContinuation<ScreenshotCaptureOutcome, Error>?
    private(set) var captureCount = 0

    func captureInteractiveSelectionToClipboard() async throws -> ScreenshotCaptureOutcome {
        captureCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with outcome: ScreenshotCaptureOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

@MainActor
private final class ScreenshotPresentationRecorder {
    private(set) var successCount = 0
    private(set) var failures: [Error] = []

    func presentSuccess() {
        successCount += 1
    }

    func presentFailure(_ error: Error) {
        failures.append(error)
    }
}

private enum ScreenshotTestError: Error {
    case captureFailed
}
