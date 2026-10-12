import Foundation

public struct NotesDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var notes: [QuickNote]

    public init(version: Int = currentVersion, notes: [QuickNote]) {
        self.version = version
        self.notes = notes
    }
}

public enum NotesRepositoryError: LocalizedError {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This notes file was created by a newer version of Quick Notes (version \(version))."
        }
    }
}

public struct NotesRepository: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [QuickNote] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let document = try Self.decoderForStoredDocument().decode(NotesDocument.self, from: data)
        guard document.version <= NotesDocument.currentVersion else {
            throw NotesRepositoryError.unsupportedVersion(document.version)
        }
        return document.notes
    }

    public func save(_ notes: [QuickNote]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.storageString(for: date))
        }
        let data = try encoder.encode(NotesDocument(notes: notes))
        try data.write(to: fileURL, options: .atomic)
    }

    public static func decoderForStoredDocument() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date string."
            )
        }
        return decoder
    }

    private static func storageString(for date: Date) -> String {
        var wholeSeconds = floor(date.timeIntervalSince1970)
        var nanoseconds = Int(
            ((date.timeIntervalSince1970 - wholeSeconds) * 1_000_000_000).rounded()
        )

        if nanoseconds == 1_000_000_000 {
            wholeSeconds += 1
            nanoseconds = 0
        }

        let wholeSecondDate = Date(timeIntervalSince1970: wholeSeconds)
        let wholeSecondString = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
            .format(wholeSecondDate)
        let prefix = wholeSecondString.dropLast()
        return "\(prefix).\(String(format: "%09d", nanoseconds))Z"
    }
}
