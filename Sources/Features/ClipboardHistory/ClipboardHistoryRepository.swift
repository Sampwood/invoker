import Foundation
import SQLite3

protocol ClipboardHistoryRepository: Actor {
    func loadItems() throws -> [ClipboardHistoryItem]
    func synchronize(_ items: [ClipboardHistoryItem]) throws
}

enum ClipboardHistoryRepositoryError: LocalizedError {
    case cannotCreateDirectory(String)
    case cannotOpenDatabase(String)
    case databaseOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .cannotCreateDirectory(path):
            return "无法创建剪贴板历史目录：\(path)"
        case let .cannotOpenDatabase(path):
            return "无法打开剪贴板历史数据库：\(path)"
        case let .databaseOperationFailed(message):
            return "剪贴板历史数据库操作失败：\(message)"
        }
    }
}

actor InMemoryClipboardHistoryRepository: ClipboardHistoryRepository {
    private var items: [ClipboardHistoryItem]

    init(items: [ClipboardHistoryItem] = []) {
        self.items = items
    }

    func loadItems() throws -> [ClipboardHistoryItem] {
        items
    }

    func synchronize(_ items: [ClipboardHistoryItem]) throws {
        self.items = items
    }
}

actor SQLiteClipboardHistoryRepository: ClipboardHistoryRepository {
    private final class Connection: @unchecked Sendable {
        let pointer: OpaquePointer

        init(pointer: OpaquePointer) {
            self.pointer = pointer
        }

        deinit {
            sqlite3_close_v2(pointer)
        }
    }

    private struct StoredMetadata {
        let id: UUID
        let createdAt: Date
        let isPinned: Bool
        let sourceApplication: ClipboardSourceApplication?
        let payloadHash: String
        let previewPNGData: Data?
        let ocrText: String?
    }

    private let databaseURL: URL
    private let connection: Connection
    private var database: OpaquePointer? { connection.pointer }
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil) == SQLITE_OK,
              let openedDatabase
        else {
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            throw ClipboardHistoryRepositoryError.cannotOpenDatabase(databaseURL.path)
        }
        connection = Connection(pointer: openedDatabase)

        do {
            try Self.execute("PRAGMA foreign_keys = ON", database: openedDatabase)
            try Self.execute("PRAGMA journal_mode = WAL", database: openedDatabase)
            try Self.execute("PRAGMA synchronous = NORMAL", database: openedDatabase)
            try Self.execute(Self.schemaSQL, database: openedDatabase)
            try Self.execute("PRAGMA user_version = 1", database: openedDatabase)
        } catch {
            throw error
        }
    }

    static func makeDefault() throws -> SQLiteClipboardHistoryRepository {
        try SQLiteClipboardHistoryRepository(databaseURL: defaultDatabaseURL())
    }

    static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupportURL: URL
        do {
            applicationSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw ClipboardHistoryRepositoryError.cannotCreateDirectory(
                "~/Library/Application Support"
            )
        }

        let directoryURL = applicationSupportURL.appendingPathComponent(
            "Invoker",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ClipboardHistoryRepositoryError.cannotCreateDirectory(directoryURL.path)
        }
        return directoryURL.appendingPathComponent("ClipboardHistory.sqlite3")
    }

    func loadItems() throws -> [ClipboardHistoryItem] {
        guard let database else {
            throw ClipboardHistoryRepositoryError.cannotOpenDatabase(databaseURL.path)
        }

        let metadata = try loadMetadata(database: database)
        let representations = try loadRepresentations(database: database)

        return metadata.compactMap { stored in
            guard let snapshotItems = representations[stored.id], !snapshotItems.isEmpty else {
                return nil
            }
            return ClipboardHistoryItem(
                id: stored.id,
                createdAt: stored.createdAt,
                isPinned: stored.isPinned,
                snapshot: ClipboardSnapshot(items: snapshotItems),
                sourceApplication: stored.sourceApplication,
                payloadHash: stored.payloadHash,
                previewPNGData: stored.previewPNGData,
                ocrText: stored.ocrText
            )
        }
    }

    func synchronize(_ items: [ClipboardHistoryItem]) throws {
        guard let database else {
            throw ClipboardHistoryRepositoryError.cannotOpenDatabase(databaseURL.path)
        }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let existingHashes = try loadExistingHashes(database: database)
            let retainedIDs = Set(items.map { $0.id.uuidString })

            for (position, item) in items.enumerated() {
                try upsertMetadata(item, position: position, database: database)
                if existingHashes[item.id.uuidString] != item.payloadHash {
                    try replaceRepresentations(for: item, database: database)
                }
            }

            for id in existingHashes.keys where !retainedIDs.contains(id) {
                try deleteItem(id: id, database: database)
            }

            try execute("COMMIT TRANSACTION")
            try execute("PRAGMA wal_checkpoint(PASSIVE)")
        } catch {
            try? execute("ROLLBACK TRANSACTION")
            throw error
        }
    }

    private func loadMetadata(database: OpaquePointer) throws -> [StoredMetadata] {
        let sql = """
        SELECT id, created_at, is_pinned, source_bundle_identifier, source_app_name,
               source_bundle_path, payload_hash, preview_png, ocr_text
        FROM history_items
        ORDER BY position ASC
        """
        let statement = try prepare(sql, database: database)
        defer { sqlite3_finalize(statement) }

        var items: [StoredMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idValue = text(at: 0, statement: statement),
                  let id = UUID(uuidString: idValue),
                  let payloadHash = text(at: 6, statement: statement)
            else {
                continue
            }

            let sourceName = text(at: 4, statement: statement)
            let sourceBundleIdentifier = text(at: 3, statement: statement)
            let sourceApplication: ClipboardSourceApplication?
            if sourceName != nil || sourceBundleIdentifier != nil {
                sourceApplication = ClipboardSourceApplication(
                    bundleIdentifier: sourceBundleIdentifier,
                    name: sourceName ?? sourceBundleIdentifier ?? "未知应用",
                    bundlePath: text(at: 5, statement: statement)
                )
            } else {
                sourceApplication = nil
            }

            items.append(
                StoredMetadata(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    isPinned: sqlite3_column_int(statement, 2) != 0,
                    sourceApplication: sourceApplication,
                    payloadHash: payloadHash,
                    previewPNGData: data(at: 7, statement: statement),
                    ocrText: text(at: 8, statement: statement)
                )
            )
        }
        return items
    }

    private func loadRepresentations(
        database: OpaquePointer
    ) throws -> [UUID: [ClipboardSnapshotItem]] {
        let sql = """
        SELECT item_id, pasteboard_item_index, representation_index, type_identifier, data
        FROM representations
        ORDER BY item_id, pasteboard_item_index, representation_index
        """
        let statement = try prepare(sql, database: database)
        defer { sqlite3_finalize(statement) }

        var grouped: [UUID: [Int: [ClipboardRepresentation]]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idValue = text(at: 0, statement: statement),
                  let id = UUID(uuidString: idValue),
                  let typeIdentifier = text(at: 3, statement: statement),
                  let representationData = data(at: 4, statement: statement)
            else {
                continue
            }
            let itemIndex = Int(sqlite3_column_int(statement, 1))
            grouped[id, default: [:]][itemIndex, default: []].append(
                ClipboardRepresentation(
                    typeIdentifier: typeIdentifier,
                    data: representationData
                )
            )
        }

        return grouped.mapValues { indexedItems in
            indexedItems.keys.sorted().map { itemIndex in
                ClipboardSnapshotItem(representations: indexedItems[itemIndex] ?? [])
            }
        }
    }

    private func loadExistingHashes(database: OpaquePointer) throws -> [String: String] {
        let statement = try prepare(
            "SELECT id, payload_hash FROM history_items",
            database: database
        )
        defer { sqlite3_finalize(statement) }

        var hashes: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = text(at: 0, statement: statement),
               let hash = text(at: 1, statement: statement) {
                hashes[id] = hash
            }
        }
        return hashes
    }

    private func upsertMetadata(
        _ item: ClipboardHistoryItem,
        position: Int,
        database: OpaquePointer
    ) throws {
        let sql = """
        INSERT INTO history_items (
            id, position, created_at, is_pinned, source_bundle_identifier,
            source_app_name, source_bundle_path, payload_hash, preview_png, ocr_text
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            position = excluded.position,
            created_at = excluded.created_at,
            is_pinned = excluded.is_pinned,
            source_bundle_identifier = excluded.source_bundle_identifier,
            source_app_name = excluded.source_app_name,
            source_bundle_path = excluded.source_bundle_path,
            payload_hash = excluded.payload_hash,
            preview_png = excluded.preview_png,
            ocr_text = excluded.ocr_text
        """
        let statement = try prepare(sql, database: database)
        defer { sqlite3_finalize(statement) }

        try bind(item.id.uuidString, at: 1, statement: statement)
        sqlite3_bind_int(statement, 2, Int32(position))
        sqlite3_bind_double(statement, 3, item.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 4, item.isPinned ? 1 : 0)
        try bind(item.sourceApplication?.bundleIdentifier, at: 5, statement: statement)
        try bind(item.sourceApplication?.name, at: 6, statement: statement)
        try bind(item.sourceApplication?.bundlePath, at: 7, statement: statement)
        try bind(item.payloadHash, at: 8, statement: statement)
        try bind(item.previewPNGData, at: 9, statement: statement)
        try bind(item.ocrText, at: 10, statement: statement)
        try stepDone(statement, database: database)
    }

    private func replaceRepresentations(
        for item: ClipboardHistoryItem,
        database: OpaquePointer
    ) throws {
        do {
            let deleteStatement = try prepare(
                "DELETE FROM representations WHERE item_id = ?",
                database: database
            )
            defer { sqlite3_finalize(deleteStatement) }
            try bind(item.id.uuidString, at: 1, statement: deleteStatement)
            try stepDone(deleteStatement, database: database)
        }

        let sql = """
        INSERT INTO representations (
            item_id, pasteboard_item_index, representation_index, type_identifier, data
        ) VALUES (?, ?, ?, ?, ?)
        """
        for (itemIndex, snapshotItem) in item.snapshot.items.enumerated() {
            for (representationIndex, representation) in snapshotItem.representations.enumerated() {
                let statement = try prepare(sql, database: database)
                do {
                    try bind(item.id.uuidString, at: 1, statement: statement)
                    sqlite3_bind_int(statement, 2, Int32(itemIndex))
                    sqlite3_bind_int(statement, 3, Int32(representationIndex))
                    try bind(representation.typeIdentifier, at: 4, statement: statement)
                    try bind(representation.data, at: 5, statement: statement)
                    try stepDone(statement, database: database)
                    sqlite3_finalize(statement)
                } catch {
                    sqlite3_finalize(statement)
                    throw error
                }
            }
        }
    }

    private func deleteItem(id: String, database: OpaquePointer) throws {
        let statement = try prepare(
            "DELETE FROM history_items WHERE id = ?",
            database: database
        )
        defer { sqlite3_finalize(statement) }
        try bind(id, at: 1, statement: statement)
        try stepDone(statement, database: database)
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw ClipboardHistoryRepositoryError.cannotOpenDatabase(databaseURL.path)
        }
        try Self.execute(sql, database: database)
    }

    private static func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard status == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw ClipboardHistoryRepositoryError.databaseOperationFailed(message)
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw ClipboardHistoryRepositoryError.databaseOperationFailed(
                String(cString: sqlite3_errmsg(database))
            )
        }
        return statement
    }

    private func bind(_ value: String?, at index: Int32, statement: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        let status = value.withCString { valuePointer in
            sqlite3_bind_text(statement, index, valuePointer, -1, sqliteTransient)
        }
        guard status == SQLITE_OK else {
            throw ClipboardHistoryRepositoryError.databaseOperationFailed("无法绑定文本字段")
        }
    }

    private func bind(_ value: Data?, at index: Int32, statement: OpaquePointer) throws {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        let status: Int32
        if value.isEmpty {
            status = sqlite3_bind_zeroblob(statement, index, 0)
        } else {
            status = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(
                    statement,
                    index,
                    bytes.baseAddress,
                    Int32(bytes.count),
                    sqliteTransient
                )
            }
        }
        guard status == SQLITE_OK else {
            throw ClipboardHistoryRepositoryError.databaseOperationFailed("无法绑定二进制字段")
        }
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ClipboardHistoryRepositoryError.databaseOperationFailed(
                String(cString: sqlite3_errmsg(database))
            )
        }
    }

    private func text(at index: Int32, statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index)
        else {
            return nil
        }
        return String(decodingCString: value, as: UTF8.self)
    }

    private func data(at index: Int32, statement: OpaquePointer) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: bytes, count: count)
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS history_items (
        id TEXT PRIMARY KEY NOT NULL,
        position INTEGER NOT NULL,
        created_at REAL NOT NULL,
        is_pinned INTEGER NOT NULL,
        source_bundle_identifier TEXT,
        source_app_name TEXT,
        source_bundle_path TEXT,
        payload_hash TEXT NOT NULL,
        preview_png BLOB,
        ocr_text TEXT
    );
    CREATE INDEX IF NOT EXISTS history_items_position_index
        ON history_items(position);
    CREATE INDEX IF NOT EXISTS history_items_payload_hash_index
        ON history_items(payload_hash);
    CREATE TABLE IF NOT EXISTS representations (
        item_id TEXT NOT NULL,
        pasteboard_item_index INTEGER NOT NULL,
        representation_index INTEGER NOT NULL,
        type_identifier TEXT NOT NULL,
        data BLOB NOT NULL,
        PRIMARY KEY(item_id, pasteboard_item_index, representation_index),
        FOREIGN KEY(item_id) REFERENCES history_items(id) ON DELETE CASCADE
    );
    """
}
