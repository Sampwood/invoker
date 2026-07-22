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

    func testDuplicatePayloadMovesNewestItemToTopAndPreservesIdentity() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let first = ClipboardHistoryItem.text("repeat", createdAt: Date(timeIntervalSince1970: 1))
        let second = ClipboardHistoryItem.text("other", createdAt: Date(timeIntervalSince1970: 2))
        let duplicate = ClipboardHistoryItem.text("repeat", createdAt: Date(timeIntervalSince1970: 3))

        suite.store.record(first)
        suite.store.record(second)
        suite.store.record(duplicate)

        XCTAssertEqual(suite.store.items.map(\.text), ["repeat", "other"])
        XCTAssertEqual(suite.store.items.first?.id, first.id)
        XCTAssertEqual(suite.store.items.first?.createdAt, duplicate.createdAt)
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

    func testDecodesLegacyItemsAsUnpinned() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let legacyItem = LegacyClipboardHistoryItem(
            id: UUID(),
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 1),
            text: "legacy",
            imagePNGData: nil
        )
        suite.defaults.set(
            try JSONEncoder().encode([legacyItem]),
            forKey: ClipboardHistoryStore.defaultsKey
        )

        let reloadedStore = ClipboardHistoryStore(
            userDefaults: suite.defaults,
            pasteboard: suite.pasteboard,
            pollInterval: 100
        )

        XCTAssertEqual(reloadedStore.items.map(\.text), ["legacy"])
        XCTAssertFalse(try XCTUnwrap(reloadedStore.items.first).isPinned)
    }

    func testPinningMovesItemsToTopAndReuseKeepsPinnedOrderStable() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let first = ClipboardHistoryItem.text("first", createdAt: Date(timeIntervalSince1970: 1))
        let second = ClipboardHistoryItem.text("second", createdAt: Date(timeIntervalSince1970: 2))
        let third = ClipboardHistoryItem.text("third", createdAt: Date(timeIntervalSince1970: 3))
        suite.store.record(first)
        suite.store.record(second)
        suite.store.record(third)

        XCTAssertEqual(suite.store.togglePin(for: first.id), .pinned)
        XCTAssertEqual(suite.store.togglePin(for: second.id), .pinned)
        XCTAssertEqual(suite.store.items.map(\.text), ["second", "first", "third"])

        let pinnedFirst = try XCTUnwrap(suite.store.items.first { $0.id == first.id })
        XCTAssertTrue(
            suite.store.copyToPasteboard(
                pinnedFirst,
                createdAt: Date(timeIntervalSince1970: 4)
            )
        )

        XCTAssertEqual(suite.store.items.map(\.text), ["second", "first", "third"])
        XCTAssertEqual(suite.store.items[1].id, first.id)
        XCTAssertEqual(suite.store.items[1].createdAt, Date(timeIntervalSince1970: 4))
        XCTAssertTrue(suite.store.items[1].isPinned)
    }

    func testPinnedItemsDoNotUseUnpinnedCapacity() throws {
        let suite = try ClipboardHistoryTestSuite(maxItems: 2)
        defer { suite.removePersistentDomain() }
        let pinnedItem = ClipboardHistoryItem.text("pinned")
        suite.store.record(pinnedItem)
        XCTAssertEqual(suite.store.togglePin(for: pinnedItem.id), .pinned)

        suite.store.record(.text("one"))
        suite.store.record(.text("two"))
        suite.store.record(.text("three"))

        XCTAssertEqual(suite.store.items.map(\.text), ["pinned", "three", "two"])
        XCTAssertEqual(suite.store.pinnedItemCount, 1)
        XCTAssertEqual(suite.store.unpinnedItemCount, 2)
    }

    func testRejectsPinBeyondPinnedLimitWithoutChangingItems() throws {
        let suite = try ClipboardHistoryTestSuite(maxPinnedItems: 2)
        defer { suite.removePersistentDomain() }
        let first = ClipboardHistoryItem.text("first")
        let second = ClipboardHistoryItem.text("second")
        let third = ClipboardHistoryItem.text("third")
        suite.store.record(first)
        suite.store.record(second)
        suite.store.record(third)
        XCTAssertEqual(suite.store.togglePin(for: first.id), .pinned)
        XCTAssertEqual(suite.store.togglePin(for: second.id), .pinned)
        let itemsBeforeRejectedPin = suite.store.items

        XCTAssertEqual(suite.store.togglePin(for: third.id), .limitReached)

        XCTAssertEqual(suite.store.items, itemsBeforeRejectedPin)
        XCTAssertEqual(suite.store.pinnedItemCount, 2)
        XCTAssertFalse(try XCTUnwrap(suite.store.items.first { $0.id == third.id }).isPinned)
    }

    func testUnpinningMovesItemToTopOfUnpinnedHistoryAndTrimsOldest() throws {
        let suite = try ClipboardHistoryTestSuite(maxItems: 2)
        defer { suite.removePersistentDomain() }
        let pinnedItem = ClipboardHistoryItem.text("pinned")
        suite.store.record(pinnedItem)
        suite.store.record(.text("old"))
        XCTAssertEqual(suite.store.togglePin(for: pinnedItem.id), .pinned)
        suite.store.record(.text("newer"))
        suite.store.record(.text("newest"))

        XCTAssertEqual(suite.store.togglePin(for: pinnedItem.id), .unpinned)

        XCTAssertEqual(suite.store.items.map(\.text), ["pinned", "newest"])
        XCTAssertEqual(suite.store.pinnedItemCount, 0)
        XCTAssertEqual(suite.store.unpinnedItemCount, 2)
    }

    func testClearUnpinnedPreservesPinnedItems() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let pinnedItem = ClipboardHistoryItem.text("keep")
        suite.store.record(pinnedItem)
        suite.store.record(.text("remove"))
        XCTAssertEqual(suite.store.togglePin(for: pinnedItem.id), .pinned)

        suite.store.clearUnpinned()

        XCTAssertEqual(suite.store.items.map(\.text), ["keep"])
        XCTAssertTrue(try XCTUnwrap(suite.store.items.first).isPinned)
        XCTAssertFalse(suite.store.hasUnpinnedItems)
    }

    func testPersistsPinnedStateAndStableOrder() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let first = ClipboardHistoryItem.text("first")
        let second = ClipboardHistoryItem.text("second")
        suite.store.record(first)
        suite.store.record(second)
        XCTAssertEqual(suite.store.togglePin(for: first.id), .pinned)
        XCTAssertEqual(suite.store.togglePin(for: second.id), .pinned)

        let reloadedStore = ClipboardHistoryStore(
            userDefaults: suite.defaults,
            pasteboard: suite.pasteboard,
            pollInterval: 100
        )

        XCTAssertEqual(reloadedStore.items, suite.store.items)
        XCTAssertEqual(reloadedStore.items.map(\.text), ["second", "first"])
        XCTAssertTrue(reloadedStore.items.allSatisfy(\.isPinned))
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

    init(
        maxItems: Int = ClipboardHistoryStore.defaultMaxItems,
        maxPinnedItems: Int = ClipboardHistoryStore.defaultMaxPinnedItems
    ) throws {
        suiteName = "ClipboardHistoryStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        pasteboard = FakeClipboardPasteboard()
        store = ClipboardHistoryStore(
            userDefaults: defaults,
            pasteboard: pasteboard,
            maxItems: maxItems,
            maxPinnedItems: maxPinnedItems,
            pollInterval: 100
        )
    }

    func removePersistentDomain() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct LegacyClipboardHistoryItem: Encodable {
    let id: UUID
    let kind: ClipboardHistoryItem.Kind
    let createdAt: Date
    let text: String?
    let imagePNGData: Data?
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
