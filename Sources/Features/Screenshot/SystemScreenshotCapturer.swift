import Foundation

@MainActor
protocol ScreenshotCapturing: AnyObject {
    func captureInteractiveSelectionToClipboard() async throws
}

struct ScreenshotCommandConfiguration: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]

    static let interactiveSelectionToClipboard = ScreenshotCommandConfiguration(
        executableURL: URL(fileURLWithPath: "/usr/sbin/screencapture"),
        arguments: ["-i", "-c"]
    )
}

@MainActor
final class SystemScreenshotCapturer: ScreenshotCapturing {
    private let configuration: ScreenshotCommandConfiguration

    init(configuration: ScreenshotCommandConfiguration = .interactiveSelectionToClipboard) {
        self.configuration = configuration
    }

    func captureInteractiveSelectionToClipboard() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let retention = ProcessRetention()
            let process = Process()
            retention.retain(process)
            process.executableURL = configuration.executableURL
            process.arguments = configuration.arguments

            process.terminationHandler = { process in
                defer {
                    retention.release()
                }

                switch process.terminationStatus {
                case 0, 1:
                    continuation.resume(returning: ())
                default:
                    continuation.resume(throwing: ScreenshotCaptureError.unexpectedExit(process.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                retention.release()
                continuation.resume(throwing: ScreenshotCaptureError(launchFailed: error))
            }
        }
    }
}

enum ScreenshotCaptureError: LocalizedError, Equatable, Sendable {
    case launchFailed(String)
    case unexpectedExit(Int32)

    init(launchFailed error: Error) {
        self = .launchFailed(error.localizedDescription)
    }

    var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return "无法启动系统截图工具：\(message)"
        case let .unexpectedExit(status):
            return "系统截图工具异常退出，退出码：\(status)。"
        }
    }
}

private final class ProcessRetention: @unchecked Sendable {
    private let lock = NSLock()
    private var retainedProcess: Process?

    func retain(_ process: Process) {
        lock.lock()
        defer {
            lock.unlock()
        }
        retainedProcess = process
    }

    func release() {
        lock.lock()
        defer {
            lock.unlock()
        }
        retainedProcess = nil
    }
}
