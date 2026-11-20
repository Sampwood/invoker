import Foundation
import SwiftUI

@MainActor
final class LauncherSearchViewModel: ObservableObject {
    let registry: LauncherCommandRegistry
    let usage: LauncherUsageStore
    private let scan: @Sendable () async -> [LauncherApplication]
    private let launcher: any LauncherApplicationLaunching
    @Published var query = "" { didSet { selectFirstMatch() } }
    @Published private(set) var selectedCommandID: String?
    @Published private(set) var scrollRequestID = UUID()
    @Published private(set) var focusRequestID = UUID()
    @Published private(set) var applications: [LauncherApplication] = []
    @Published private(set) var isScanning = false
    @Published private var usageRevision = 0
    private var refreshTask: Task<Void, Never>?
    private var pinyinByTitle: [String: String] = [:]

    init(registry: LauncherCommandRegistry,
         usage: LauncherUsageStore = LauncherUsageStore(),
         launcher: any LauncherApplicationLaunching = WorkspaceApplicationLauncher(),
         scan: @escaping @Sendable () async -> [LauncherApplication] = {
             await Task.detached(priority: .utility) { LauncherApplicationScanner().scan() }.value
         }) {
        self.registry = registry
        self.usage = usage
        self.launcher = launcher
        self.scan = scan
    }

    var results: [LauncherSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pinyinQuery = compactPinyin(query)
        let canMatchPinyin = !pinyinQuery.isEmpty && pinyinQuery.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber)
        }
        let history = usage.snapshot()
        let candidates = registry.commands.map(LauncherSearchResult.command)
            + applications.map(LauncherSearchResult.application)
        let scored: [(item: LauncherSearchResult, score: Int)] = candidates.compactMap { item in
            if query.isEmpty { return (item, 0) }
            let score: Int?
            switch item {
            case .command(let command):
                score = registry.score(command, for: query)
            case .application(let application):
                let scores = [application.title, application.fileName].compactMap { name -> Int? in
                    if name.lowercased() == query.lowercased() { return 0 }
                    if name.lowercased().hasPrefix(query.lowercased()) { return 1 }
                    if name.localizedCaseInsensitiveContains(query) { return 2 }
                    return nil
                }
                score = scores.min()
            }
            if let score { return (item, score) }
            guard canMatchPinyin else { return nil }
            return pinyinScore(for: item.title, query: pinyinQuery).map { (item, $0) }
        }
        let sorted = scored.sorted { lhs, rhs in
            let a = history[lhs.item.id] ?? [], b = history[rhs.item.id] ?? []
            if a.count != b.count { return a.count > b.count }
            let lastA = a.max() ?? .distantPast, lastB = b.max() ?? .distantPast
            if lastA != lastB { return lastA > lastB }
            if !query.isEmpty {
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.item.isCommand != rhs.item.isCommand { return lhs.item.isCommand }
            }
            let order = lhs.item.title.localizedStandardCompare(rhs.item.title)
            if order != .orderedSame { return order == .orderedAscending }
            if lhs.item.isCommand != rhs.item.isCommand { return lhs.item.isCommand }
            return lhs.item.id < rhs.item.id
        }.map(\.item)
        return query.isEmpty ? Array(sorted.prefix(5)) : sorted
    }

    private func pinyinScore(for title: String, query: String) -> Int? {
        if pinyinByTitle[title] == nil {
            let transliterated = title.applyingTransform(.mandarinToLatin, reverse: false) ?? title
            pinyinByTitle[title] = transliterated == title ? "" : compactPinyin(transliterated)
        }
        guard let pinyin = pinyinByTitle[title], pinyin.hasPrefix(query) else { return nil }
        return pinyin == query ? 6 : 7
    }

    private func compactPinyin(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }
    }

    func prepare() {
        query = ""
        requestSearchFocus()
        refresh()
    }

    func refresh() {
        guard refreshTask == nil else { return }
        isScanning = true
        let scan = scan
        refreshTask = Task { [weak self] in
            let applications = await scan()
            guard let self else { return }
            self.applications = applications
            self.isScanning = false
            self.reconcileSelection()
            self.refreshTask = nil
        }
    }

    func waitForRefresh() async { await refreshTask?.value }
    func requestSearchFocus() { focusRequestID = UUID() }
    func select(_ result: LauncherSearchResult) { selectedCommandID = result.id }
    func selectFirstMatch() {
        selectedCommandID = results.first?.id
        scrollRequestID = UUID()
    }
    func reconcileSelection() {
        if let selectedCommandID, results.contains(where: { $0.id == selectedCommandID }) { return }
        selectFirstMatch()
    }
    func moveSelection(by offset: Int) {
        let items = results
        guard !items.isEmpty else { selectedCommandID = nil; return }
        let index = items.firstIndex { $0.id == selectedCommandID } ?? 0
        selectedCommandID = items[min(max(index + offset, 0), items.count - 1)].id
        scrollRequestID = UUID()
    }
    func selectedCommand() -> LauncherSearchResult? {
        results.first { $0.id == selectedCommandID }
    }

    func execute(_ result: LauncherSearchResult) async throws {
        switch result {
        case .command(let command):
            usage.record(result.id)
            usageRevision += 1
            command.action()
        case .application(let application):
            try await launcher.open(application)
            usage.record(result.id)
            usageRevision += 1
        }
        reconcileSelection()
    }
}
