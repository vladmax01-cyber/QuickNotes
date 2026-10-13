import AppKit
import SwiftUI
import QuickNotesCore

struct QuickNoteView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: NotesStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var editorController: RichTextEditorController

    let onNewNote: () -> Void
    let onDuplicateNote: (UUID) -> Void
    let onDeleteNote: (UUID) -> Void
    let onTogglePin: () -> Void
    let onOpenSettings: () -> Void
    let onHide: () -> Void
    let onQuit: () -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        ZStack {
            GlassWindowBackground(
                transparency: viewModel.isCollapsed && preferences.translucentCollapsedBar
                    ? max(preferences.windowTransparency, 0.72)
                    : preferences.windowTransparency,
                glassEnabled: viewModel.isCollapsed
                    ? preferences.translucentCollapsedBar
                    : preferences.useGlass,
                material: viewModel.isCollapsed ? .popover : .underWindowBackground
            )

            VStack(spacing: 0) {
                if viewModel.isCollapsed {
                    collapsedHeader
                        .transition(.opacity)
                } else {
                    header
                    Divider().opacity(0.55)
                    if let storageError = store.storageError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                            Text(storageError)
                                .foregroundStyle(.primary)
                        }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.08))
                            .accessibilityLabel("Storage error: \(storageError)")
                    }
                    content
                        .transition(.opacity)
                }
            }

            if viewModel.isSearchVisible && !viewModel.isCollapsed {
                SearchOverlay(
                    store: store,
                    preferences: preferences,
                    viewModel: viewModel,
                    onSelect: selectSearchResult
                )
                .padding(14)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .clipShape(RoundedRectangle(
            cornerRadius: viewModel.isCollapsed ? 22 : 14,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: viewModel.isCollapsed ? 22 : 14,
                style: .continuous
            )
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(viewModel.isCollapsed ? 0.18 : 0.12)
                        : Color.white.opacity(0.58),
                    lineWidth: 1
                )
        }
        .shadow(
            color: .black.opacity(viewModel.isCollapsed ? 0.16 : 0.10),
            radius: viewModel.isCollapsed ? 9 : 6,
            y: viewModel.isCollapsed ? 4 : 3
        )
        .padding(6)
        .tint(preferences.accentColor)
        .frame(minWidth: viewModel.isCollapsed ? 136 : 280,
               maxWidth: .infinity,
               maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Notes")
        .environment(\.locale, Locale(identifier: "en_US"))
        .alert("Delete \"\(deletionTargetTitle)\"?", isPresented: deletionAlertBinding) {
            Button("Delete Note", role: .destructive, action: confirmDeletion)
            Button("Cancel", role: .cancel, action: viewModel.cancelDeletion)
        } message: {
            Text("You can restore this note from Trash in Settings.")
        }
    }

    private var collapsedHeader: some View {
        WindowDragRegion(onDoubleClick: toggleCollapseWithFeedback)
            .overlay {
                Text(store.selectedNote?.title ?? "Quick Notes")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .tracking(0.1)
                    .foregroundStyle(Color.primary.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 22)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .help("Double-click to expand note")
            .contextMenu {
                Button("Expand Note", action: toggleCollapseWithFeedback)
                Button(preferences.translucentCollapsedBar ? "Turn Off Translucency" : "Use Translucency") {
                    preferences.translucentCollapsedBar.toggle()
                }
            }
            .accessibilityLabel("Collapsed note: \(store.selectedNote?.title ?? "Quick Notes")")
    }

    private var header: some View {
        let noteDetails = store.selectedNote.map(timestampDetails) ?? "Quick Notes"

        return GeometryReader { geometry in
            let expandedCount = preferences.showFormattingToolbarWhenWide
                ? inlineControlCount(for: geometry.size.width) : 0
            HStack(spacing: 4) {
                HeaderButton(
                    symbol: "sidebar.left",
                    label: viewModel.isSidebarVisible ? "Hide Recent Notes" : "Show Recent Notes",
                    tintColor: toolbarIconColor
                ) {
                    withAnimation(reducedMotionAnimation) {
                        viewModel.isSidebarVisible.toggle()
                    }
                }

                WindowDragRegion(onDoubleClick: toggleCollapseWithFeedback)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .help(noteDetails)

                HStack(spacing: 0) {
                    ForEach(preferences.toolbarOrder) { action in
                        toolbarControl(action, expandedCount: expandedCount)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .clipShape(Capsule())
                .animation(toolbarExpansionAnimation, value: expandedCount)

                moreMenu
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.18))
    }

    @ViewBuilder
    private func toolbarControl(
        _ action: ToolbarAction,
        expandedCount: Int
    ) -> some View {
        switch action {
        case .newNote:
            HeaderButton(
                symbol: "square.and.pencil",
                label: "New Note",
                tintColor: toolbarIconColor,
                onMove: { moveToolbarAction(action, offset: $0) },
                action: onNewNote
            )
        case .search:
            HeaderButton(
                symbol: "magnifyingglass",
                label: "Search Notes",
                tintColor: toolbarIconColor,
                onMove: { moveToolbarAction(action, offset: $0) }
            ) {
                withAnimation(reducedMotionAnimation) {
                    viewModel.showSearch()
                }
            }
            .keyboardShortcut("f", modifiers: .command)
        case .format:
            HStack(spacing: 2) {
                FormatPaletteButton(
                    isPresented: formatPaletteBinding,
                    controller: editorController,
                    preferences: preferences,
                    onMove: { moveToolbarAction(action, offset: $0) }
                )
                if expandedCount > 0 {
                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 1)
                    InlineFormatButton(label: "Bold", text: "B",
                                       isActive: editorController.formattingState.bold,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction(editorController.toggleBold)
                    }
                    .transition(inlineControlTransition)
                }
                if expandedCount > 1 {
                    InlineFormatButton(label: "Italic", text: "I",
                                       isActive: editorController.formattingState.italic,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction(editorController.toggleItalic)
                    }
                    .transition(inlineControlTransition)
                }
                if expandedCount > 2 {
                    InlineFormatButton(label: "Underline", text: "U",
                                       isActive: editorController.formattingState.underline,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction(editorController.toggleUnderline)
                    }
                    .transition(inlineControlTransition)
                }
                if expandedCount > 3 {
                    InlineFormatButton(label: "Checklist", symbol: "checklist",
                                       isActive: editorController.formattingState.listStyle == .checklist,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction { editorController.applyList(.checklist) }
                    }
                    .transition(inlineControlTransition)
                }
                if expandedCount > 4 {
                    InlineFormatButton(label: "Bulleted List", symbol: "list.bullet",
                                       isActive: editorController.formattingState.listStyle == .bulleted,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction { editorController.applyList(.bulleted) }
                    }
                    .transition(inlineControlTransition)
                }
                if expandedCount > 5 {
                    InlineFormatButton(label: "Numbered List", symbol: "list.number",
                                       isActive: editorController.formattingState.listStyle == .numbered,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction { editorController.applyList(.numbered) }
                    }
                    .transition(inlineControlTransition)
                }
                if expandedCount > 6 {
                    InlineFormatButton(label: "Strikethrough", text: "S",
                                       isActive: editorController.formattingState.strikethrough,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction(editorController.toggleStrikethrough)
                    }
                    .transition(inlineControlTransition)
                }
                if expandedCount > 7 {
                    InlineFormatButton(label: "Highlight", symbol: "highlighter",
                                       isActive: editorController.formattingState.highlight,
                                       accent: preferences.accentColor,
                                       inactiveColor: formatControlColor) {
                        performFormatAction(editorController.toggleHighlight)
                    }
                    .transition(inlineControlTransition)
                }
            }
        case .delete:
            HeaderButton(
                symbol: "trash",
                label: "Delete Note",
                tintColor: toolbarIconColor,
                onMove: { moveToolbarAction(action, offset: $0) }
            ) {
                if let id = store.selectedNoteID {
                    viewModel.requestDeletion(of: id)
                }
            }
        case .pin:
            HeaderButton(
                symbol: viewModel.isPinned ? "pin.fill" : "pin",
                label: viewModel.isPinned ? "Unpin Note" : "Pin Note",
                isActive: viewModel.isPinned,
                tintColor: toolbarIconColor,
                onMove: { moveToolbarAction(action, offset: $0) },
                action: {
                    withAnimation(reducedMotionAnimation) {
                        onTogglePin()
                    }
                    InteractionHaptics.shared.play(.pinChanged,
                                                    enabled: preferences.hapticFeedbackEnabled)
                }
            )
            .accessibilityValue(viewModel.isPinned ? "Pinned" : "Unpinned")
        }
    }

    private var moreMenu: some View {
        Menu {
            if let note = store.selectedNote {
                Button("Duplicate Note") {
                    onDuplicateNote(note.id)
                }
                Button("Delete Note…", role: .destructive) {
                    viewModel.requestDeletion(of: note.id)
                }
                Divider()
                Section("Note Info") {
                    Text("\(wordCount(in: note.text)) words · \(note.text.count) characters")
                    Text("Created \(exactDate(note.createdAt))")
                    Text("Edited \(exactDate(note.modifiedAt))")
                }
                Divider()
            }
            Button("Settings…", action: onOpenSettings)
                .keyboardShortcut(",", modifiers: .command)
            Button("Hide Quick Note", action: onHide)
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Quit Quick Notes", action: onQuit)
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(toolbarIconColor)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }

    private var content: some View {
        HStack(spacing: 0) {
            if viewModel.isSidebarVisible {
                RecentNotesSidebar(
                    store: store,
                    onSelect: { id in
                        store.select(id)
                    },
                    onDelete: viewModel.requestDeletion
                )
                .frame(width: 150)
                .transition(.move(edge: .leading).combined(with: .opacity))
                Divider().opacity(0.55)
            }

            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let note = store.selectedNote {
            ZStack(alignment: .topLeading) {
                Color(nsColor: .textBackgroundColor).opacity(
                    NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                        ? 1
                        : editorSurfaceOpacity
                )

                NativeTextEditor(
                    noteID: note.id,
                    text: note.text,
                    richTextData: note.richTextData,
                    focusGeneration: viewModel.editorFocusGeneration,
                    controller: editorController,
                    onChange: store.updateContent,
                    onEscape: escape
                )
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No Note Selected")
                    .font(.headline)
                Text("Create a note to start writing.")
                    .font(.callout)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var reducedMotionAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.12)
    }

    private var toolbarExpansionAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : .spring(response: 0.30, dampingFraction: 0.86)
    }

    private var inlineControlTransition: AnyTransition {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.88, anchor: .leading))
    }

    private func inlineControlCount(for width: CGFloat) -> Int {
        [335, 360, 385, 410, 435, 460, 485, 510]
            .prefix(while: { width >= CGFloat($0) }).count
    }

    private var editorSurfaceOpacity: Double {
        let transparency = min(1, max(0, preferences.windowTransparency))
        if transparency <= 0.45 {
            return 0.72 - ((transparency / 0.45) * 0.25)
        }
        return 0.47 - (((transparency - 0.45) / 0.55) * 0.22)
    }

    private func escape() {
        if viewModel.isSearchVisible {
            withAnimation(reducedMotionAnimation) {
                viewModel.closeSearch()
            }
        } else {
            onHide()
        }
    }

    private func selectSearchResult(_ note: QuickNote) {
        store.select(note.id)
        withAnimation(reducedMotionAnimation) {
            viewModel.closeSearch()
        }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeletionID != nil },
            set: { isPresented in
                if !isPresented { viewModel.cancelDeletion() }
            }
        )
    }

    private var deletionTargetTitle: String {
        guard let id = viewModel.pendingDeletionID else { return "this note" }
        return store.notes.first(where: { $0.id == id })?.title ?? "this note"
    }

    private var formatPaletteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isFormatPaletteVisible },
            set: { viewModel.isFormatPaletteVisible = $0 }
        )
    }

    private func confirmDeletion() {
        guard let id = viewModel.pendingDeletionID else { return }
        viewModel.cancelDeletion()
        onDeleteNote(id)
    }

    private func timestampDetails(for note: QuickNote) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: "en_US"))
        return "Created \(note.createdAt.formatted(style))\nEdited \(note.modifiedAt.formatted(style))"
    }

    private func exactDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(Locale(identifier: "en_US"))
        )
    }

    private func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func moveToolbarAction(_ action: ToolbarAction, offset: Int) {
        withAnimation(reducedMotionAnimation) {
            preferences.moveToolbarAction(action, offset: offset)
        }
    }

    private var toolbarIconColor: Color {
        preferences.toolbarUsesAccent ? preferences.accentColor : .primary
    }

    private var formatControlColor: Color {
        preferences.formatControlsUseAccent ? preferences.accentColor : .primary
    }

    private func performFormatAction(_ action: () -> Void) {
        action()
        editorController.refreshFormattingState()
        InteractionHaptics.shared.play(.inlineFormatApplied,
                                        enabled: preferences.hapticFeedbackEnabled)
    }

    private func toggleCollapseWithFeedback() {
        onToggleCollapse()
        InteractionHaptics.shared.play(.noteFolded,
                                        enabled: preferences.hapticFeedbackEnabled)
    }
}

private struct HeaderButton: View {
    let symbol: String
    let label: String
    var isActive = false
    var tintColor: Color = .primary
    var onMove: ((Int) -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: performAction) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isActive ? Color.accentColor : tintColor)
                .frame(width: 26, height: 26)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.20))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(isActive ? Color.accentColor : tintColor)
        .help(helpText)
        .accessibilityLabel(label)
    }

    private var helpText: String {
        guard onMove != nil else { return label }
        return "\(label)\nCommand-click: move right\nCommand-Shift-click: move left"
    }

    private func performAction() {
        if let offset = toolbarMoveOffset(), let onMove {
            onMove(offset)
        } else {
            action()
        }
    }
}

private struct FormatPaletteButton: View {
    @Binding var isPresented: Bool
    @ObservedObject var controller: RichTextEditorController
    @ObservedObject var preferences: AppPreferences
    let onMove: (Int) -> Void

    var body: some View {
        Button(action: performAction) {
            Text("Aa")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isPresented ? preferences.accentColor : (preferences.toolbarUsesAccent ? preferences.accentColor : Color.primary))
                .frame(width: 26, height: 26)
                .background(isPresented ? preferences.accentColor.opacity(0.19) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(preferences.toolbarUsesAccent ? preferences.accentColor : Color.primary)
        .help("Text Formatting\nCommand-click: move right\nCommand-Shift-click: move left")
        .accessibilityLabel("Text Formatting")
        .accessibilityValue(isPresented ? "Open" : "Closed")
        .background {
            PersistentFormattingPopover(
                isPresented: $isPresented,
                controller: controller,
                preferences: preferences
            )
            .frame(width: 26, height: 26)
            .allowsHitTesting(false)
        }
    }

    private func performAction() {
        if let offset = toolbarMoveOffset() {
            onMove(offset)
        } else {
            if !isPresented {
                controller.ensurePaletteSelection()
            } else {
                controller.clearPaletteSelection()
            }
            let opening = !isPresented
            isPresented.toggle()
            if opening {
                InteractionHaptics.shared.play(.paletteOpened,
                                                enabled: preferences.hapticFeedbackEnabled)
            }
        }
    }
}

private struct PersistentFormattingPopover: NSViewRepresentable {
    @Binding var isPresented: Bool
    let controller: RichTextEditorController
    let preferences: AppPreferences

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, controller: controller)
    }

    func makeNSView(context: Context) -> NSView {
        PopoverAnchorView()
    }

    func updateNSView(_ anchor: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isPresented = $isPresented
        if !isPresented {
            controller.setSelectionPreviewMode(false)
            coordinator.popover?.close()
            controller.clearPaletteSelection()
            return
        }
        controller.setSelectionPreviewMode(true)

        if coordinator.popover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.delegate = coordinator
            coordinator.popover = popover
        }

        DispatchQueue.main.async { [weak anchor, weak coordinator] in
            guard let anchor, let window = anchor.window,
                  let contentView = window.contentView,
                  let coordinator, coordinator.isPresented.wrappedValue,
                  let popover = coordinator.popover else { return }
            if popover.isShown {
                coordinator.alignPopover()
                return
            }
            let fontSizeInput = FontSizeInputModel()
            fontSizeInput.text = String(controller.currentFontSize)
            popover.contentViewController = NSHostingController(rootView: FormattingPalette(
                controller: controller,
                preferences: preferences,
                onClose: { [weak coordinator] in
                    controller.clearPaletteSelection()
                    coordinator?.isPresented.wrappedValue = false
                },
                fontSizeInput: fontSizeInput
            ))
            let anchorRect = anchor.convert(anchor.bounds, to: contentView)
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
            let paletteWidth: CGFloat = 266
            let openRight = FormattingPalettePlacement.side(
                of: window.frame,
                paletteWidth: paletteWidth,
                in: screenFrame
            ) == .right
            coordinator.noteWindow = window
            coordinator.paletteWidth = paletteWidth
            let edgeRect = NSRect(
                x: openRight ? contentView.bounds.maxX - 1 : contentView.bounds.minX,
                y: anchorRect.midY,
                width: 1,
                height: 1
            )
            popover.show(
                relativeTo: edgeRect,
                of: contentView,
                preferredEdge: openRight ? .maxX : .minX
            )
        }
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var isPresented: Binding<Bool>
        weak var controller: RichTextEditorController?
        var popover: NSPopover?
        weak var noteWindow: NSWindow?
        var paletteWidth: CGFloat = 266
        private var windowObservers: [NSObjectProtocol] = []

        init(isPresented: Binding<Bool>, controller: RichTextEditorController) {
            self.isPresented = isPresented
            self.controller = controller
        }

        deinit {
            removeWindowObservers()
        }

        func popoverDidShow(_ notification: Notification) {
            alignPopover()
            guard let noteWindow else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: noteWindow, queue: .main
                ) { [weak self] _ in
                    DispatchQueue.main.async { self?.alignPopover() }
                })
            }
        }

        func alignPopover() {
            guard let noteWindow, let popoverWindow = popover?.contentViewController?.view.window else { return }
            let screenFrame = noteWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? noteWindow.frame
            let side = FormattingPalettePlacement.side(
                of: noteWindow.frame, paletteWidth: paletteWidth, in: screenFrame
            )
            let x = FormattingPalettePlacement.popoverWindowX(
                nextTo: noteWindow.frame,
                windowWidth: popoverWindow.frame.width,
                contentWidth: paletteWidth,
                side: side,
                in: screenFrame
            )
            if abs(popoverWindow.frame.minX - x) > 0.5 {
                popoverWindow.setFrameOrigin(NSPoint(x: x, y: popoverWindow.frame.minY))
            }
        }

        private func removeWindowObservers() {
            for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
            windowObservers.removeAll()
        }

        func popoverDidClose(_ notification: Notification) {
            removeWindowObservers()
            controller?.setSelectionPreviewMode(false)
            if isPresented.wrappedValue { isPresented.wrappedValue = false }
        }
    }
}

private final class PopoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct InlineFormatButton: View {
    let label: String
    let text: String?
    let symbol: String?
    let isActive: Bool
    let accent: Color
    let inactiveColor: Color
    let action: () -> Void

    init(label: String, text: String, isActive: Bool, accent: Color, inactiveColor: Color,
         action: @escaping () -> Void) {
        self.label = label
        self.text = text
        symbol = nil
        self.isActive = isActive
        self.accent = accent
        self.inactiveColor = inactiveColor
        self.action = action
    }

    init(label: String, symbol: String, isActive: Bool, accent: Color, inactiveColor: Color,
         action: @escaping () -> Void) {
        self.label = label
        text = nil
        self.symbol = symbol
        self.isActive = isActive
        self.accent = accent
        self.inactiveColor = inactiveColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if label == "Strikethrough" {
                    StrikethroughGlyph(color: isActive ? accent : inactiveColor)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                } else if let text {
                    Text(text)
                        .font(.system(size: 15, weight: label == "Bold" ? .bold : .semibold))
                        .italic(label == "Italic")
                        .underline(label == "Underline")
                }
            }
            .foregroundStyle(isActive ? accent : inactiveColor)
            .frame(width: 27, height: 27)
        }
        .buttonStyle(InlineFormatButtonStyle(accent: accent, isActive: isActive))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                   ? nil : .easeOut(duration: 0.14), value: isActive)
    }
}

private struct StrikethroughGlyph: View {
    let color: Color

    var body: some View {
        Image(systemName: "strikethrough")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

private struct InlineFormatButtonStyle: ButtonStyle {
    let accent: Color
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return configuration.label
            .background(shape.fill(isActive ? accent.opacity(0.23)
                                   : configuration.isPressed ? Color.primary.opacity(0.10) : .clear))
            .overlay(shape.strokeBorder(isActive ? accent.opacity(0.60) : .clear, lineWidth: 0.7))
            .contentShape(shape)
    }
}

private struct FormattingPalette: View {
    @ObservedObject var controller: RichTextEditorController
    @ObservedObject var preferences: AppPreferences
    let onClose: () -> Void
    @ObservedObject var fontSizeInput: FontSizeInputModel

    private var formatControlColor: Color {
        preferences.formatControlsUseAccent ? preferences.accentColor : .primary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Format")
                        .font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close Formatting")
                }

                HStack(spacing: 6) {
                    PaletteFormatButton(label: "Bold", text: "B", font: .headline,
                                        isActive: controller.formattingState.bold,
                                        accent: preferences.accentColor,
                                        inactiveColor: formatControlColor) {
                        apply(controller.toggleBold)
                    }
                    PaletteFormatButton(label: "Italic", text: "I", font: .headline.italic(),
                                        isActive: controller.formattingState.italic,
                                        accent: preferences.accentColor,
                                        inactiveColor: formatControlColor) {
                        apply(controller.toggleItalic)
                    }
                    PaletteFormatButton(label: "Underline", text: "U", font: .headline,
                                        underline: true, isActive: controller.formattingState.underline,
                                        accent: preferences.accentColor,
                                        inactiveColor: formatControlColor) {
                        apply(controller.toggleUnderline)
                    }
                    PaletteFormatButton(label: "Strikethrough", text: "S", font: .headline,
                                        isActive: controller.formattingState.strikethrough,
                                        accent: preferences.accentColor,
                                        inactiveColor: formatControlColor) {
                        apply(controller.toggleStrikethrough)
                    }
                    PaletteFormatButton(label: "Highlight", symbol: "highlighter",
                                        isActive: controller.formattingState.highlight,
                                        accent: preferences.accentColor,
                                        inactiveColor: formatControlColor) {
                        apply(controller.toggleHighlight)
                    }
                }

                paletteSection("Highlight") {
                    HStack(spacing: 7) {
                        ForEach(RichTextEditorController.HighlightColor.allCases) { color in
                            HighlightSwatchButton(
                                color: color,
                                accent: preferences.accentColor,
                                isSelected: controller.formattingState.highlight
                                    && controller.formattingState.highlightColor == color
                            ) {
                                apply { controller.applyHighlight(color) }
                            }
                        }
                        Rectangle()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: 1, height: 18)
                        Button {
                            apply(controller.removeHighlight)
                        } label: {
                            Image(systemName: "eraser")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove Highlight")
                        .help("Remove Highlight")
                    }
                }

                paletteSection("Text Style") {
                    VStack(spacing: 4) {
                        styleButton(.title, font: .system(size: 26, weight: .bold))
                        styleButton(.heading, font: .system(size: 20, weight: .semibold))
                        styleButton(.subheading, font: .system(size: 16, weight: .semibold))
                        styleButton(.body, font: .system(size: 13))
                        styleButton(.monostyled, font: .system(size: 13, design: .monospaced))
                    }
                }

                paletteSection("Lists and Quotes") {
                    VStack(spacing: 4) {
                        listButton("Checklist", symbol: "circle", style: .checklist)
                        listButton("Bulleted list", symbol: "list.bullet", style: .bulleted)
                        listButton("Numbered list", symbol: "list.number", style: .numbered)
                        listButton("Dashed list", symbol: "list.dash", style: .dashed)
                        listButton("Block quote", symbol: "text.quote", style: .blockQuote)
                    }
                }

                paletteSection("Alignment") {
                    HStack(spacing: 6) {
                        alignmentButton("text.alignleft", .left, label: "Align Left")
                        alignmentButton("text.aligncenter", .center, label: "Align Center")
                        alignmentButton("text.alignright", .right, label: "Align Right")
                        alignmentButton("text.justify", .justified, label: "Justify")
                    }
                }

                HStack(spacing: 8) {
                    if preferences.fontSizeControlStyle == .numeric {
                        Text("Size")
                        Button {
                            resizeFont(by: -1)
                        } label: {
                            Image(systemName: "minus")
                        }
                        .accessibilityLabel("Decrease Font Size")
                        TextField("Size", text: $fontSizeInput.text)
                            .frame(width: 38)
                            .multilineTextAlignment(.center)
                            .onSubmit(commitFontSize)
                            .accessibilityLabel("Font Size")
                        Button {
                            resizeFont(by: 1)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Increase Font Size")
                    } else {
                        Button {
                            resizeFont(by: -1)
                        } label: {
                            Label("Smaller", systemImage: "textformat.size.smaller")
                        }
                        Button {
                            resizeFont(by: 1)
                        } label: {
                            Label("Larger", systemImage: "textformat.size.larger")
                        }
                    }
                    Spacer()
                    Button("Clear") {
                        apply(controller.clearFormatting)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(14)
        }
        .frame(width: 266, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(preferences.accentColor)
        .accessibilityLabel("Text Formatting Options")
        .onDisappear(perform: commitFontSize)
    }

    private func paletteSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.quickNotesSecondaryText)
            content()
        }
    }

    private func styleButton(_ style: RichTextEditorController.TextStyle, font: Font) -> some View {
        Button {
            apply { controller.apply(style) }
        } label: {
            HStack {
                Text(style.rawValue)
                    .font(font)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PaletteRowButtonStyle(accent: preferences.accentColor,
                                          isActive: controller.formattingState.textStyle == style))
        .accessibilityLabel("Apply \(style.rawValue) style")
        .accessibilityValue(controller.formattingState.textStyle == style ? "Selected" : "")
    }

    private func listButton(
        _ title: String,
        symbol: String,
        style: RichTextEditorController.ListStyle
    ) -> some View {
        Button {
            apply { controller.applyList(style) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PaletteRowButtonStyle(accent: preferences.accentColor,
                                          isActive: controller.formattingState.listStyle == style))
        .accessibilityLabel(title)
        .accessibilityValue(controller.formattingState.listStyle == style ? "Selected" : "")
    }

    private func alignmentButton(
        _ symbol: String,
        _ alignment: NSTextAlignment,
        label: String
    ) -> some View {
        Button {
            apply { controller.setAlignment(alignment) }
        } label: {
            Image(systemName: symbol)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(PaletteRowButtonStyle(accent: preferences.accentColor,
                                          isActive: controller.formattingState.alignment == alignment))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(controller.formattingState.alignment == alignment ? "Selected" : "")
    }

    private func apply(_ action: () -> Void) {
        commitPendingFontSize()
        controller.applyPaletteAction(action)
        InteractionHaptics.shared.play(.formatApplied,
                                        enabled: preferences.hapticFeedbackEnabled)
        syncFontSize()
    }

    private func resizeFont(by delta: Int) {
        let size = min(72, max(9, controller.currentFontSize + delta))
        apply { controller.setFontSize(CGFloat(size)) }
    }

    private func commitFontSize() {
        commitPendingFontSize()
        syncFontSize()
    }

    private func commitPendingFontSize() {
        guard let size = Int(fontSizeInput.text.trimmingCharacters(in: .whitespaces)),
              (9...72).contains(size), size != controller.currentFontSize else { return }
        controller.restorePaletteSelection()
        controller.setFontSize(CGFloat(size))
        controller.rememberPaletteSelection()
        controller.refreshFormattingState()
    }

    private func syncFontSize() {
        fontSizeInput.text = String(controller.currentFontSize)
    }
}

private final class FontSizeInputModel: ObservableObject {
    @Published var text = ""
}

private struct HighlightSwatchButton: View {
    let color: RichTextEditorController.HighlightColor
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color.nsColor.withAlphaComponent(0.88)))
                .frame(width: 17, height: 17)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? accent.opacity(0.14) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.primary.opacity(0.7) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Highlight \(color.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "")
        .help("Highlight \(color.rawValue)")
    }
}

private struct PaletteFormatButton: View {
    let label: String
    let text: String?
    let symbol: String?
    let font: Font
    let underline: Bool
    let isActive: Bool
    let accent: Color
    let inactiveColor: Color
    let action: () -> Void

    init(
        label: String,
        text: String,
        font: Font,
        underline: Bool = false,
        isActive: Bool,
        accent: Color,
        inactiveColor: Color,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.text = text
        symbol = nil
        self.font = font
        self.underline = underline
        self.isActive = isActive
        self.accent = accent
        self.inactiveColor = inactiveColor
        self.action = action
    }

    init(label: String, symbol: String, isActive: Bool, accent: Color, inactiveColor: Color,
         action: @escaping () -> Void) {
        self.label = label
        text = nil
        self.symbol = symbol
        font = .headline
        underline = false
        self.isActive = isActive
        self.accent = accent
        self.inactiveColor = inactiveColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if label == "Strikethrough" {
                    StrikethroughGlyph(color: isActive ? accent : inactiveColor)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                } else if let text {
                    Text(text)
                        .font(font)
                        .underline(underline)
                }
            }
            .foregroundStyle(isActive ? accent : inactiveColor)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaletteRowButtonStyle(accent: accent, isActive: isActive))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "Off")
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                   ? nil : .easeOut(duration: 0.14), value: isActive)
    }
}

private struct PaletteRowButtonStyle: ButtonStyle {
    let accent: Color
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed || isActive
                          ? accent.opacity(isActive ? 0.20 : 0.15)
                          : Color.primary.opacity(0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? accent.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private func toolbarMoveOffset() -> Int? {
    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command) else { return nil }
    return flags.contains(.shift) ? -1 : 1
}

private struct RecentNotesSidebar: View {
    @ObservedObject var store: NotesStore
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        List(selection: Binding(
            get: { store.selectedNoteID },
            set: { id in
                if let id { onSelect(id) }
            }
        )) {
            ForEach(store.sortedNotes) { note in
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if !note.preview.isEmpty {
                        Text(note.preview)
                            .font(.caption2)
                            .foregroundStyle(Color.quickNotesSecondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
                .tag(note.id)
                .help(timestampDetails(for: note))
                .contextMenu {
                    Button("Delete Note", role: .destructive) {
                        onDelete(note.id)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    note.preview.isEmpty ? note.title : "\(note.title), \(note.preview)"
                )
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.28))
        .accessibilityLabel("Recent Notes")
    }

    private func timestampDetails(for note: QuickNote) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: "en_US"))
        return "Created \(note.createdAt.formatted(style))\nEdited \(note.modifiedAt.formatted(style))"
    }
}

private struct SearchOverlay: View {
    @ObservedObject var store: NotesStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var viewModel: AppViewModel
    let onSelect: (QuickNote) -> Void

    private var results: [QuickNote] {
        store.searchResults(for: viewModel.searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                NativeSearchField(
                    text: viewModel.searchQuery,
                    focusGeneration: viewModel.searchFocusGeneration,
                    onChange: { query in
                        viewModel.searchQuery = query
                        viewModel.searchSelection = 0
                    },
                    onSubmit: selectCurrent
                )
                .frame(height: 24)
                Button {
                    viewModel.closeSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Search")
                .accessibilityLabel("Close Search")
            }
            .padding(12)

            Divider()

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(viewModel.searchQuery.isEmpty ? "Type to Search" : "No Results")
                        .font(.headline)
                    Text(viewModel.searchQuery.isEmpty
                         ? "Search titles and note text."
                         : "Try a different search.")
                        .font(.callout)
                        .foregroundStyle(Color.quickNotesSecondaryText)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, note in
                                Button {
                                    onSelect(note)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(note.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            if !note.preview.isEmpty {
                                                Text(note.preview)
                                                    .font(.caption)
                                                    .foregroundStyle(Color.quickNotesSecondaryText)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        if index == viewModel.searchSelection {
                                            Image(systemName: "return")
                                                .foregroundStyle(.secondary)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(index == viewModel.searchSelection
                                                  ? preferences.accentColor.opacity(0.18)
                                                  : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(note.id)
                                .accessibilityLabel(note.title)
                                .accessibilityValue(
                                    index == viewModel.searchSelection
                                        ? "Current selection"
                                        : "Not selected"
                                )
                                .contextMenu {
                                    Button("Delete Note…", role: .destructive) {
                                        viewModel.closeSearch()
                                        viewModel.requestDeletion(of: note.id)
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: viewModel.searchSelection) { _, newValue in
                        guard results.indices.contains(newValue) else { return }
                        proxy.scrollTo(results[newValue].id)
                    }
                }
            }
        }
        .frame(maxWidth: 420, maxHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search Notes")
    }

    private func selectCurrent() {
        guard results.indices.contains(viewModel.searchSelection) else { return }
        onSelect(results[viewModel.searchSelection])
    }
}
