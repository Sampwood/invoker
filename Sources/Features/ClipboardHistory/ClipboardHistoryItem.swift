import AppKit
import CryptoKit
import Foundation

struct ClipboardRepresentation: Codable, Equatable, Hashable, Sendable {
    let typeIdentifier: String
    let data: Data
}

struct ClipboardSnapshotItem: Codable, Equatable, Hashable, Sendable {
    let representations: [ClipboardRepresentation]
}

struct ClipboardSnapshot: Codable, Equatable, Hashable, Sendable {
    let items: [ClipboardSnapshotItem]

    var payloadHash: String {
        var payload = Data()
        Self.append(UInt64(items.count), to: &payload)

        for (itemIndex, item) in items.enumerated() {
            Self.append(UInt64(itemIndex), to: &payload)
            Self.append(UInt64(item.representations.count), to: &payload)

            for (representationIndex, representation) in item.representations.enumerated() {
                Self.append(UInt64(representationIndex), to: &payload)
                let typeData = Data(representation.typeIdentifier.utf8)
                Self.append(UInt64(typeData.count), to: &payload)
                payload.append(typeData)
                Self.append(UInt64(representation.data.count), to: &payload)
                payload.append(representation.data)
            }
        }

        return SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var byteCount: Int {
        items.reduce(0) { itemTotal, item in
            itemTotal + item.representations.reduce(0) { representationTotal, representation in
                representationTotal
                    + representation.typeIdentifier.utf8.count
                    + representation.data.count
            }
        }
    }

    var typeIdentifiers: [String] {
        items.flatMap(\.representations).map(\.typeIdentifier)
    }

    var extractedText: String? {
        let values = items.flatMap { item in
            item.representations.compactMap { Self.text(from: $0) }
        }
        let text = Self.uniqueNonempty(values).joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    var fileNames: [String] {
        Self.uniqueNonempty(
            representations(ofType: NSPasteboard.PasteboardType.fileURL.rawValue).compactMap { representation in
                guard let value = Self.string(from: representation.data),
                      let url = URL(string: value)
                else {
                    return nil
                }
                return url.lastPathComponent
            }
        )
    }

    var urls: [String] {
        let urlTypes = [
            NSPasteboard.PasteboardType.URL.rawValue,
            NSPasteboard.PasteboardType.fileURL.rawValue
        ]
        return Self.uniqueNonempty(
            urlTypes.flatMap { typeIdentifier in
                representations(ofType: typeIdentifier).compactMap { Self.string(from: $0.data) }
            }
        )
    }

    func representations(ofType typeIdentifier: String) -> [ClipboardRepresentation] {
        items.flatMap(\.representations).filter { $0.typeIdentifier == typeIdentifier }
    }

    private static func text(from representation: ClipboardRepresentation) -> String? {
        switch representation.typeIdentifier {
        case NSPasteboard.PasteboardType.string.rawValue,
             NSPasteboard.PasteboardType.URL.rawValue,
             NSPasteboard.PasteboardType.fileURL.rawValue:
            return string(from: representation.data)
        case NSPasteboard.PasteboardType.rtf.rawValue:
            return attributedString(from: representation.data, documentType: .rtf)
        case NSPasteboard.PasteboardType.html.rawValue:
            return attributedString(from: representation.data, documentType: .html)
        default:
            return nil
        }
    }

    private static func string(from data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
    }

    private static func attributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> String? {
        let attributedString = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
        return attributedString?.string
    }

    private static func uniqueNonempty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

struct ClipboardSourceApplication: Codable, Equatable, Hashable, Sendable {
    let bundleIdentifier: String?
    let name: String
    let bundlePath: String?
}

struct ClipboardHistoryItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case text
        case richText
        case image
        case file
        case url
    }

    let id: UUID
    let createdAt: Date
    let isPinned: Bool
    let snapshot: ClipboardSnapshot
    let sourceApplication: ClipboardSourceApplication?
    let payloadHash: String
    let previewPNGData: Data?
    let ocrText: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isPinned: Bool = false,
        snapshot: ClipboardSnapshot,
        sourceApplication: ClipboardSourceApplication? = nil,
        payloadHash: String? = nil,
        previewPNGData: Data? = nil,
        ocrText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.snapshot = snapshot
        self.sourceApplication = sourceApplication
        self.payloadHash = payloadHash ?? snapshot.payloadHash
        self.previewPNGData = previewPNGData
        self.ocrText = ocrText
    }

    init(
        id: UUID = UUID(),
        kind: Kind,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        text: String? = nil,
        imagePNGData: Data? = nil
    ) {
        switch kind {
        case .image:
            self = .image(
                pngData: imagePNGData ?? Data(),
                id: id,
                createdAt: createdAt,
                isPinned: isPinned
            )
        case .file, .url, .richText, .text:
            self = .text(
                text ?? "",
                id: id,
                createdAt: createdAt,
                isPinned: isPinned
            )
        }
    }

    var kind: Kind {
        let types = Set(snapshot.typeIdentifiers)
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            return .file
        }
        if types.contains(NSPasteboard.PasteboardType.png.rawValue)
            || types.contains(NSPasteboard.PasteboardType.tiff.rawValue) {
            return .image
        }
        if types.contains(NSPasteboard.PasteboardType.URL.rawValue) {
            return .url
        }
        if types.contains(NSPasteboard.PasteboardType.rtf.rawValue)
            || types.contains(NSPasteboard.PasteboardType.html.rawValue) {
            return .richText
        }
        return .text
    }

    var text: String? {
        snapshot.extractedText
    }

    var imagePNGData: Data? {
        previewPNGData
    }

    var displayTitle: String {
        switch kind {
        case .file:
            let fileNames = snapshot.fileNames.joined(separator: ", ")
            return fileNames.isEmpty ? snapshot.urls.first ?? "文件" : fileNames
        case .url:
            return snapshot.urls.first ?? text ?? "链接"
        case .image:
            return "图片"
        case .richText, .text:
            return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    var searchableText: String {
        let fileNames: String = snapshot.fileNames.joined(separator: " ")
        let urls: String = snapshot.urls.joined(separator: " ")
        var components: [String] = [
            text,
            fileNames,
            urls,
            sourceApplication?.name,
            sourceApplication?.bundleIdentifier,
            ocrText
        ].compactMap { $0 }
        components.append(contentsOf: snapshot.typeIdentifiers.map(Self.displayName(forType:)))
        return components.joined(separator: "\n")
    }

    var logicalByteCount: Int {
        snapshot.byteCount
            + (previewPNGData?.count ?? 0)
            + (ocrText?.utf8.count ?? 0)
    }

    static func text(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isPinned: Bool = false,
        sourceApplication: ClipboardSourceApplication? = nil
    ) -> ClipboardHistoryItem {
        let representation = ClipboardRepresentation(
            typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
            data: Data(text.utf8)
        )
        return ClipboardHistoryItem(
            id: id,
            createdAt: createdAt,
            isPinned: isPinned,
            snapshot: ClipboardSnapshot(
                items: [ClipboardSnapshotItem(representations: [representation])]
            ),
            sourceApplication: sourceApplication
        )
    }

    static func image(
        pngData: Data,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isPinned: Bool = false,
        sourceApplication: ClipboardSourceApplication? = nil
    ) -> ClipboardHistoryItem {
        let representation = ClipboardRepresentation(
            typeIdentifier: NSPasteboard.PasteboardType.png.rawValue,
            data: pngData
        )
        return ClipboardHistoryItem(
            id: id,
            createdAt: createdAt,
            isPinned: isPinned,
            snapshot: ClipboardSnapshot(
                items: [ClipboardSnapshotItem(representations: [representation])]
            ),
            sourceApplication: sourceApplication,
            previewPNGData: pngData
        )
    }

    func refreshingTimestamp(
        _ date: Date = Date(),
        sourceApplication: ClipboardSourceApplication? = nil
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            createdAt: date,
            isPinned: isPinned,
            snapshot: snapshot,
            sourceApplication: sourceApplication ?? self.sourceApplication,
            payloadHash: payloadHash,
            previewPNGData: previewPNGData,
            ocrText: ocrText
        )
    }

    func settingPinned(_ isPinned: Bool) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            createdAt: createdAt,
            isPinned: isPinned,
            snapshot: snapshot,
            sourceApplication: sourceApplication,
            payloadHash: payloadHash,
            previewPNGData: previewPNGData,
            ocrText: ocrText
        )
    }

    func settingOCRText(_ ocrText: String?) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            createdAt: createdAt,
            isPinned: isPinned,
            snapshot: snapshot,
            sourceApplication: sourceApplication,
            payloadHash: payloadHash,
            previewPNGData: previewPNGData,
            ocrText: ocrText
        )
    }

    func preservingIdentityAndPin(from existing: ClipboardHistoryItem) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: existing.id,
            createdAt: createdAt,
            isPinned: existing.isPinned,
            snapshot: snapshot,
            sourceApplication: sourceApplication,
            payloadHash: payloadHash,
            previewPNGData: previewPNGData,
            ocrText: ocrText ?? existing.ocrText
        )
    }

    func hasSamePayload(as other: ClipboardHistoryItem) -> Bool {
        payloadHash == other.payloadHash && snapshot == other.snapshot
    }

    private static func displayName(forType typeIdentifier: String) -> String {
        switch typeIdentifier {
        case NSPasteboard.PasteboardType.string.rawValue:
            return "文本"
        case NSPasteboard.PasteboardType.rtf.rawValue:
            return "富文本"
        case NSPasteboard.PasteboardType.html.rawValue:
            return "HTML"
        case NSPasteboard.PasteboardType.fileURL.rawValue:
            return "文件"
        case NSPasteboard.PasteboardType.URL.rawValue:
            return "链接"
        case NSPasteboard.PasteboardType.png.rawValue,
             NSPasteboard.PasteboardType.tiff.rawValue:
            return "图片"
        default:
            return typeIdentifier
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt
        case isPinned
        case text
        case imagePNGData
        case snapshot
        case sourceApplication
        case payloadHash
        case previewPNGData
        case ocrText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false

        if let snapshot = try container.decodeIfPresent(ClipboardSnapshot.self, forKey: .snapshot) {
            self.snapshot = snapshot
            sourceApplication = try container.decodeIfPresent(
                ClipboardSourceApplication.self,
                forKey: .sourceApplication
            )
            payloadHash = try container.decodeIfPresent(String.self, forKey: .payloadHash)
                ?? snapshot.payloadHash
            previewPNGData = try container.decodeIfPresent(Data.self, forKey: .previewPNGData)
            ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
            return
        }

        let legacyKind = try container.decode(Kind.self, forKey: .kind)
        let legacyText = try container.decodeIfPresent(String.self, forKey: .text)
        let legacyPNGData = try container.decodeIfPresent(Data.self, forKey: .imagePNGData)
        let legacyItem: ClipboardHistoryItem
        if legacyKind == .image {
            legacyItem = .image(
                pngData: legacyPNGData ?? Data(),
                id: id,
                createdAt: createdAt,
                isPinned: isPinned
            )
        } else {
            legacyItem = .text(
                legacyText ?? "",
                id: id,
                createdAt: createdAt,
                isPinned: isPinned
            )
        }
        snapshot = legacyItem.snapshot
        sourceApplication = nil
        payloadHash = legacyItem.payloadHash
        previewPNGData = legacyItem.previewPNGData
        ocrText = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(snapshot, forKey: .snapshot)
        try container.encodeIfPresent(sourceApplication, forKey: .sourceApplication)
        try container.encode(payloadHash, forKey: .payloadHash)
        try container.encodeIfPresent(previewPNGData, forKey: .previewPNGData)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
    }
}
