import AppKit
import Combine
import Foundation

@MainActor
protocol ClipboardPasteboardAccessing: AnyObject {
    var changeCount: Int { get }
    func currentHistoryItem(createdAt: Date) -> ClipboardHistoryItem?
    func write(_ item: ClipboardHistoryItem) -> Bool
}

enum ClipboardPinToggleResult: Equatable {
    case pinned
    case unpinned
    case limitReached
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let defaultMaxItems = 50
    static let defaultMaxPinnedItems = 50
    static let defaultsKey = "clipboardHistory.items"

    @Published private(set) var items: [ClipboardHistoryItem]

    private let userDefaults: UserDefaults
    private let pasteboard: ClipboardPasteboardAccessing
    private let maxItems: Int
    private let maxPinnedItems: Int
    private let pollInterval: TimeInterval
    private var lastObservedChangeCount: Int?
    private var pollTimer: Timer?

    init(
        userDefaults: UserDefaults = .standard,
        pasteboard: ClipboardPasteboardAccessing = SystemClipboardPasteboardAccessor(),
        maxItems: Int = ClipboardHistoryStore.defaultMaxItems,
        maxPinnedItems: Int = ClipboardHistoryStore.defaultMaxPinnedItems,
        pollInterval: TimeInterval = 0.7
    ) {
        let normalizedMaxItems = max(1, maxItems)
        self.userDefaults = userDefaults
        self.pasteboard = pasteboard
        self.maxItems = normalizedMaxItems
        self.maxPinnedItems = max(1, maxPinnedItems)
        self.pollInterval = pollInterval
        items = Self.normalizedItems(
            Self.loadItems(from: userDefaults),
            maxUnpinnedItems: normalizedMaxItems
        )
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

    func startMonitoring() {
        guard pollTimer == nil else {
            return
        }

        lastObservedChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureCurrentItemIfChanged()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        lastObservedChangeCount = nil
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
        guard let item = pasteboard.currentHistoryItem(createdAt: createdAt) else {
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
        persist()
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
            trimUnpinnedItems()
            persist()
            return .unpinned
        }

        guard pinnedItemCount < maxPinnedItems else {
            return .limitReached
        }

        items.remove(at: index)
        items.insert(item.settingPinned(true), at: 0)
        persist()
        return .pinned
    }

    func record(_ item: ClipboardHistoryItem) {
        if let existingIndex = items.firstIndex(where: { $0.hasSamePayload(as: item) }) {
            let existingItem = items[existingIndex]
            let updatedItem = ClipboardHistoryItem(
                id: existingItem.id,
                kind: item.kind,
                createdAt: item.createdAt,
                isPinned: existingItem.isPinned,
                text: item.text,
                imagePNGData: item.imagePNGData
            )

            if existingItem.isPinned {
                items[existingIndex] = updatedItem
            } else {
                items.remove(at: existingIndex)
                items.insert(updatedItem, at: pinnedItemCount)
            }
        } else {
            items.insert(item.settingPinned(false), at: pinnedItemCount)
        }

        trimUnpinnedItems()
        persist()
    }

    private func trimUnpinnedItems() {
        items = Self.normalizedItems(items, maxUnpinnedItems: maxItems)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else {
            return
        }

        userDefaults.set(data, forKey: Self.defaultsKey)
    }

    private static func loadItems(from userDefaults: UserDefaults) -> [ClipboardHistoryItem] {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        else {
            return []
        }

        return items
    }

    private static func normalizedItems(
        _ items: [ClipboardHistoryItem],
        maxUnpinnedItems: Int
    ) -> [ClipboardHistoryItem] {
        let pinnedItems = items.filter(\.isPinned)
        let unpinnedItems = items.lazy.filter { !$0.isPinned }.prefix(maxUnpinnedItems)
        return pinnedItems + Array(unpinnedItems)
    }
}

@MainActor
final class SystemClipboardPasteboardAccessor: ClipboardPasteboardAccessing {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func currentHistoryItem(createdAt: Date) -> ClipboardHistoryItem? {
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text, createdAt: createdAt)
        }

        if let pngData = pasteboard.data(forType: .png),
           let image = NSImage(data: pngData),
           let normalizedPNGData = Self.pngData(for: image) {
            return .image(pngData: normalizedPNGData, createdAt: createdAt)
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let pngData = Self.pngData(for: image) {
            return .image(pngData: pngData, createdAt: createdAt)
        }

        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let pngData = Self.pngData(for: image) {
            return .image(pngData: pngData, createdAt: createdAt)
        }

        return nil
    }

    func write(_ item: ClipboardHistoryItem) -> Bool {
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let text = item.text else {
                return false
            }
            return pasteboard.setString(text, forType: .string)
        case .image:
            guard let pngData = item.imagePNGData else {
                return false
            }
            if let image = NSImage(data: pngData),
               pasteboard.writeObjects([image]) {
                return true
            }
            return pasteboard.setData(pngData, forType: .png)
        }
    }

    private static func pngData(for image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRepresentation.representation(using: .png, properties: [:])
    }
}
