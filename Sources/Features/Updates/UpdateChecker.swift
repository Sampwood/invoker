import AppKit
import Foundation

@MainActor
final class UpdateChecker {
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/Sampwood/invoker/releases/latest")!
    private let bundle: Bundle
    private var isChecking = false

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func checkForUpdates() {
        guard !isChecking else {
            return
        }

        isChecking = true

        Task {
            defer {
                isChecking = false
            }

            do {
                let release = try await fetchLatestRelease()
                presentResult(for: release)
            } catch {
                presentError(error)
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Invoker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateCheckError.githubStatus(httpResponse.statusCode)
        }

        return try JSONDecoder.githubReleaseDecoder.decode(GitHubRelease.self, from: data)
    }

    private func presentResult(for release: GitHubRelease) {
        let currentVersion = AppVersion(bundle.shortVersionString)
        let latestVersion = AppVersion(release.tagName)

        if latestVersion > currentVersion {
            presentAvailableUpdate(release)
        } else {
            presentUpToDate(release)
        }
    }

    private func presentAvailableUpdate(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(release.tagName)"
        alert.informativeText = "当前版本是 \(bundle.shortVersionString)。请打开 GitHub Release 页面下载最新版。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开发布页面")
        alert.addButton(withTitle: "稍后")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else {
            return
        }

        NSWorkspace.shared.open(release.htmlURL)
    }

    private func presentUpToDate(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "Invoker 已是最新版本"
        alert.informativeText = "当前版本 \(bundle.shortVersionString)，最新发布版本 \(release.tagName)。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "检查更新失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private struct AppVersion: Comparable {
    private let numbers: [Int]

    init(_ rawValue: String) {
        let normalized = rawValue.hasPrefix("v") || rawValue.hasPrefix("V")
            ? String(rawValue.dropFirst())
            : rawValue

        numbers = normalized
            .split { character in
                character == "." || character == "-" || character == "_"
            }
            .map { part in
                let numericPrefix = part.prefix { character in
                    character.isNumber
                }
                return Int(numericPrefix) ?? 0
            }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)

        for index in 0..<count {
            let left = lhs.numbers.indices.contains(index) ? lhs.numbers[index] : 0
            let right = rhs.numbers.indices.contains(index) ? rhs.numbers[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}

private enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case githubStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub 返回了无法识别的响应。"
        case let .githubStatus(statusCode):
            return "GitHub Releases 请求失败，HTTP 状态码：\(statusCode)。"
        }
    }
}

private extension Bundle {
    var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

private extension JSONDecoder {
    static var githubReleaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}
