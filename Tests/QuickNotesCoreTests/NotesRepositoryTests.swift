import Foundation
import XCTest
@testable import QuickNotesCore

final class NotesRepositoryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testMissingFileLoadsAsEmptyCollection() throws {
        let repository = NotesRepository(
            fileURL: temporaryDirectory.appendingPathComponent("missing/notes.json")
        )

        XCTAssertEqual(try repository.load(), [])
    }

    func testSaveAndLoadRoundTripPreservesNotes() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("nested/notes.json")
        let repository = NotesRepository(fileURL: fileURL)
        let notes = [
            QuickNote(
                id: UUID(uuidString: "B44430DE-4AD9-4EB3-AB7A-8CBB1F39ABAD")!,
                text: "First note\nwith two lines",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_100)
            ),
            QuickNote(
                id: UUID(uuidString: "F8E23A20-9A07-4456-876B-4C7DA41B8295")!,
                text: "Unicode: café 📝",
                createdAt: Date(timeIntervalSince1970: 1_700_001_000),
                modifiedAt: Date(timeIntervalSince1970: 1_700_001_200)
            )
        ]

        try repository.save(notes)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try repository.load(), notes)
    }

    func testSaveAndLoadRoundTripPreservesSubsecondDates() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.json")
        let repository = NotesRepository(fileURL: fileURL)
        let note = QuickNote(
            id: UUID(uuidString: "9F90C4D1-E8EF-4F86-B4C0-5D56855727BB")!,
            text: "Subsecond precision",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.123456),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100.654321)
        )

        try repository.save([note])

        XCTAssertEqual(try repository.load(), [note])
    }

    func testLoadSupportsLegacyISO8601Dates() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.json")
        let note = QuickNote(
            id: UUID(uuidString: "2BC4994E-8068-438E-8A1C-B6D7067D55A5")!,
            text: "Legacy dates",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(NotesDocument(notes: [note])).write(to: fileURL)
        let repository = NotesRepository(fileURL: fileURL)

        XCTAssertEqual(try repository.load(), [note])
    }

    func testLoadRejectsDocumentFromFutureVersion() throws {
        let fileURL = temporaryDirectory.appendingPathComponent("notes.json")
        let futureVersion = NotesDocument.currentVersion + 1
        let document = NotesDocument(version: futureVersion, notes: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: fileURL)
        let repository = NotesRepository(fileURL: fileURL)

        XCTAssertThrowsError(try repository.load()) { error in
            guard case NotesRepositoryError.unsupportedVersion(let version) = error else {
                return XCTFail("Expected unsupportedVersion, received \(error)")
            }
            XCTAssertEqual(version, futureVersion)
        }
    }
}
