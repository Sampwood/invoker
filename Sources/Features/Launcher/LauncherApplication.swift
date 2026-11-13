import AppKit
import UniformTypeIdentifiers

struct LauncherApplication: Identifiable, Sendable {
    let url: URL
    let title: String
    var id: String { "app:" + url.path }
    var fileName: String { url.deletingPathExtension().lastPathComponent }
}

struct LauncherApplicationScanner: Sendable {
    var roots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        URL(fileURLWithPath: "/System/Applications")
    ]

    func scan() -> [LauncherApplication] {
        let manager = FileManager.default
        var applications: [String: LauncherApplication] = [:]
        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isPackageKey])
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    if let application = Self.application(at: url) { applications[application.id] = application }
                } else if values?.isSymbolicLink == true || values?.isPackage == true
                    || ["bundle", "framework", "plugin", "appex", "xpc"].contains(url.pathExtension.lowercased())
                    || UTType(filenameExtension: url.pathExtension)?.conforms(to: .package) == true {
                    enumerator.skipDescendants()
                }
            }
        }
        return applications.values.sorted { $0.url.path < $1.url.path }
    }

    static func application(at url: URL) -> LauncherApplication? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard let bundle = Bundle(url: resolved),
              bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL",
              let executable = bundle.executableURL,
              FileManager.default.fileExists(atPath: executable.path) else { return nil }
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        let names = keys.map { bundle.localizedInfoDictionary?[$0] as? String }
            + keys.map { bundle.infoDictionary?[$0] as? String }
        let name = names.compactMap { $0 }.first { !$0.isEmpty }
            ?? resolved.deletingPathExtension().lastPathComponent
        return LauncherApplication(url: resolved, title: name)
    }
}

@MainActor
protocol LauncherApplicationLaunching {
    func open(_ application: LauncherApplication) async throws
}

@MainActor
struct WorkspaceApplicationLauncher: LauncherApplicationLaunching {
    func open(_ application: LauncherApplication) async throws {
        guard LauncherApplicationScanner.application(at: application.url) != nil else {
            throw NSError(domain: "Invoker.Launcher", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "应用已不存在或不可访问，请重新搜索。"])
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        _ = try await NSWorkspace.shared.openApplication(at: application.url, configuration: configuration)
    }
}

@MainActor
final class LauncherIconCache {
    static let shared = LauncherIconCache()
    private let images = NSCache<NSURL, NSImage>()

    func image(for application: LauncherApplication) -> NSImage {
        let key = application.url as NSURL
        if let image = images.object(forKey: key) { return image }
        let image = NSWorkspace.shared.icon(forFile: application.url.path)
        images.setObject(image, forKey: key)
        return image
    }
}
