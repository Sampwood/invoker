import Foundation

struct ClipboardHistoryItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date
    let isPinned: Bool
    let text: String?
    let imagePNGData: Data?

    init(
        id: UUID = UUID(),
        kind: Kind,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        text: String? = nil,
        imagePNGData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.text = text
        self.imagePNGData = imagePNGData
    }

    static func text(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            kind: .text,
            createdAt: createdAt,
            isPinned: isPinned,
            text: text
        )
    }

    static func image(
        pngData: Data,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            kind: .image,
            createdAt: createdAt,
            isPinned: isPinned,
            imagePNGData: pngData
        )
    }

    func refreshingTimestamp(_ date: Date = Date()) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            kind: kind,
            createdAt: date,
            isPinned: isPinned,
            text: text,
            imagePNGData: imagePNGData
        )
    }

    func settingPinned(_ isPinned: Bool) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            kind: kind,
            createdAt: createdAt,
            isPinned: isPinned,
            text: text,
            imagePNGData: imagePNGData
        )
    }

    func hasSamePayload(as other: ClipboardHistoryItem) -> Bool {
        guard kind == other.kind else {
            return false
        }

        switch kind {
        case .text:
            return text == other.text
        case .image:
            return imagePNGData == other.imagePNGData
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt
        case isPinned
        case text
        case imagePNGData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imagePNGData = try container.decodeIfPresent(Data.self, forKey: .imagePNGData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(imagePNGData, forKey: .imagePNGData)
    }
}
