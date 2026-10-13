import Foundation
import AppKit
import QuickNotesCore

enum ModelSmokeFailure: Error {
    case failed(String)
}

@main
enum ModelSmoke {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickNotesModelSmoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.json")
        let suiteName = "QuickNotesModelSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = NotesRepository(fileURL: url)
        let store = NotesStore(repository: repository, defaults: defaults)
        guard store.selectedNoteID != nil else {
            throw ModelSmokeFailure.failed("Initial note was not selected")
        }

        store.updateSelectedText("Autosaved note\nLast character: Z")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        var loaded = try repository.load()
        guard loaded.first?.text.hasSuffix("Z") == true else {
            throw ModelSmokeFailure.failed("Debounced autosave lost the final character")
        }

        store.updateSelectedText("Flushed immediately")
        store.flush()
        loaded = try repository.load()
        guard loaded.first?.text == "Flushed immediately" else {
            throw ModelSmokeFailure.failed("Explicit flush did not persist the current note")
        }
        let savedAt = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        if let selectedID = store.selectedNoteID { store.select(selectedID) }
        let afterSelection = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        guard savedAt == afterSelection else {
            throw ModelSmokeFailure.failed("Selecting an unchanged note rewrote the notes file")
        }

        _ = store.createNote()
        store.updateSelectedText("Second note")
        store.flush()
        loaded = try repository.load()
        guard loaded.count == 2 else {
            throw ModelSmokeFailure.failed("Creating a second note did not persist both notes")
        }
        try testRecentNotesMenu(store: store)
        guard store.searchResults(for: "second").count == 1 else {
            throw ModelSmokeFailure.failed("Search did not find the second note")
        }

        let richText = Data("{\\rtf1 Rich text}".utf8)
        store.updateSelectedContent(text: "Rich text", richTextData: richText)
        store.flush()
        loaded = try repository.load()
        guard loaded.first(where: { $0.id == store.selectedNoteID })?.richTextData == richText else {
            throw ModelSmokeFailure.failed("Rich text data was not persisted")
        }

        guard let deletedID = store.selectedNoteID,
              let deletion = store.deleteRecording(deletedID) else {
            throw ModelSmokeFailure.failed("Selected note could not be deleted")
        }
        guard !store.notes.contains(where: { $0.id == deletedID }) else {
            throw ModelSmokeFailure.failed("Deleted note remained in the store")
        }
        guard store.deletedNotes.contains(where: { $0.id == deletedID }) else {
            throw ModelSmokeFailure.failed("Deleted note was not moved to Trash")
        }
        store.restoreDeletion(deletion)
        guard store.notes.contains(where: { $0.id == deletedID }),
              store.selectedNoteID == deletedID,
              !store.deletedNotes.contains(where: { $0.id == deletedID }) else {
            throw ModelSmokeFailure.failed("Deleted note could not be restored")
        }

        let singleDirectory = directory.appendingPathComponent("single", isDirectory: true)
        let singleStore = NotesStore(
            repository: NotesRepository(fileURL: singleDirectory.appendingPathComponent("notes.json")),
            defaults: defaults
        )
        guard let singleID = singleStore.selectedNoteID,
              let singleDeletion = singleStore.deleteRecording(singleID),
              singleStore.notes.count == 1,
              singleStore.notes.first?.id != singleID else {
            throw ModelSmokeFailure.failed("Deleting the final note did not create a replacement")
        }
        singleStore.restoreDeletion(singleDeletion)
        guard singleStore.notes.count == 1,
              singleStore.notes.first?.id == singleID,
              singleStore.selectedNoteID == singleID else {
            throw ModelSmokeFailure.failed("Undoing deletion of the final note left a replacement behind")
        }
        let countBeforeDuplicate = store.notes.count
        guard let duplicateID = store.duplicate(deletedID),
              duplicateID != deletedID,
              store.notes.count == countBeforeDuplicate + 1 else {
            throw ModelSmokeFailure.failed("Note duplication failed")
        }

        guard store.delete(deletedID),
              store.restoreDeletedNote(deletedID),
              store.notes.contains(where: { $0.id == deletedID }) else {
            throw ModelSmokeFailure.failed("Trash restore did not recover the note")
        }
        guard store.delete(deletedID), store.emptyTrash(), store.deletedNotes.isEmpty else {
            throw ModelSmokeFailure.failed("Empty Trash did not clear deleted notes")
        }
        store.flush()
        let reopened = NotesStore(repository: repository, defaults: defaults)
        guard reopened.deletedNotes.isEmpty,
              !reopened.notes.contains(where: { $0.id == deletedID }) else {
            throw ModelSmokeFailure.failed("Trash state did not persist after reopening")
        }

        let corruptURL = directory.appendingPathComponent("corrupt.json")
        let corruptData = Data("{broken".utf8)
        try corruptData.write(to: corruptURL)
        let blockedStore = NotesStore(
            repository: NotesRepository(fileURL: corruptURL),
            defaults: defaults
        )
        guard blockedStore.storageError != nil else {
            throw ModelSmokeFailure.failed("Corrupt storage did not surface an error")
        }
        blockedStore.updateSelectedText("Do not overwrite the original")
        blockedStore.flush()
        guard try Data(contentsOf: corruptURL) == corruptData else {
            throw ModelSmokeFailure.failed("Corrupt storage was overwritten")
        }

        let shortcutSuiteName = "QuickNotesShortcutSmoke.\(UUID().uuidString)"
        let shortcutDefaults = UserDefaults(suiteName: shortcutSuiteName)!
        defer { shortcutDefaults.removePersistentDomain(forName: shortcutSuiteName) }
        let fnOnly = ShortcutDefinition(
            keyCode: 45,
            carbonModifiers: 131072,
            keyLabel: "N"
        )
        shortcutDefaults.set(try JSONEncoder().encode(fnOnly), forKey: "shortcut")
        let preferences = AppPreferences(defaults: shortcutDefaults)
        guard preferences.hapticFeedbackEnabled else {
            throw ModelSmokeFailure.failed("Haptic feedback should be enabled by default")
        }
        guard abs(preferences.customAccentBrightness - 0.96) < 0.001 else {
            throw ModelSmokeFailure.failed("Custom color shade changed the existing default color")
        }
        guard preferences.shortcut == .defaultShortcut else {
            throw ModelSmokeFailure.failed("Saved fn-only shortcut did not migrate to Control + N")
        }
        guard let migratedData = shortcutDefaults.data(forKey: "shortcut"),
              try JSONDecoder().decode(ShortcutDefinition.self, from: migratedData) == .defaultShortcut else {
            throw ModelSmokeFailure.failed("Migrated Control + N shortcut was not persisted")
        }

        let customShortcut = ShortcutDefinition(
            keyCode: 40,
            carbonModifiers: 2048,
            keyLabel: "K"
        )
        preferences.setShortcut(customShortcut)
        let reloadedPreferences = AppPreferences(defaults: shortcutDefaults)
        guard reloadedPreferences.shortcut == customShortcut else {
            throw ModelSmokeFailure.failed("A valid custom shortcut was not preserved")
        }
        guard preferences.newNoteShortcutEnabled,
              preferences.newNoteShortcut == .defaultNewNoteShortcut else {
            throw ModelSmokeFailure.failed("New Note shortcut defaults were incorrect")
        }
        preferences.newNoteShortcutEnabled = false
        preferences.setNewNoteShortcut(customShortcut)
        let reloadedNewNotePreferences = AppPreferences(defaults: shortcutDefaults)
        guard !reloadedNewNotePreferences.newNoteShortcutEnabled,
              reloadedNewNotePreferences.newNoteShortcut == customShortcut else {
            throw ModelSmokeFailure.failed("New Note shortcut settings did not persist")
        }

        preferences.windowTransparency = 0.87
        preferences.showFormattingToolbarWhenWide = false
        preferences.hapticFeedbackEnabled = false
        preferences.customAccentBrightness = 0.58
        preferences.fontSizeControlStyle = .classic
        preferences.defaultPinned = true
        let firstToolbarAction = preferences.toolbarOrder[0]
        preferences.moveToolbarAction(firstToolbarAction, offset: 1)
        let appearancePreferences = AppPreferences(defaults: shortcutDefaults)
        guard abs(appearancePreferences.windowTransparency - 0.87) < 0.001,
              appearancePreferences.showFormattingToolbarWhenWide == false,
              !appearancePreferences.hapticFeedbackEnabled,
              abs(appearancePreferences.customAccentBrightness - 0.58) < 0.001,
              appearancePreferences.fontSizeControlStyle == .classic,
              appearancePreferences.defaultPinned,
              appearancePreferences.toolbarOrder[1] == firstToolbarAction else {
            throw ModelSmokeFailure.failed("Appearance or toolbar customization was not persisted")
        }

        shortcutDefaults.set(2.0, forKey: "windowTransparency")
        let clampedPreferences = AppPreferences(defaults: shortcutDefaults)
        guard clampedPreferences.windowTransparency == 1 else {
            throw ModelSmokeFailure.failed("Transparency outside the 0 to 100 percent range was not clamped")
        }

        print("Notes model and shortcut migration smoke tests passed")
    }

    @MainActor
    private static func testRecentNotesMenu(store: NotesStore) throws {
        let controller = MenuBarController(store: store)
        guard let menu = Mirror(reflecting: controller).children.first(where: { $0.label == "menu" })?.value as? NSMenu else {
            throw ModelSmokeFailure.failed("Recent Notes menu was not available")
        }
        var requestedDeletion: UUID?
        var selectedNote: UUID?
        controller.onRequestDeleteNote = { requestedDeletion = $0 }
        controller.onSelectNote = { selectedNote = $0 }
        controller.menuWillOpen(menu)
        guard let first = store.sortedNotes.first,
              let recent = menu.items.first(where: { $0.title == "Recent Notes" })?.submenu,
              let actions = recent.items.first?.submenu,
              let open = actions.items.first(where: { $0.title == "Open Note" }),
              let delete = actions.items.first(where: { $0.title == "Delete Note…" }),
              let openAction = open.action, let deleteAction = delete.action else {
            throw ModelSmokeFailure.failed("A recent note did not expose Open and Delete actions")
        }
        let originalCount = store.notes.count
        NSApplication.shared.sendAction(openAction, to: open.target, from: open)
        NSApplication.shared.sendAction(deleteAction, to: delete.target, from: delete)
        guard selectedNote == first.id, requestedDeletion == nil,
              store.notes.count == originalCount else {
            throw ModelSmokeFailure.failed("Recent Notes menu opened deletion before the menu closed")
        }
        controller.menuDidClose(menu)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        guard requestedDeletion == first.id, store.notes.count == originalCount else {
            throw ModelSmokeFailure.failed("Recent Notes menu targeted the wrong note or deleted without confirmation")
        }
        guard !controller.isTrackingMenu else {
            throw ModelSmokeFailure.failed("Recent Notes menu remained in tracking state")
        }
    }
}
