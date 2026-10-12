import XCTest
@testable import QuickNotesCore

final class ShortcutDefinitionTests: XCTestCase {
    func testDefaultShortcutUsesControlN() {
        let shortcut = ShortcutDefinition.defaultShortcut

        XCTAssertEqual(shortcut.keyCode, 45)
        XCTAssertEqual(shortcut.carbonModifiers, 4096)
        XCTAssertEqual(shortcut.keyLabel, "N")
        XCTAssertEqual(shortcut.displayString, "Control + N")
        XCTAssertTrue(shortcut.hasPrimaryModifier)
    }

    func testDisplayStringUsesStableMacModifierOrder() {
        let shortcut = ShortcutDefinition(
            keyCode: 40,
            carbonModifiers: 4096 | 2048 | 512 | 256,
            keyLabel: "K"
        )

        XCTAssertEqual(shortcut.displayString, "Control + Option + Shift + Command + K")
    }

    func testShiftAloneIsNotAPrimaryModifier() {
        let shortcut = ShortcutDefinition(
            keyCode: 40,
            carbonModifiers: 512,
            keyLabel: "K"
        )

        XCTAssertFalse(shortcut.hasPrimaryModifier)
    }

    func testCommandCountsAsAPrimaryModifier() {
        let shortcut = ShortcutDefinition(
            keyCode: 40,
            carbonModifiers: 256,
            keyLabel: "K"
        )

        XCTAssertTrue(shortcut.hasPrimaryModifier)
    }

    func testFunctionAloneIsNotAPrimaryModifier() {
        let shortcut = ShortcutDefinition(
            keyCode: 45,
            carbonModifiers: 131072,
            keyLabel: "N"
        )

        XCTAssertEqual(shortcut.displayString, "fn + N")
        XCTAssertFalse(shortcut.hasPrimaryModifier)
    }

    func testFunctionCanBeAddedToAStandardModifier() {
        let shortcut = ShortcutDefinition(
            keyCode: 45,
            carbonModifiers: 131072 | 4096,
            keyLabel: "N"
        )

        XCTAssertEqual(shortcut.displayString, "fn + Control + N")
        XCTAssertTrue(shortcut.hasPrimaryModifier)
    }
}
