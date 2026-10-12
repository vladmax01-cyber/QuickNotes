import AppKit
import QuickNotesCore

private struct LocalKeyEvent: Sendable {
    let keyCode: UInt16
    let modifierRawValue: UInt
    let characters: String
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preferences: AppPreferences!
    private var viewModel: AppViewModel!
    private var store: NotesStore!
    private var editorController: RichTextEditorController!
    private var launchAtLogin: LaunchAtLoginService!
    private var hotKeyService: GlobalHotKeyService!
    private var panelController: QuickNotePanelController!
    private var settingsController: SettingsWindowController!
    private var menuBarController: MenuBarController!
    private var registeredShortcut: ShortcutDefinition?
    private var localEventMonitor: Any?
    private var preferencesObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var deletedNoteUndoStack: [NoteDeletionRecord] = []
    private var deletedNoteRedoStack: [NoteDeletionRecord] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = appDefaults()
        preferences = AppPreferences(defaults: defaults)
        viewModel = AppViewModel(isPinned: preferences.defaultPinned)
        launchAtLogin = LaunchAtLoginService()
        store = NotesStore(repository: NotesRepository(fileURL: notesFileURL()), defaults: defaults)
        editorController = RichTextEditorController()
        hotKeyService = GlobalHotKeyService()

        installMainMenu()
        configureApplicationIcon()

        panelController = QuickNotePanelController(
            store: store,
            preferences: preferences,
            viewModel: viewModel,
            editorController: editorController,
            defaults: defaults,
            onNewNote: { [weak self] in self?.createNewNote() },
            onDuplicateNote: { [weak self] id in self?.duplicateNote(id) },
            onDeleteNote: { [weak self] id in self?.deleteNote(id) },
            onTogglePin: { [weak self] in self?.togglePin() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { [weak self] in self?.quitApplication() }
        )

        settingsController = SettingsWindowController(
            preferences: preferences,
            launchAtLogin: launchAtLogin,
            viewModel: viewModel,
            onShortcutRecordingChanged: { [weak self] isRecording in
                self?.setShortcutRecording(isRecording)
            },
            onShortcutRecorded: { [weak self] shortcut in
                self?.applyShortcut(shortcut, persist: true)
            }
        )

        menuBarController = MenuBarController(store: store)
        menuBarController.isQuickNoteVisible = { [weak self] in
            self?.panelController.isPresented ?? false
        }
        menuBarController.onToggleQuickNote = { [weak self] in self?.toggleQuickNote() }
        menuBarController.onNewNote = { [weak self] in self?.createNewNote() }
        menuBarController.onSelectNote = { [weak self] id in self?.show(noteID: id) }
        menuBarController.onRequestDeleteNote = { [weak self] id in self?.requestDeleteNote(id) }
        menuBarController.onOpenSettings = { [weak self] in self?.openSettings() }
        menuBarController.onQuit = { NSApp.terminate(nil) }

        panelController.shouldSuppressFocusLoss = { [weak self] in
            guard let self else { return false }
            return self.settingsController.isPresented
                || self.menuBarController.isTrackingMenu
                || self.viewModel.pendingDeletionID != nil
        }

        observeChanges()
        applyPreferences()
        applyShortcut(preferences.shortcut, persist: false)
        installLocalKeyboardHandling()

        if preferences.openAtStartup {
            panelController.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flush()
        hotKeyService?.unregister()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }

    @objc func toggleQuickNote() {
        panelController.toggle()
        menuBarController.refresh()
    }

    @objc func createNewNote() {
        store.createNote()
        panelController.show()
        viewModel.focusEditor()
        menuBarController.refresh()
    }

    @objc func openSearch() {
        if !panelController.isPresented {
            panelController.show()
        }
        viewModel.showSearch()
    }

    @objc func openSettings() {
        if panelController.isPresented {
            panelController.hide(restoreFocus: false)
        }
        launchAtLogin.refresh()
        settingsController.show()
    }

    @objc func closeQuickNote() {
        panelController.hide(restoreFocus: true)
    }

    @objc func toggleSidebar() {
        viewModel.isSidebarVisible.toggle()
    }

    @objc func applyTitleStyle() { editorController.apply(.title) }
    @objc func applyHeadingStyle() { editorController.apply(.heading) }
    @objc func applySubheadingStyle() { editorController.apply(.subheading) }
    @objc func applyBodyStyle() { editorController.apply(.body) }
    @objc func applyMonostyledStyle() { editorController.apply(.monostyled) }
    @objc func toggleBold() { editorController.toggleBold() }
    @objc func toggleItalic() { editorController.toggleItalic() }
    @objc func toggleUnderline() { editorController.toggleUnderline() }
    @objc func toggleStrikethrough() { editorController.toggleStrikethrough() }
    @objc func toggleHighlight() { editorController.toggleHighlight() }
    @objc func applyBulletedList() { editorController.applyList(.bulleted) }
    @objc func applyDashedList() { editorController.applyList(.dashed) }
    @objc func applyNumberedList() { editorController.applyList(.numbered) }
    @objc func applyChecklist() { editorController.applyList(.checklist) }
    @objc func applyBlockQuote() { editorController.applyList(.blockQuote) }
    @objc func alignLeft() { editorController.setAlignment(.left) }
    @objc func alignCenter() { editorController.setAlignment(.center) }
    @objc func alignRight() { editorController.setAlignment(.right) }
    @objc func alignJustified() { editorController.setAlignment(.justified) }
    @objc func increaseFontSize() { editorController.changeFontSize(by: 1) }
    @objc func decreaseFontSize() { editorController.changeFontSize(by: -1) }
    @objc func clearFormatting() { editorController.clearFormatting() }

    @objc func undoAction(_ sender: Any?) {
        _ = performUndoOrRedo(redo: false)
    }

    @objc func redoAction(_ sender: Any?) {
        _ = performUndoOrRedo(redo: true)
    }

    @objc func quitApplication() {
        NSApp.terminate(nil)
    }

    private func duplicateNote(_ id: UUID) {
        guard store.duplicate(id) != nil else { return }
        viewModel.focusEditor()
        menuBarController.refresh()
    }

    private func togglePin() {
        panelController.setPinned(!viewModel.isPinned)
    }

    private func show(noteID: UUID) {
        store.select(noteID)
        panelController.show()
        viewModel.focusEditor()
    }

    private func requestDeleteNote(_ id: UUID) {
        guard store.notes.contains(where: { $0.id == id }) else { return }
        show(noteID: id)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.store.notes.contains(where: { $0.id == id }) else { return }
            self.viewModel.requestDeletion(of: id)
        }
    }

    private func applyShortcut(_ shortcut: ShortcutDefinition, persist: Bool) {
        let prior = registeredShortcut ?? preferences.shortcut
        do {
            try hotKeyService.register(shortcut) { [weak self] in
                self?.toggleQuickNote()
            }
            registeredShortcut = shortcut
            viewModel.shortcutError = nil
            if persist {
                preferences.setShortcut(shortcut)
            }
        } catch {
            viewModel.shortcutError = error.localizedDescription
            if shortcut != prior {
                try? hotKeyService.register(prior) { [weak self] in
                    self?.toggleQuickNote()
                }
                registeredShortcut = prior
            }
            if !preferences.showMenuBarIcon && !preferences.showDockIcon {
                preferences.showMenuBarIcon = true
            }
            settingsController?.show()
        }
    }

    private func setShortcutRecording(_ isRecording: Bool) {
        if isRecording {
            hotKeyService.unregister()
        } else if let registeredShortcut {
            applyShortcut(registeredShortcut, persist: false)
        }
    }

    private func observeChanges() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: .quickNotesPreferencesChanged,
            object: preferences,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyPreferences()
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelController.repositionIfNeeded()
            }
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelController.activeSpaceDidChange()
            }
        }
    }

    private func applyPreferences() {
        switch preferences.appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        _ = NSApp.setActivationPolicy(preferences.showDockIcon ? .regular : .accessory)
        menuBarController?.setVisible(preferences.showMenuBarIcon)
    }

    private func installLocalKeyboardHandling() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyEvent = LocalKeyEvent(
                keyCode: event.keyCode,
                modifierRawValue: event.modifierFlags.rawValue,
                characters: event.charactersIgnoringModifiers?.lowercased() ?? ""
            )
            let handled = MainActor.assumeIsolated {
                self.handleLocalKeyDown(keyEvent)
            }
            return handled ? nil : event
        }
    }

    private func handleLocalKeyDown(_ event: LocalKeyEvent) -> Bool {
        if settingsController.isRecordingShortcut {
            return false
        }
        let modifiers = NSEvent.ModifierFlags(rawValue: event.modifierRawValue)
            .intersection(.deviceIndependentFlagsMask)
        let characters = event.characters

        if event.keyCode == 53, panelController.isPresented {
            if viewModel.isSearchVisible {
                viewModel.closeSearch()
            } else {
                closeQuickNote()
            }
            return true
        }

        if modifiers.contains(.command) {
            if characters == "z", modifiers == [.command],
               settingsController.window?.isKeyWindow != true {
                return performUndoOrRedo(redo: false)
            }
            if characters == "z", modifiers == [.command, .shift],
               settingsController.window?.isKeyWindow != true {
                return performUndoOrRedo(redo: true)
            }
            switch characters {
            case "n":
                createNewNote()
                return true
            case "f", "k":
                openSearch()
                return true
            case ",":
                openSettings()
                return true
            case "w":
                if settingsController.window?.isKeyWindow == true {
                    settingsController.window?.performClose(nil)
                } else if panelController.isPresented {
                    closeQuickNote()
                }
                return true
            case "s" where modifiers.contains(.shift):
                toggleSidebar()
                return true
            default:
                break
            }
        }

        guard panelController.isPresented, viewModel.isSearchVisible else { return false }
        let results = store.searchResults(for: viewModel.searchQuery)
        switch event.keyCode {
        case 125:
            if !results.isEmpty {
                viewModel.searchSelection = min(viewModel.searchSelection + 1, results.count - 1)
            }
            return true
        case 126:
            if !results.isEmpty {
                viewModel.searchSelection = max(viewModel.searchSelection - 1, 0)
            }
            return true
        case 36, 76:
            guard results.indices.contains(viewModel.searchSelection) else { return true }
            store.select(results[viewModel.searchSelection].id)
            viewModel.closeSearch()
            return true
        default:
            return false
        }
    }

    private func configureApplicationIcon() {
        if let url = Bundle.main.url(forResource: "QuickNotes", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    private func notesFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["QUICK_NOTES_DATA_DIRECTORY"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("notes.json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("Quick Notes", isDirectory: true)
            .appendingPathComponent("notes.json")
    }

    private func appDefaults() -> UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["QUICK_NOTES_DEFAULTS_SUITE"],
           !suite.isEmpty,
           let isolatedDefaults = UserDefaults(suiteName: suite) {
            return isolatedDefaults
        }
        return .standard
    }

    private func isSidebarFocused() -> Bool {
        var responder = panelController.window?.firstResponder
        for _ in 0..<12 {
            guard let current = responder else { return false }
            if current is NSTextView { return false }
            if current is NSTableView { return true }
            responder = current.nextResponder
        }
        return false
    }

    private func deleteNote(_ id: UUID) {
        guard let record = store.deleteRecording(id) else { return }
        deletedNoteUndoStack.append(record)
        deletedNoteRedoStack.removeAll()
        menuBarController.refresh()
    }

    private func performUndoOrRedo(redo: Bool) -> Bool {
        guard panelController.isPresented,
              let window = panelController.window else { return false }

        let activeEditor = window.firstResponder as? NSTextView
            ?? (isSidebarFocused() ? nil : editorController.textView)
        if let textUndoManager = activeEditor?.undoManager {
            if redo, textUndoManager.canRedo {
                textUndoManager.redo()
                return true
            }
            if !redo, textUndoManager.canUndo {
                textUndoManager.undo()
                return true
            }
        }

        if performDeletedNoteHistory(redo: redo) {
            return true
        }

        guard let undoManager = window.undoManager else { return false }
        if redo {
            guard undoManager.canRedo else { return false }
            undoManager.redo()
        } else {
            guard undoManager.canUndo else { return false }
            undoManager.undo()
        }
        return true
    }

    private func performDeletedNoteHistory(redo: Bool) -> Bool {
        if redo {
            guard let record = deletedNoteRedoStack.popLast(),
                  let newRecord = store.deleteRecording(record.note.id) else { return false }
            deletedNoteUndoStack.append(newRecord)
        } else {
            guard let record = deletedNoteUndoStack.popLast() else { return false }
            store.restoreDeletion(record)
            deletedNoteRedoStack.append(record)
        }
        menuBarController.refresh()
        return true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Quick Notes")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Quick Notes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Quick Notes", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit Quick Notes", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        let new = fileMenu.addItem(withTitle: "New Note", action: #selector(createNewNote), keyEquivalent: "n")
        new.target = self
        let search = fileMenu.addItem(withTitle: "Search Notes", action: #selector(openSearch), keyEquivalent: "f")
        search.target = self
        fileMenu.addItem(.separator())
        let close = fileMenu.addItem(withTitle: "Close Quick Note", action: #selector(closeQuickNote), keyEquivalent: "w")
        close.target = self

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        let undo = editMenu.addItem(withTitle: "Undo", action: #selector(undoAction), keyEquivalent: "z")
        undo.target = self
        let redo = editMenu.addItem(withTitle: "Redo", action: #selector(redoAction), keyEquivalent: "z")
        redo.target = self
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let matchStyle = editMenu.addItem(
            withTitle: "Paste and Match Style",
            action: #selector(EscapeAwareTextView.pasteMatchingStyle(_:)),
            keyEquivalent: "v"
        )
        matchStyle.keyEquivalentModifierMask = [.command, .option, .shift]
        let plainText = editMenu.addItem(
            withTitle: "Paste as Plain Text",
            action: #selector(EscapeAwareTextView.pastePlainText(_:)),
            keyEquivalent: "v"
        )
        plainText.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(
            withTitle: "Paste Image",
            action: #selector(EscapeAwareTextView.pasteClipboardImage(_:)),
            keyEquivalent: ""
        )
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let emoji = editMenu.addItem(withTitle: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: " ")
        emoji.keyEquivalentModifierMask = [.control, .command]

        let formatMenuItem = NSMenuItem()
        mainMenu.addItem(formatMenuItem)
        let formatMenu = NSMenu(title: "Format")
        formatMenuItem.submenu = formatMenu

        addMenuItem(formatMenu, title: "Title", action: #selector(applyTitleStyle), key: "t", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Heading", action: #selector(applyHeadingStyle), key: "h", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Subheading", action: #selector(applySubheadingStyle), key: "j", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Body", action: #selector(applyBodyStyle), key: "b", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Monostyled", action: #selector(applyMonostyledStyle), key: "m", modifiers: [.command, .shift])
        formatMenu.addItem(.separator())
        addMenuItem(formatMenu, title: "Bold", action: #selector(toggleBold), key: "b", modifiers: .command)
        addMenuItem(formatMenu, title: "Italic", action: #selector(toggleItalic), key: "i", modifiers: .command)
        addMenuItem(formatMenu, title: "Underline", action: #selector(toggleUnderline), key: "u", modifiers: .command)
        addMenuItem(formatMenu, title: "Strikethrough", action: #selector(toggleStrikethrough))
        addMenuItem(formatMenu, title: "Highlight", action: #selector(toggleHighlight))
        formatMenu.addItem(.separator())
        addMenuItem(formatMenu, title: "Bulleted List", action: #selector(applyBulletedList), key: "7", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Dashed List", action: #selector(applyDashedList), key: "8", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Numbered List", action: #selector(applyNumberedList), key: "9", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Checklist", action: #selector(applyChecklist), key: "l", modifiers: [.command, .shift])
        addMenuItem(formatMenu, title: "Block Quote", action: #selector(applyBlockQuote), key: "'", modifiers: .command)

        let alignmentItem = NSMenuItem(title: "Alignment", action: nil, keyEquivalent: "")
        let alignmentMenu = NSMenu(title: "Alignment")
        alignmentItem.submenu = alignmentMenu
        addMenuItem(alignmentMenu, title: "Left", action: #selector(alignLeft))
        addMenuItem(alignmentMenu, title: "Center", action: #selector(alignCenter))
        addMenuItem(alignmentMenu, title: "Right", action: #selector(alignRight))
        addMenuItem(alignmentMenu, title: "Justified", action: #selector(alignJustified))
        formatMenu.addItem(alignmentItem)
        formatMenu.addItem(.separator())
        addMenuItem(formatMenu, title: "Increase Size", action: #selector(increaseFontSize), key: "+", modifiers: .command)
        addMenuItem(formatMenu, title: "Decrease Size", action: #selector(decreaseFontSize), key: "-", modifiers: .command)
        addMenuItem(formatMenu, title: "Clear Formatting", action: #selector(clearFormatting))

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        let sidebar = viewMenu.addItem(withTitle: "Show or Hide Recent Notes", action: #selector(toggleSidebar), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .shift]
        sidebar.target = self

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        NSApp.mainMenu = mainMenu
    }

    private func addMenuItem(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
    }
}
