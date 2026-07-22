import AppKit
import XCTest
@testable import Invoker

@MainActor
final class ClipboardHistoryStoreTests: XCTestCase {
    func testRecordsTextClipboardItem() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let item = ClipboardHistoryItem.text("hello", createdAt: Date(timeIntervalSince1970: 1))
        suite.pasteboard.nextItem = item
        suite.pasteboard.changeCount = 1

        suite.store.captureCurrentItemIfChanged()

        XCTAssertEqual(suite.store.items, [item])
    }

    func testRecordsImageClipboardItem() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let item = ClipboardHistoryItem.image(
            pngData: try Self.samplePNGData(),
            createdAt: Date(timeIntervalSince1970: 1)
        )
        suite.pasteboard.nextItem = item
        suite.pasteboard.changeCount = 1

        suite.store.captureCurrentItemIfChanged()

        XCTAssertEqual(suite.store.items, [item])
    }

    func testIgnoresEmptyOrUnsupportedClipboardItem() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        suite.pasteboard.nextItem = nil
        suite.pasteboard.changeCount = 1

        suite.store.captureCurrentItemIfChanged()

        XCTAssertTrue(suite.store.items.isEmpty)
    }

    func testDuplicatePayloadMovesNewestItemToTop() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let first = ClipboardHistoryItem.text("repeat", createdAt: Date(timeIntervalSince1970: 1))
        let second = ClipboardHistoryItem.text("other", createdAt: Date(timeIntervalSince1970: 2))
        let duplicate = ClipboardHistoryItem.text("repeat", createdAt: Date(timeIntervalSince1970: 3))

        suite.store.record(first)
        suite.store.record(second)
        suite.store.record(duplicate)

        XCTAssertEqual(suite.store.items, [duplicate, second])
    }

    func testTrimsItemsToMaxLimit() throws {
        let suite = try ClipboardHistoryTestSuite(maxItems: 2)
        defer { suite.removePersistentDomain() }

        suite.store.record(.text("one", createdAt: Date(timeIntervalSince1970: 1)))
        suite.store.record(.text("two", createdAt: Date(timeIntervalSince1970: 2)))
        suite.store.record(.text("three", createdAt: Date(timeIntervalSince1970: 3)))

        XCTAssertEqual(suite.store.items.map(\.text), ["three", "two"])
    }

    func testPersistsTextAndImageItems() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let textItem = ClipboardHistoryItem.text("persisted", createdAt: Date(timeIntervalSince1970: 1))
        let imageItem = ClipboardHistoryItem.image(
            pngData: try Self.samplePNGData(),
            createdAt: Date(timeIntervalSince1970: 2)
        )

        suite.store.record(textItem)
        suite.store.record(imageItem)

        let reloadedStore = ClipboardHistoryStore(
            userDefaults: suite.defaults,
            pasteboard: suite.pasteboard,
            maxItems: ClipboardHistoryStore.defaultMaxItems,
            pollInterval: 100
        )

        XCTAssertEqual(reloadedStore.items, [imageItem, textItem])
    }

    func testCopyToPasteboardWritesItemAndMovesItToTop() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let oldItem = ClipboardHistoryItem.text("old", createdAt: Date(timeIntervalSince1970: 1))
        let selectedItem = ClipboardHistoryItem.text("selected", createdAt: Date(timeIntervalSince1970: 2))
        suite.store.record(selectedItem)
        suite.store.record(oldItem)

        let didCopy = suite.store.copyToPasteboard(
            selectedItem,
            createdAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertTrue(didCopy)
        XCTAssertEqual(suite.pasteboard.writtenItems, [selectedItem])
        XCTAssertEqual(suite.store.items.map(\.text), ["selected", "old"])
        XCTAssertEqual(suite.store.items.first?.createdAt, Date(timeIntervalSince1970: 3))
    }

    func testPresentationStateFiltersTextAndImages() {
        let state = ClipboardHistoryPresentationState()
        let textItem = ClipboardHistoryItem.text("Project README")
        let imageItem = ClipboardHistoryItem.image(pngData: Data([0]))
        let items = [textItem, imageItem]

        state.query = "readme"
        XCTAssertEqual(state.filteredItems(from: items), [textItem])

        state.query = "图片"
        XCTAssertEqual(state.filteredItems(from: items), [imageItem])
    }

    func testPresentationStateMovesSelectionAndClampsAtBounds() {
        let state = ClipboardHistoryPresentationState()
        let items = [
            ClipboardHistoryItem.text("first"),
            ClipboardHistoryItem.text("second"),
            ClipboardHistoryItem.text("third")
        ]

        state.prepare(for: items)
        XCTAssertEqual(state.selectedItemID, items[0].id)

        state.moveSelection(by: 1, in: items)
        XCTAssertEqual(state.selectedItemID, items[1].id)

        state.moveSelection(by: 10, in: items)
        XCTAssertEqual(state.selectedItemID, items[2].id)

        state.moveSelection(by: -10, in: items)
        XCTAssertEqual(state.selectedItemID, items[0].id)
    }

    private static func samplePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class ClipboardHistoryTestSuite {
    let defaults: UserDefaults
    let pasteboard: FakeClipboardPasteboard
    let store: ClipboardHistoryStore
    private let suiteName: String

    init(maxItems: Int = ClipboardHistoryStore.defaultMaxItems) throws {
        suiteName = "ClipboardHistoryStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        pasteboard = FakeClipboardPasteboard()
        store = ClipboardHistoryStore(
            userDefaults: defaults,
            pasteboard: pasteboard,
            maxItems: maxItems,
            pollInterval: 100
        )
    }

    func removePersistentDomain() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class FakeClipboardPasteboard: ClipboardPasteboardAccessing {
    var changeCount = 0
    var nextItem: ClipboardHistoryItem?
    private(set) var writtenItems: [ClipboardHistoryItem] = []

    func currentHistoryItem(createdAt: Date) -> ClipboardHistoryItem? {
        nextItem
    }

    func write(_ item: ClipboardHistoryItem) -> Bool {
        writtenItems.append(item)
        changeCount += 1
        return true
    }
}
