import AppKit
import ApplicationServices

// Runs in the invoking terminal's existing permission context, outside the XCTest sandbox.
struct InputRequest: Decodable {
    let id: UUID
    let pid: pid_t
    let launchTime: TimeInterval
    let keys: [CGKeyCode]
}

let runtime = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
guard runtime.deletingLastPathComponent() == URL(fileURLWithPath: "/private/tmp", isDirectory: true).resolvingSymlinksInPath(),
      runtime.lastPathComponent.hasPrefix("invoker-ui-tests-"),
      AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
    FileHandle.standardError.write(Data("Invalid test directory or missing existing AX/event-posting permission.\n".utf8))
    exit(1)
}
// The runner can write only inside its own container, even when /private/tmp is readable.
let input = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Containers/com.sampwood.invoker.uitests.xctrunner/Data/tmp/\(runtime.lastPathComponent)",
    isDirectory: true
)
let requestURL = input.appendingPathComponent("request.json")
let expectedApp = runtime.appendingPathComponent("DerivedData/Build/Products/Debug/InvokerUITestHost.app")
let allowedKeys: Set<CGKeyCode> = [18, 20, 25, 29, 36, 51, 53, 125, 126]
try Data(input.path.utf8).write(to: runtime.appendingPathComponent("Input/container-directory.txt"), options: .atomic)
try Data().write(to: runtime.appendingPathComponent("Input/ready"), options: .atomic)

func record(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

func validate(_ request: InputRequest) throws -> NSRunningApplication {
    guard let app = NSRunningApplication(processIdentifier: request.pid),
          app.bundleIdentifier == "com.sampwood.invoker.uitesthost",
          app.bundleURL?.resolvingSymlinksInPath().path == expectedApp.path,
          app.launchDate?.timeIntervalSince1970 == request.launchTime,
          NSWorkspace.shared.frontmostApplication?.processIdentifier == request.pid else {
        let actual = NSRunningApplication(processIdentifier: request.pid)
        let detail = "path=\(actual?.bundleURL?.resolvingSymlinksInPath().path ?? "nil"), "
            + "launch=\(actual?.launchDate?.timeIntervalSince1970 ?? 0)/\(request.launchTime), "
            + "foreground=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)/\(request.pid)"
        throw NSError(domain: "InvokerUITestInput", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Test host identity or foreground state changed: \(detail)"])
    }
    return app
}

precondition((try? validate(InputRequest(id: UUID(), pid: getpid(), launchTime: 0, keys: [36]))) == nil,
             "A non-host process must never receive test input.")
record("Safety check passed: rejected a non-host process before event posting.")

while true {
    if FileManager.default.fileExists(atPath: requestURL.path) {
        let request = try JSONDecoder().decode(InputRequest.self, from: Data(contentsOf: requestURL))
        try FileManager.default.removeItem(at: requestURL)
        var errorMessage = ""
        do {
            guard !request.keys.isEmpty, request.keys.count <= 32,
                  request.keys.allSatisfy(allowedKeys.contains) else {
                throw NSError(domain: "InvokerUITestInput", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Unexpected test key sequence."])
            }
            for code in request.keys {
                _ = try validate(request)
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
                    throw NSError(domain: "InvokerUITestInput", code: 3)
                }
                down.flags = []
                up.flags = []
                down.postToPid(request.pid)
                up.postToPid(request.pid)
                Thread.sleep(forTimeInterval: 0.05)
            }
            record("Sent keys \(request.keys) to test host PID \(request.pid), launch \(request.launchTime).")
        } catch {
            errorMessage = error.localizedDescription
            record("Rejected input: \(errorMessage)")
        }
        let response = ["id": request.id.uuidString, "error": errorMessage]
        try JSONSerialization.data(withJSONObject: response).write(
            to: input.appendingPathComponent("response.json"), options: .atomic
        )
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
