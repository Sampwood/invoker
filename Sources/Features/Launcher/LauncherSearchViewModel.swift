import Combine
import Foundation
import SwiftUI

@MainActor
final class LauncherSearchViewModel: ObservableObject {
    let registry: LauncherCommandRegistry
    let usage: LauncherUsageStore
    private let scan: @Sendable () async -> [LauncherApplication]
    private let launcher: any LauncherApplicationLaunching
    private let exchangeRates: TwelveDataExchangeRates
    @Published var query = "" {
        didSet {
            updateCalculation()
            selectFirstMatch()
        }
    }
    @Published private(set) var selectedCommandID: String?
    @Published private(set) var scrollRequestID = UUID()
    @Published private(set) var focusRequestID = UUID()
    @Published private(set) var applications: [LauncherApplication] = []
    @Published private(set) var isScanning = false
    @Published private var usageRevision = 0
    @Published private var calculation: LauncherSearchResult?
    @Published private(set) var exchangeRateStatus: String?
    private var exchangeRateAPIKey = ""
    private var exchangeRateKeySubscription: AnyCancellable?
    private var exchangeRateTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pinyinByTitle: [String: String] = [:]

    init(registry: LauncherCommandRegistry,
         usage: LauncherUsageStore = LauncherUsageStore(),
         launcher: any LauncherApplicationLaunching = WorkspaceApplicationLauncher(),
         exchangeRateKeys: Published<String>.Publisher? = nil,
         exchangeRates: TwelveDataExchangeRates = TwelveDataExchangeRates(),
         scan: @escaping @Sendable () async -> [LauncherApplication] = {
             await Task.detached(priority: .utility) { LauncherApplicationScanner().scan() }.value
         }) {
        self.registry = registry
        self.usage = usage
        self.launcher = launcher
        self.exchangeRates = exchangeRates
        self.scan = scan
        exchangeRateKeySubscription = exchangeRateKeys?.removeDuplicates().sink { [weak self] key in
            guard let self else { return }
            let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key != self.exchangeRateAPIKey else { return }
            self.exchangeRateAPIKey = key
            self.cancelExchangeRateLookup()
            self.exchangeRates.invalidate()
            self.updateCalculation()
            self.reconcileSelection()
        }
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
            case .calculation:
                return nil
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
        if query.isEmpty { return Array(sorted.prefix(5)) }
        if let calculation { return [calculation] + sorted }
        return sorted
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

    private var dollarAmount: Decimal? {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = input.wholeMatch(of: /\$([0-9]+(?:\.[0-9]+)?)/)?.output.1 else { return nil }
        return Decimal(string: String(amount), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func updateCalculation() {
        guard let amount = dollarAmount else {
            calculation = LauncherArithmetic.evaluate(query).map { .calculation(value: $0) }
            exchangeRateStatus = nil
            return
        }

        let apiKey = exchangeRateAPIKey
        if let quote = exchangeRates.cachedQuote(for: apiKey) {
            showExchangeResult(quote, amount: amount)
            return
        }
        calculation = nil
        guard !apiKey.isEmpty else {
            exchangeRateStatus = "请在「设置 → 通用 → 汇率」填写 Twelve Data API Key。"
            return
        }

        exchangeRateStatus = "正在获取美元兑人民币汇率…"
        guard exchangeRateTask == nil else { return }
        exchangeRateTask = Task { [weak self, exchangeRates] in
            let response: Result<TwelveDataExchangeRates.Quote, Error>
            do {
                response = .success(try await exchangeRates.quote(for: apiKey))
            } catch {
                response = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.exchangeRateTask = nil
            guard let amount = self.dollarAmount else { return }

            switch response {
            case .success(let quote):
                self.showExchangeResult(quote, amount: amount)
            case .failure(let error):
                self.exchangeRateStatus = self.exchangeRateErrorMessage(error)
            }
            self.reconcileSelection()
        }
    }

    private func showExchangeResult(_ quote: TwelveDataExchangeRates.Quote, amount: Decimal) {
        let converted = amount * quote.rate
        guard !converted.isNaN else {
            calculation = nil
            exchangeRateStatus = "金额超出可换算范围。"
            return
        }
        let value = converted.formatted(.number
            .locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never)
            .precision(.fractionLength(2))
            .rounded(rule: .toNearestOrAwayFromZero))
        calculation = .calculation(value: value, quoteTime: Date(timeIntervalSince1970: quote.timestamp))
        exchangeRateStatus = nil
    }

    private func exchangeRateErrorMessage(_ error: Error) -> String {
        switch error as? TwelveDataExchangeRates.LookupError {
        case .invalidKey:
            "Twelve Data API Key 无效，请检查设置。"
        case .accessDenied:
            "当前 Twelve Data 账号无法查询美元兑人民币汇率。"
        case .rateLimited:
            "Twelve Data 请求额度已用完，请稍后重试。"
        default:
            "暂时无法获取汇率，请稍后重试。"
        }
    }

    private func cancelExchangeRateLookup() {
        exchangeRateTask?.cancel()
        exchangeRateTask = nil
    }

    func dismiss() {
        cancelExchangeRateLookup()
        query = ""
    }

    func waitForExchangeRateLookup() async {
        await exchangeRateTask?.value
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
        case .calculation:
            return
        }
        reconcileSelection()
    }
}
