import Foundation

struct ClipboardHistoryItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date
    let text: String?
    let imagePNGData: Data?

    init(
        id: UUID = UUID(),
        kind: Kind,
        createdAt: Date = Date(),
        text: String? = nil,
        imagePNGData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.text = text
        self.imagePNGData = imagePNGData
    }

    static func text(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            kind: .text,
            createdAt: createdAt,
            text: text
        )
    }

    static func image(
        pngData: Data,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            id: id,
            kind: .image,
            createdAt: createdAt,
            imagePNGData: pngData
        )
    }

    func refreshingTimestamp(_ date: Date = Date()) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            kind: kind,
            createdAt: date,
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
}
