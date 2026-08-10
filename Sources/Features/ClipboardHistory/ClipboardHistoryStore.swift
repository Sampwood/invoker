import AppKit
import Combine
import Foundation

@MainActor
protocol ClipboardPasteboardAccessing: AnyObject {
    var changeCount: Int { get }
    var availableTypeIdentifiers: Set<String> { get }
    func currentHistoryItem(
        createdAt: Date,
        sourceApplication: ClipboardSourceApplication?
    ) -> ClipboardHistoryItem?
    func write(_ item: ClipboardHistoryItem) -> Bool
}

@MainActor
protocol ClipboardSourceApplicationProviding: AnyObject {
    func frontmostApplication() -> ClipboardSourceApplication?
}

enum ClipboardPinToggleResult: Equatable {
    case pinned
    case unpinned
    case limitReached
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let defaultMaxItems = ClipboardHistorySettingsStore.defaultMaxHistoryItems
    static let defaultMaxPinnedItems = ClipboardHistorySettingsStore.maxPinnedItems
    static let defaultsKey = "clipboardHistory.items"

    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published private(set) var persistenceErrorMessage: String?
    @Published private(set) var ocrErrorMessage: String?
    @Published private(set) var captureErrorMessage: String?

    let settings: ClipboardHistorySettingsStore

    private let userDefaults: UserDefaults
    private let pasteboard: ClipboardPasteboardAccessing
    private let sourceApplicationProvider: ClipboardSourceApplicationProviding
    private let repository: any ClipboardHistoryRepository
    private let ocrRecognizer: any ClipboardOCRRecognizing
    private let pollInterval: TimeInterval
    private let persistenceUnavailable: Bool
    private var lastObservedChangeCount: Int?
    private var pollTimer: Timer?
    private var startupTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var ocrTasks: [String: Task<Void, Never>] = [:]
    private var settingsCancellable: AnyCancellable?

    init(
        userDefaults: UserDefaults = .standard,
        settings: ClipboardHistorySettingsStore? = nil,
        pasteboard: ClipboardPasteboardAccessing = SystemClipboardPasteboardAccessor(),
        sourceApplicationProvider: ClipboardSourceApplicationProviding = WorkspaceClipboardSourceApplicationProvider(),
        repository: (any ClipboardHistoryRepository)? = nil,
        ocrRecognizer: any ClipboardOCRRecognizing = VisionClipboardOCRRecognizer(),
        maxItems: Int? = nil,
        pollInterval: TimeInterval = 0.7
    ) {
        self.userDefaults = userDefaults
        let resolvedSettings = settings ?? ClipboardHistorySettingsStore(userDefaults: userDefaults)
        if let maxItems {
            resolvedSettings.maxHistoryItems = max(1, maxItems)
        }
        self.settings = resolvedSettings
        self.pasteboard = pasteboard
        self.sourceApplicationProvider = sourceApplicationProvider
        self.ocrRecognizer = ocrRecognizer
        self.pollInterval = pollInterval

        if let repository {
            self.repository = repository
            persistenceUnavailable = false
            persistenceErrorMessage = nil
        } else {
            do {
                self.repository = try SQLiteClipboardHistoryRepository.makeDefault()
                persistenceUnavailable = false
                persistenceErrorMessage = nil
            } catch {
                self.repository = InMemoryClipboardHistoryRepository()
                persistenceUnavailable = true
                persistenceErrorMessage = error.localizedDescription
            }
        }

        settingsCancellable = Publishers.CombineLatest(
            resolvedSettings.$maxHistoryItems,
            resolvedSettings.$maxStorageMegabytes
        )
        .dropFirst()
        .sink { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.applyCurrentLimitsAndPersist()
            }
        }
    }

    var pinnedItemCount: Int {
        items.lazy.filter(\.isPinned).count
    }

    var unpinnedItemCount: Int {
        items.count - pinnedItemCount
    }

    var hasUnpinnedItems: Bool {
        unpinnedItemCount > 0
    }

    var statusErrorMessages: [String] {
        [persistenceErrorMessage, ocrErrorMessage, captureErrorMessage].compactMap { $0 }
    }

    func startMonitoring() {
        guard pollTimer == nil, startupTask == nil else {
            return
        }

        lastObservedChangeCount = pasteboard.changeCount
        startupTask = Task { [weak self] in
            guard let self else { return }
            await loadPersistedHistory()
            guard !Task.isCancelled else { return }
            installPollTimer()
            startupTask = nil
        }
    }

    func stopMonitoring() {
        startupTask?.cancel()
        startupTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
        lastObservedChangeCount = nil
        for task in ocrTasks.values {
            task.cancel()
        }
        ocrTasks.removeAll()
    }

    func loadPersistedHistory() async {
        let legacyData = userDefaults.data(forKey: Self.defaultsKey)

        do {
            var loadedItems = try await repository.loadItems()
            if loadedItems.isEmpty,
               let legacyData,
               let legacyItems = try? JSONDecoder().decode(
                   [ClipboardHistoryItem].self,
                   from: legacyData
               ) {
                loadedItems = normalizedItems(legacyItems)
                try await repository.synchronize(loadedItems)
                if !persistenceUnavailable {
                    userDefaults.removeObject(forKey: Self.defaultsKey)
                }
            } else if !loadedItems.isEmpty, legacyData != nil, !persistenceUnavailable {
                userDefaults.removeObject(forKey: Self.defaultsKey)
            }

            let normalized = normalizedItems(loadedItems)
            items = normalized
            if normalized != loadedItems {
                try await repository.synchronize(normalized)
            }
            if !persistenceUnavailable {
                persistenceErrorMessage = nil
            }
            scheduleMissingOCR()
        } catch {
            persistenceErrorMessage = error.localizedDescription
            if let legacyData,
               let legacyItems = try? JSONDecoder().decode(
                   [ClipboardHistoryItem].self,
                   from: legacyData
               ) {
                items = normalizedItems(legacyItems)
                scheduleMissingOCR()
            }
        }
    }

    func waitForPendingPersistence() async {
        await persistenceTask?.value
    }

    func captureCurrentItemIfChanged(createdAt: Date = Date()) {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastObservedChangeCount else {
            return
        }

        lastObservedChangeCount = changeCount
        captureCurrentItem(createdAt: createdAt)
    }

    func captureCurrentItem(createdAt: Date = Date()) {
        let sourceApplication = sourceApplicationProvider.frontmostApplication()
        let policy = settings.capturePolicy
        guard !policy.shouldIgnore(
            typeIdentifiers: pasteboard.availableTypeIdentifiers,
            sourceApplication: sourceApplication
        ) else {
            return
        }

        guard let item = pasteboard.currentHistoryItem(
            createdAt: createdAt,
            sourceApplication: sourceApplication
        ) else {
            return
        }
        record(item)
    }

    func copyToPasteboard(_ item: ClipboardHistoryItem, createdAt: Date = Date()) -> Bool {
        guard pasteboard.write(item) else {
            return false
        }

        record(item.refreshingTimestamp(createdAt))
        lastObservedChangeCount = pasteboard.changeCount
        return true
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        enqueuePersistence()
    }

    @discardableResult
    func togglePin(for id: ClipboardHistoryItem.ID) -> ClipboardPinToggleResult {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            preconditionFailure("Cannot toggle a clipboard item that is not in the store")
        }

        let item = items[index]
        if item.isPinned {
            items.remove(at: index)
            items.insert(item.settingPinned(false), at: pinnedItemCount)
            items = normalizedItems(items)
            enqueuePersistence()
            return .unpinned
        }

        guard pinnedItemCount < Self.defaultMaxPinnedItems else {
            return .limitReached
        }

        items.remove(at: index)
        items.insert(item.settingPinned(true), at: 0)
        enqueuePersistence()
        return .pinned
    }

    func record(_ item: ClipboardHistoryItem) {
        guard item.logicalByteCount <= ClipboardHistorySettingsStore.maxSingleItemBytes else {
            captureErrorMessage = "已忽略超过 10 MB 的剪贴板内容"
            return
        }

        let recordedItem: ClipboardHistoryItem
        if let existingIndex = items.firstIndex(where: { $0.hasSamePayload(as: item) }) {
            let existingItem = items[existingIndex]
            recordedItem = item.preservingIdentityAndPin(from: existingItem)

            if existingItem.isPinned {
                items[existingIndex] = recordedItem
            } else {
                items.remove(at: existingIndex)
                items.insert(recordedItem, at: pinnedItemCount)
            }
        } else {
            recordedItem = item.settingPinned(false)
            items.insert(recordedItem, at: pinnedItemCount)
        }

        items = normalizedItems(items)
        captureErrorMessage = nil
        enqueuePersistence()

        if items.contains(where: { $0.id == recordedItem.id }) {
            scheduleOCRIfNeeded(for: recordedItem)
        }
    }

    private func installPollTimer() {
        guard pollTimer == nil else { return }
        lastObservedChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureCurrentItemIfChanged()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func normalizedItems(_ sourceItems: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        let pinnedItems = sourceItems.filter(\.isPinned)
        var unpinnedItems = Array(
            sourceItems.lazy
                .filter { !$0.isPinned }
                .prefix(max(1, settings.maxHistoryItems))
        )

        let storageLimit = max(1, settings.maxStorageBytes)
        var totalBytes = pinnedItems.reduce(0) { $0 + $1.logicalByteCount }
            + unpinnedItems.reduce(0) { $0 + $1.logicalByteCount }
        while totalBytes > storageLimit, let removed = unpinnedItems.popLast() {
            totalBytes -= removed.logicalByteCount
        }
        return pinnedItems + unpinnedItems
    }

    private func applyCurrentLimitsAndPersist() {
        let normalized = normalizedItems(items)
        guard normalized != items else { return }
        items = normalized
        enqueuePersistence()
    }

    private func enqueuePersistence() {
        let itemsToPersist = items
        let previousTask = persistenceTask
        let repository = repository
        persistenceTask = Task { [weak self] in
            await previousTask?.value
            do {
                try await repository.synchronize(itemsToPersist)
                guard let self, !self.persistenceUnavailable else { return }
                self.persistenceErrorMessage = nil
            } catch {
                self?.persistenceErrorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleMissingOCR() {
        for item in items where item.ocrText == nil {
            scheduleOCRIfNeeded(for: item)
        }
    }

    private func scheduleOCRIfNeeded(for item: ClipboardHistoryItem) {
        guard item.ocrText == nil,
              item.kind == .image,
              let pngData = item.previewPNGData,
              ocrTasks[item.payloadHash] == nil
        else {
            return
        }

        let payloadHash = item.payloadHash
        let recognizer = ocrRecognizer
        ocrTasks[payloadHash] = Task { [weak self] in
            do {
                let text = try await recognizer.recognizeText(in: pngData)
                guard !Task.isCancelled, let self else { return }
                self.applyOCRText(text, payloadHash: payloadHash)
                self.ocrErrorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                self?.ocrErrorMessage = error.localizedDescription
            }
            self?.ocrTasks[payloadHash] = nil
        }
    }

    private func applyOCRText(_ text: String?, payloadHash: String) {
        guard let index = items.firstIndex(where: { $0.payloadHash == payloadHash }) else {
            return
        }
        items[index] = items[index].settingOCRText(text)
        enqueuePersistence()
    }
}

@MainActor
final class WorkspaceClipboardSourceApplicationProvider: ClipboardSourceApplicationProviding {
    func frontmostApplication() -> ClipboardSourceApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return ClipboardSourceApplication(
            bundleIdentifier: application.bundleIdentifier,
            name: application.localizedName ?? application.bundleIdentifier ?? "未知应用",
            bundlePath: application.bundleURL?.path
        )
    }
}

@MainActor
final class SystemClipboardPasteboardAccessor: ClipboardPasteboardAccessing {
    private static let supportedTypes: Set<NSPasteboard.PasteboardType> = [
        .string,
        .rtf,
        .html,
        .fileURL,
        .URL,
        .png,
        .tiff
    ]

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    var availableTypeIdentifiers: Set<String> {
        var identifiers = Set((pasteboard.types ?? []).map(\.rawValue))
        for item in pasteboard.pasteboardItems ?? [] {
            identifiers.formUnion(item.types.map(\.rawValue))
        }
        return identifiers
    }

    func currentHistoryItem(
        createdAt: Date,
        sourceApplication: ClipboardSourceApplication?
    ) -> ClipboardHistoryItem? {
        var snapshotItems = (pasteboard.pasteboardItems ?? []).compactMap { pasteboardItem in
            let representations = pasteboardItem.types.compactMap { type -> ClipboardRepresentation? in
                guard Self.supportedTypes.contains(type) else {
                    return nil
                }
                if let data = pasteboardItem.data(forType: type) {
                    return ClipboardRepresentation(typeIdentifier: type.rawValue, data: data)
                }
                if let value = pasteboardItem.string(forType: type) {
                    return ClipboardRepresentation(
                        typeIdentifier: type.rawValue,
                        data: Data(value.utf8)
                    )
                }
                return nil
            }
            return representations.isEmpty
                ? nil
                : ClipboardSnapshotItem(representations: representations)
        }

        if snapshotItems.isEmpty {
            let representations = (pasteboard.types ?? []).compactMap {
                type -> ClipboardRepresentation? in
                guard Self.supportedTypes.contains(type) else { return nil }
                if let data = pasteboard.data(forType: type) {
                    return ClipboardRepresentation(typeIdentifier: type.rawValue, data: data)
                }
                if let value = pasteboard.string(forType: type) {
                    return ClipboardRepresentation(
                        typeIdentifier: type.rawValue,
                        data: Data(value.utf8)
                    )
                }
                return nil
            }
            if !representations.isEmpty {
                snapshotItems = [ClipboardSnapshotItem(representations: representations)]
            }
        }

        guard !snapshotItems.isEmpty else {
            return nil
        }

        let snapshot = ClipboardSnapshot(items: snapshotItems)
        let previewPNGData = Self.previewPNGData(from: snapshot)
        let item = ClipboardHistoryItem(
            createdAt: createdAt,
            snapshot: snapshot,
            sourceApplication: sourceApplication,
            previewPNGData: previewPNGData
        )

        switch item.kind {
        case .text, .richText:
            guard item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
        case .file, .image, .url:
            break
        }
        return item
    }

    func write(_ item: ClipboardHistoryItem) -> Bool {
        if item.kind == .richText, let text = item.text {
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }

        let pasteboardItems = item.snapshot.items.compactMap { snapshotItem -> NSPasteboardItem? in
            let pasteboardItem = NSPasteboardItem()
            var wroteRepresentation = false
            for representation in snapshotItem.representations {
                let type = NSPasteboard.PasteboardType(representation.typeIdentifier)
                guard Self.supportedTypes.contains(type) else { continue }
                if pasteboardItem.setData(representation.data, forType: type) {
                    wroteRepresentation = true
                }
            }
            return wroteRepresentation ? pasteboardItem : nil
        }

        guard !pasteboardItems.isEmpty else {
            return false
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(pasteboardItems)
    }

    private static func previewPNGData(from snapshot: ClipboardSnapshot) -> Data? {
        let imageTypes = [
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue
        ]
        for typeIdentifier in imageTypes {
            for representation in snapshot.representations(ofType: typeIdentifier) {
                if let image = NSImage(data: representation.data),
                   let pngData = pngData(for: image) {
                    return pngData
                }
            }
        }
        return nil
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRepresentation.representation(using: .png, properties: [:])
    }
}
