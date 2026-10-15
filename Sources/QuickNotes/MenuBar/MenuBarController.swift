import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: NotesStore
    private let updateChecker: UpdateChecker
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var pendingDeleteID: UUID?

    var isTrackingMenu = false
    var isQuickNoteVisible: () -> Bool = { false }
    var onToggleQuickNote: () -> Void = {}
    var onNewNote: () -> Void = {}
    var onSelectNote: (UUID) -> Void = { _ in }
    var onRequestDeleteNote: (UUID) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    init(store: NotesStore, updateChecker: UpdateChecker) {
        self.store = store
        self.updateChecker = updateChecker
        super.init()
        menu.delegate = self
    }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                let image = NSImage(
                    systemSymbolName: "note.text",
                    accessibilityDescription: "Quick Notes"
                )
                image?.isTemplate = true
                button.image = image
                button.toolTip = "Quick Notes"
            }
            item.menu = menu
            statusItem = item
        } else if !visible, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func refresh() {
        guard !isTrackingMenu else { return }
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isTrackingMenu = true
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isTrackingMenu = false
        if let id = pendingDeleteID {
            pendingDeleteID = nil
            DispatchQueue.main.async { [weak self] in
                self?.onRequestDeleteNote(id)
            }
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let toggleTitle = isQuickNoteVisible() ? "Hide Quick Note" : "Show Quick Note"
        menu.addItem(item(toggleTitle, action: #selector(toggleQuickNote)))
        let newItem = item("New Note", action: #selector(createNote))
        newItem.keyEquivalent = "n"
        newItem.keyEquivalentModifierMask = [.command]
        menu.addItem(newItem)

        let recentMenu = NSMenu(title: "Recent Notes")
        for note in store.sortedNotes.prefix(7) {
            let noteItem = NSMenuItem(title: note.title, action: nil, keyEquivalent: "")
            noteItem.toolTip = note.preview.isEmpty ? nil : note.preview
            let actions = NSMenu(title: note.title)
            let open = item("Open Note", action: #selector(selectRecentNote(_:)))
            open.representedObject = note.id.uuidString
            actions.addItem(open)
            let delete = item("Move to Trash", action: #selector(requestDeleteRecentNote(_:)))
            delete.representedObject = note.id.uuidString
            actions.addItem(delete)
            noteItem.submenu = actions
            recentMenu.addItem(noteItem)
        }
        if recentMenu.items.isEmpty {
            let empty = NSMenuItem(title: "No Notes", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentMenu.addItem(empty)
        }
        let recentItem = NSMenuItem(title: "Recent Notes", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        if let release = updateChecker.availableRelease {
            let update = item("Quick Notes \(release.version) Available…", action: #selector(openUpdate))
            update.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(update)
        }
        let settings = item("Settings…", action: #selector(openSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(item("Quit Quick Notes", action: #selector(quit)))
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleQuickNote() { onToggleQuickNote() }
    @objc private func createNote() { onNewNote() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openUpdate() { updateChecker.openRelease() }
    @objc private func quit() { onQuit() }

    @objc private func selectRecentNote(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value) else { return }
        onSelectNote(id)
    }

    @objc private func requestDeleteRecentNote(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value) else { return }
        if isTrackingMenu {
            pendingDeleteID = id
        } else {
            onRequestDeleteNote(id)
        }
    }
}
