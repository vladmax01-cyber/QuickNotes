import Foundation

public struct QuickNote: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var richTextData: Data?
    public let createdAt: Date
    public var modifiedAt: Date
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        text: String = "",
        richTextData: Data? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.richTextData = richTextData
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, richTextData, createdAt, modifiedAt, isPinned
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        richTextData = try values.decodeIfPresent(Data.self, forKey: .richTextData)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public var title: String {
        let firstLine = text.replacingOccurrences(of: "\u{FFFC}", with: "[Image]")
            .components(separatedBy: .newlines)
            .map(Self.displayLine)
            .first { !$0.isEmpty }
        return firstLine.map { String($0.prefix(72)) } ?? "Untitled Note"
    }

    public var preview: String {
        let lines = text.replacingOccurrences(of: "\u{FFFC}", with: "[Image]")
            .components(separatedBy: .newlines)
            .map(Self.displayLine)
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "Empty note" }
        let compact = lines.dropFirst()
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(compact.prefix(110))
    }

    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || text.localizedCaseInsensitiveContains(trimmed)
    }

    private static func displayLine(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["○ ", "◉ ", "☐ ", "☑ ", "• ", "- ", "> "] where line.hasPrefix(prefix) {
            line.removeFirst(prefix.count)
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let digits = line.prefix(while: { $0.isNumber })
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            line.removeFirst(digits.count + 2)
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
