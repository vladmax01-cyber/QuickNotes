import XCTest
@testable import QuickNotesCore

final class QuickNoteTests: XCTestCase {
    func testTitleUsesFirstNonemptyTrimmedLine() {
        let note = QuickNote(text: "  \n\t  \n  First useful line  \nSecond line")

        XCTAssertEqual(note.title, "First useful line")
    }

    func testTitleFallsBackForWhitespaceOnlyText() {
        let note = QuickNote(text: " \n\t\n ")

        XCTAssertEqual(note.title, "Untitled Note")
    }

    func testTitleAndPreviewOmitListMarkers() {
        let note = QuickNote(text: "○ Café 📝 — Ελληνικά\n◉ 日本語\n2. שלום")
        XCTAssertEqual(note.title, "Café 📝 — Ελληνικά")
        XCTAssertEqual(note.preview, "日本語 שלום")
    }

    func testTitleIsLimitedToSeventyTwoCharacters() {
        let note = QuickNote(text: String(repeating: "a", count: 80))

        XCTAssertEqual(note.title, String(repeating: "a", count: 72))
    }

    func testPreviewCollapsesWhitespace() {
        let note = QuickNote(text: "First\n\nsecond\tthird   fourth")

        XCTAssertEqual(note.preview, "second third fourth")
    }

    func testPreviewFallsBackForWhitespaceOnlyText() {
        let note = QuickNote(text: " \n\t\n ")

        XCTAssertEqual(note.preview, "Empty note")
    }

    func testSingleLineNoteDoesNotRepeatTitleInPreview() {
        let note = QuickNote(text: "Quick Note")

        XCTAssertEqual(note.preview, "")
    }

    func testPreviewIsLimitedToOneHundredTenCharacters() {
        let note = QuickNote(text: "Title\n" + String(repeating: "b", count: 120))

        XCTAssertEqual(note.preview, String(repeating: "b", count: 110))
    }

    func testSearchIsCaseInsensitiveAndMatchesAcrossFullText() {
        let note = QuickNote(text: "CoursePoint reading\nMedication SAFETY")

        XCTAssertTrue(note.matches("coursepoint"))
        XCTAssertTrue(note.matches("safety"))
        XCTAssertFalse(note.matches("Blackboard"))
    }

    func testBlankSearchMatchesEveryNote() {
        let note = QuickNote(text: "Any content")

        XCTAssertTrue(note.matches(""))
        XCTAssertTrue(note.matches("  \n\t"))
    }
}
