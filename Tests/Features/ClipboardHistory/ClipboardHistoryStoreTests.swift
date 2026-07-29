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
        suite.pasteboard.typeIdentifiers = Set(item.snapshot.typeIdentifiers)
        suite.pasteboard.changeCount = 1

        suite.store.captureCurrentItemIfChanged()

        XCTAssertEqual(suite.store.items, [item])
        XCTAssertEqual(suite.pasteboard.readCount, 1)
    }

    func testSensitiveMarkerIsRejectedBeforePayloadRead() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        suite.pasteboard.nextItem = .text("secret")
        suite.pasteboard.typeIdentifiers = ["org.nspasteboard.ConcealedType"]
        suite.pasteboard.changeCount = 1

        suite.store.captureCurrentItemIfChanged()

        XCTAssertTrue(suite.store.items.isEmpty)
        XCTAssertEqual(suite.pasteboard.readCount, 0)
    }

    func testRemoteClipboardIsIgnoredByDefaultAndCanBeEnabled() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        suite.pasteboard.nextItem = .text("remote")
        suite.pasteboard.typeIdentifiers = [ClipboardCapturePolicy.remoteClipboardTypeIdentifier]
        suite.pasteboard.changeCount = 1

        suite.store.captureCurrentItemIfChanged()
        XCTAssertTrue(suite.store.items.isEmpty)

        suite.settings.capturesUniversalClipboard = true
        suite.pasteboard.changeCount = 2
        suite.store.captureCurrentItemIfChanged()

        XCTAssertEqual(suite.store.items.map(\.text), ["remote"])
    }

    func testBuiltInPasswordManagerAndCustomApplicationAreIgnored() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        suite.pasteboard.nextItem = .text("secret")
        suite.pasteboard.typeIdentifiers = [NSPasteboard.PasteboardType.string.rawValue]

        suite.sourceProvider.application = ClipboardSourceApplication(
            bundleIdentifier: "com.bitwarden.desktop",
            name: "Bitwarden",
            bundlePath: nil
        )
        suite.pasteboard.changeCount = 1
        suite.store.captureCurrentItemIfChanged()
        XCTAssertEqual(suite.pasteboard.readCount, 0)

        suite.settings.addIgnoredApplication(
            IgnoredClipboardApplication(
                bundleIdentifier: "com.example.private",
                name: "Private",
                bundlePath: nil
            )
        )
        suite.sourceProvider.application = ClipboardSourceApplication(
            bundleIdentifier: "com.example.private",
            name: "Private",
            bundlePath: nil
        )
        suite.pasteboard.changeCount = 2
        suite.store.captureCurrentItemIfChanged()

        XCTAssertTrue(suite.store.items.isEmpty)
        XCTAssertEqual(suite.pasteboard.readCount, 0)
    }

    func testBuiltInPasswordManagerCanBeDisabled() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let bitwarden = try XCTUnwrap(
            PasswordManagerCatalog.entries.first { $0.id == "bitwarden" }
        )
        suite.settings.setPasswordManager(bitwarden, enabled: false)
        suite.sourceProvider.application = ClipboardSourceApplication(
            bundleIdentifier: "com.bitwarden.desktop",
            name: "Bitwarden",
            bundlePath: nil
        )
        suite.pasteboard.nextItem = .text(
            "allowed",
            sourceApplication: suite.sourceProvider.application
        )
        suite.pasteboard.typeIdentifiers = [NSPasteboard.PasteboardType.string.rawValue]
        suite.pasteboard.changeCount = 1

        suite.store.captureCurrentItemIfChanged()

        XCTAssertEqual(suite.store.items.map(\.text), ["allowed"])
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

    func testSnapshotHashIncludesRepresentationOrderAndType() {
        let text = ClipboardRepresentation(
            typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
            data: Data("hello".utf8)
        )
        let html = ClipboardRepresentation(
            typeIdentifier: NSPasteboard.PasteboardType.html.rawValue,
            data: Data("<b>hello</b>".utf8)
        )
        let first = ClipboardSnapshot(
            items: [ClipboardSnapshotItem(representations: [text, html])]
        )
        let second = ClipboardSnapshot(
            items: [ClipboardSnapshotItem(representations: [html, text])]
        )

        XCTAssertNotEqual(first.payloadHash, second.payloadHash)
    }

    func testTrimsOnlyUnpinnedItemsToCountLimit() throws {
        let suite = try ClipboardHistoryTestSuite(maxItems: 2)
        defer { suite.removePersistentDomain() }
        let pinned = ClipboardHistoryItem.text("pinned")
        suite.store.record(pinned)
        XCTAssertEqual(suite.store.togglePin(for: pinned.id), .pinned)

        suite.store.record(.text("one"))
        suite.store.record(.text("two"))
        suite.store.record(.text("three"))

        XCTAssertEqual(suite.store.items.map(\.text), ["pinned", "three", "two"])
    }

    func testCopyToPasteboardWritesAllRepresentationsAndAvoidsRecapture() throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let item = richTextItem()
        suite.store.record(item)

        XCTAssertTrue(suite.store.copyToPasteboard(item))
        suite.store.captureCurrentItemIfChanged()

        XCTAssertEqual(suite.pasteboard.writtenItems, [item])
        XCTAssertEqual(suite.store.items.count, 1)
    }

    func testPersistsAndReloadsItems() async throws {
        let suite = try ClipboardHistoryTestSuite()
        defer { suite.removePersistentDomain() }
        let textItem = ClipboardHistoryItem.text("persisted")
        let richItem = richTextItem()
        suite.store.record(textItem)
        suite.store.record(richItem)
        await suite.store.waitForPendingPersistence()

        let reloadedStore = ClipboardHistoryStore(
            userDefaults: suite.defaults,
            settings: suite.settings,
            pasteboard: suite.pasteboard,
            sourceApplicationProvider: suite.sourceProvider,
            repository: suite.repository,
            ocrRecognizer: EmptyClipboardOCRRecognizer(),
            pollInterval: 100
        )
        await reloadedStore.loadPersistedHistory()

        XCTAssertEqual(reloadedStore.items, suite.store.items)
    }

    func testMigratesLegacyUserDefaultsIntoRepository() async throws {
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

        await suite.store.loadPersistedHistory()

        XCTAssertEqual(suite.store.items.map(\.text), ["legacy"])
        XCTAssertNil(suite.defaults.data(forKey: ClipboardHistoryStore.defaultsKey))
        let migratedItems = try await suite.repository.loadItems()
        XCTAssertEqual(migratedItems, suite.store.items)
    }

    func testSQLiteRepositoryRoundTripsMultiplePasteboardItems() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteClipboardHistoryRepository(
            databaseURL: directory.appendingPathComponent("history.sqlite3")
        )
        let item = ClipboardHistoryItem(
            snapshot: ClipboardSnapshot(
                items: [
                    ClipboardSnapshotItem(
                        representations: [
                            ClipboardRepresentation(
                                typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
                                data: Data("first".utf8)
                            )
                        ]
                    ),
                    ClipboardSnapshotItem(
                        representations: [
                            ClipboardRepresentation(
                                typeIdentifier: NSPasteboard.PasteboardType.URL.rawValue,
                                data: Data("https://example.com".utf8)
                            )
                        ]
                    )
                ]
            ),
            sourceApplication: ClipboardSourceApplication(
                bundleIdentifier: "com.example.source",
                name: "Source",
                bundlePath: "/Applications/Source.app"
            )
        )

        try await repository.synchronize([item])

        let reloadedItems = try await repository.loadItems()
        XCTAssertEqual(reloadedItems, [item])
    }

    func testSystemPasteboardAccessorPreservesSupportedRepresentations() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("hello", forType: .string)
        pasteboardItem.setData(Data("<b>hello</b>".utf8), forType: .html)
        XCTAssertTrue(pasteboard.writeObjects([pasteboardItem]))
        let accessor = SystemClipboardPasteboardAccessor(pasteboard: pasteboard)

        let item = try XCTUnwrap(
            accessor.currentHistoryItem(createdAt: Date(), sourceApplication: nil)
        )

        XCTAssertEqual(
            Set(item.snapshot.typeIdentifiers),
            Set([
                NSPasteboard.PasteboardType.string.rawValue,
                NSPasteboard.PasteboardType.html.rawValue
            ])
        )
        XCTAssertTrue(accessor.write(item))
    }

    func testPresentationSearchIncludesSourceTypeAndOCRText() {
        let state = ClipboardHistoryPresentationState()
        let source = ClipboardSourceApplication(
            bundleIdentifier: "com.example.notes",
            name: "Notes",
            bundlePath: nil
        )
        let textItem = ClipboardHistoryItem.text("Project README", sourceApplication: source)
        let imageItem = ClipboardHistoryItem.image(pngData: Data([0])).settingOCRText("invoice 2026")
        let items = [textItem, imageItem]

        state.query = "notes"
        XCTAssertEqual(state.filteredItems(from: items), [textItem])
        state.query = "invoice"
        XCTAssertEqual(state.filteredItems(from: items), [imageItem])
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
        state.moveSelection(by: 10, in: items)
        XCTAssertEqual(state.selectedItemID, items[2].id)
        state.moveSelection(by: -10, in: items)
        XCTAssertEqual(state.selectedItemID, items[0].id)
    }

    private func richTextItem() -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            snapshot: ClipboardSnapshot(
                items: [
                    ClipboardSnapshotItem(
                        representations: [
                            ClipboardRepresentation(
                                typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
                                data: Data("hello".utf8)
                            ),
                            ClipboardRepresentation(
                                typeIdentifier: NSPasteboard.PasteboardType.html.rawValue,
                                data: Data("<b>hello</b>".utf8)
                            )
                        ]
                    )
                ]
            )
        )
    }
}

@MainActor
private final class ClipboardHistoryTestSuite {
    let defaults: UserDefaults
    let settings: ClipboardHistorySettingsStore
    let pasteboard: FakeClipboardPasteboard
    let sourceProvider: FakeClipboardSourceApplicationProvider
    let repository: InMemoryClipboardHistoryRepository
    let store: ClipboardHistoryStore
    private let suiteName: String

    init(maxItems: Int = ClipboardHistoryStore.defaultMaxItems) throws {
        suiteName = "ClipboardHistoryStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = ClipboardHistorySettingsStore(userDefaults: defaults)
        settings.maxHistoryItems = maxItems
        pasteboard = FakeClipboardPasteboard()
        sourceProvider = FakeClipboardSourceApplicationProvider()
        repository = InMemoryClipboardHistoryRepository()
        store = ClipboardHistoryStore(
            userDefaults: defaults,
            settings: settings,
            pasteboard: pasteboard,
            sourceApplicationProvider: sourceProvider,
            repository: repository,
            ocrRecognizer: EmptyClipboardOCRRecognizer(),
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

private struct EmptyClipboardOCRRecognizer: ClipboardOCRRecognizing {
    func recognizeText(in pngData: Data) async throws -> String? {
        nil
    }
}

@MainActor
private final class FakeClipboardSourceApplicationProvider: ClipboardSourceApplicationProviding {
    var application: ClipboardSourceApplication?

    func frontmostApplication() -> ClipboardSourceApplication? {
        application
    }
}

@MainActor
private final class FakeClipboardPasteboard: ClipboardPasteboardAccessing {
    var changeCount = 0
    var typeIdentifiers: Set<String> = []
    var nextItem: ClipboardHistoryItem?
    private(set) var readCount = 0
    private(set) var writtenItems: [ClipboardHistoryItem] = []

    var availableTypeIdentifiers: Set<String> {
        typeIdentifiers
    }

    func currentHistoryItem(
        createdAt: Date,
        sourceApplication: ClipboardSourceApplication?
    ) -> ClipboardHistoryItem? {
        readCount += 1
        return nextItem
    }

    func write(_ item: ClipboardHistoryItem) -> Bool {
        writtenItems.append(item)
        changeCount += 1
        return true
    }
}
