import AppKit
import Combine
import Foundation

@MainActor
protocol ClipboardPasteboardAccessing: AnyObject {
    var changeCount: Int { get }
    func currentHistoryItem(createdAt: Date) -> ClipboardHistoryItem?
    func write(_ item: ClipboardHistoryItem) -> Bool
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let defaultMaxItems = 50
    static let defaultsKey = "clipboardHistory.items"

    @Published private(set) var items: [ClipboardHistoryItem]

    private let userDefaults: UserDefaults
    private let pasteboard: ClipboardPasteboardAccessing
    private let maxItems: Int
    private let pollInterval: TimeInterval
    private var lastObservedChangeCount: Int?
    private var pollTimer: Timer?

    init(
        userDefaults: UserDefaults = .standard,
        pasteboard: ClipboardPasteboardAccessing = SystemClipboardPasteboardAccessor(),
        maxItems: Int = ClipboardHistoryStore.defaultMaxItems,
        pollInterval: TimeInterval = 0.7
    ) {
        self.userDefaults = userDefaults
        self.pasteboard = pasteboard
        self.maxItems = max(1, maxItems)
        self.pollInterval = pollInterval
        items = Self.loadItems(from: userDefaults)
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

    func clear() {
        items = []
        persist()
    }

    func record(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.hasSamePayload(as: item) }
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        persist()
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
