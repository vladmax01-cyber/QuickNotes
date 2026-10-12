import Foundation

enum SmokeFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
enum CoreSmoke {
    static func main() throws {
        try testNoteDerivation()
        try testRepositoryRoundTrip()
        try testUnsupportedVersion()
        try testTimestampLabels()
        try testWindowPlacement()
        try testShortcuts()
        print("Core smoke tests passed")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw SmokeFailure.failed(message) }
    }

    private static func testNoteDerivation() throws {
        let note = QuickNote(
            text: "  \nFirst line\nSecond line with café and 📝",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try require(note.title == "First line", "First nonempty line was not used as the title")
        try require(note.preview == "Second line with café and 📝", "Preview repeated the title")
        try require(note.matches("CAFÉ"), "Localized case-insensitive search failed")
        try require(QuickNote().title == "Untitled Note", "Empty title fallback failed")
    }

    private static func testRepositoryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickNotesSmoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = NotesRepository(fileURL: directory.appendingPathComponent("nested/notes.json"))
        let note = QuickNote(
            text: "Unicode café 📝\nSecond line",
            richTextData: Data("{\\rtf1 Smoke}".utf8),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.123456),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_010.654321)
        )
        try repository.save([note])
        let loaded = try repository.load()
        try require(loaded == [note], "Repository round trip changed note data")
    }

    private static func testTimestampLabels() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try require(
            NoteTimestampFormatter.relativeLabel(for: now.addingTimeInterval(-15), relativeTo: now) == "Just now",
            "Recent timestamp was not shown as Just now"
        )
        try require(
            NoteTimestampFormatter.relativeLabel(for: now.addingTimeInterval(-120), relativeTo: now) == "2 min ago",
            "Minute timestamp was formatted incorrectly"
        )
        try require(
            NoteTimestampFormatter.relativeLabel(for: now.addingTimeInterval(-3_600), relativeTo: now) == "1 hr ago",
            "Hour timestamp was formatted incorrectly"
        )
    }

    private static func testUnsupportedVersion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickNotesFuture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("notes.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(NotesDocument(version: 99, notes: [])).write(to: url)
        do {
            _ = try NotesRepository(fileURL: url).load()
            throw SmokeFailure.failed("Future storage version was accepted")
        } catch NotesRepositoryError.unsupportedVersion(let version) {
            try require(version == 99, "Future storage version was reported incorrectly")
        }
    }

    private static func testWindowPlacement() throws {
        let visible = CGRect(x: -1200, y: 40, width: 1200, height: 800)
        let initial = WindowPlacement.defaultFrame(in: visible, size: CGSize(width: 460, height: 420))
        try require(initial.minX == -1172, "Default leading inset was incorrect")
        try require(initial.maxY == 832, "Default top inset was incorrect")
        let full = CGRect(x: -1200, y: 0, width: 1200, height: 880)
        let movementFrame = WindowPlacement.movementFrame(visibleFrame: visible, fullFrame: full)
        try require(
            movementFrame.maxY == visible.maxY + 30,
            "Menu bar overlap was not added to the movement frame"
        )
        let nearMenuBar = WindowPlacement.clamped(
            CGRect(x: -900, y: 700, width: 460, height: 420),
            to: movementFrame
        )
        try require(nearMenuBar.maxY == 870, "Window did not reach into the menu bar boundary")
        let clamped = WindowPlacement.clamped(
            CGRect(x: -1400, y: -100, width: 1400, height: 1000),
            to: visible
        )
        try require(visible.contains(clamped), "Oversized frame was not clamped to the visible screen")
    }

    private static func testShortcuts() throws {
        try require(
            ShortcutDefinition.defaultShortcut.displayString == "Control + N",
            "Default shortcut is not Control + N"
        )
        let fnShortcut = ShortcutDefinition(keyCode: 45, carbonModifiers: 131072, keyLabel: "N")
        try require(fnShortcut.displayString == "fn + N", "fn modifier was not displayed")
        try require(!fnShortcut.hasPrimaryModifier, "fn-only shortcut was accepted")
        let controlFnShortcut = ShortcutDefinition(
            keyCode: 45,
            carbonModifiers: 4096 | 131072,
            keyLabel: "N"
        )
        try require(controlFnShortcut.hasPrimaryModifier, "Control + fn shortcut was rejected")
    }
}
