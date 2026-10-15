import AppKit
import SwiftUI
import QuickNotesCore

private func quickNoteMovementFrame(for screen: NSScreen) -> NSRect {
    WindowPlacement.movementFrame(
        visibleFrame: screen.visibleFrame,
        fullFrame: screen.frame
    )
}

final class QuickNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let screen else { return frameRect }
        return WindowPlacement.clamped(frameRect, to: quickNoteMovementFrame(for: screen))
    }
}

@MainActor
final class QuickNotePanelController: NSWindowController, NSWindowDelegate {
    private enum StorageKey {
        static let size = "quickNotesWindowSize"
        static let screenOffsets = "quickNotesScreenOffsets"
    }

    private let store: NotesStore
    private let preferences: AppPreferences
    private let viewModel: AppViewModel
    private let editorController: RichTextEditorController
    private let defaults: UserDefaults
    private let noteUndoManager = UndoManager()
    private var previousApplication: NSRunningApplication?
    private var isHiding = false
    private var visibilityRevision: UInt = 0
    private var focusLossRevision: UInt = 0
    private var activeMenus: [ObjectIdentifier: NSMenu] = [:]
    var isTrackingMenu: Bool { !activeMenus.isEmpty }
    private var lastSpaceChangeUptime: TimeInterval = -.infinity
    private let expandedMinimum = NSSize(width: 280, height: 280)
    private let expandedMaximum = NSSize(width: 4096, height: 4096)
    private let collapsedMinimumWidth: CGFloat = 136
    private let collapsedHeight: CGFloat = 44
    private var expandedSize: NSSize?
    private var collapsedScrollPosition: (noteID: UUID, origin: NSPoint)?
    private var isChangingCollapse = false

    var shouldSuppressFocusLoss: () -> Bool = { false }

    init(
        store: NotesStore,
        preferences: AppPreferences,
        viewModel: AppViewModel,
        editorController: RichTextEditorController,
        updateChecker: UpdateChecker,
        defaults: UserDefaults = .standard,
        onNewNote: @escaping () -> Void,
        onDuplicateNote: @escaping (UUID) -> Void,
        onDeleteNote: @escaping (UUID) -> Void,
        onTogglePin: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.viewModel = viewModel
        self.editorController = editorController
        self.defaults = defaults

        let panel = QuickNotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Notes"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.minSize = expandedMinimum
        panel.maxSize = expandedMaximum
        panel.level = .floating
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .ignoresCycle,
            .fullScreenDisallowsTiling
        ]
        if #available(macOS 26.0, *) {
            behavior.insert(.canJoinAllApplications)
        } else {
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior

        let rootView = QuickNoteView(
            store: store,
            preferences: preferences,
            viewModel: viewModel,
            editorController: editorController,
            updateChecker: updateChecker,
            onNewNote: onNewNote,
            onDuplicateNote: onDuplicateNote,
            onDeleteNote: onDeleteNote,
            onTogglePin: onTogglePin,
            onOpenSettings: onOpenSettings,
            onHide: {},
            onQuit: onQuit,
            onToggleCollapse: {}
        )
        let hostingController = NSHostingController(rootView: rootView.ignoresSafeArea(.container, edges: .top))
        hostingController.sizingOptions = []
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 0
        hostingController.view.layer?.masksToBounds = false

        let containerController = NSViewController()
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 280))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerController.view = containerView
        containerController.addChild(hostingController)
        hostingController.view.frame = containerView.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingController.view)

        panel.contentViewController = containerController

        super.init(window: panel)
        panel.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuDidEndTracking(_:)),
            name: NSMenu.didEndTrackingNotification, object: nil
        )

        hostingController.rootView = QuickNoteView(
            store: store,
            preferences: preferences,
            viewModel: viewModel,
            editorController: editorController,
            updateChecker: updateChecker,
            onNewNote: onNewNote,
            onDuplicateNote: onDuplicateNote,
            onDeleteNote: onDeleteNote,
            onTogglePin: onTogglePin,
            onOpenSettings: onOpenSettings,
            onHide: { [weak self] in self?.hide(restoreFocus: true) },
            onQuit: onQuit,
            onToggleCollapse: { [weak self] in self?.toggleCollapsed() }
        ).ignoresSafeArea(.container, edges: .top)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isPresented: Bool {
        window?.isVisible == true && !isHiding
    }

    func toggle() {
        isPresented ? hide(restoreFocus: true) : show()
    }

    func show() {
        guard let panel = window as? QuickNotePanel else { return }
        restoreExpandedStateIfNeeded()
        visibilityRevision &+= 1
        isHiding = false
        if panel.isVisible {
            panel.alphaValue = 1
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.focusEditor()
            }
            return
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }

        let screen = screenForPresentation()
        let targetFrame = resolvedFrame(on: screen)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(
            reduceMotion ? targetFrame : targetFrame.offsetBy(dx: 0, dy: -4),
            display: false
        )
        panel.level = .floating
        panel.alphaValue = reduceMotion ? 1 : 0
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)

        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(targetFrame, display: true)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.viewModel.focusEditor()
        }
    }

    func hide(restoreFocus: Bool, animated: Bool = true) {
        guard let panel = window, panel.isVisible, !isHiding else { return }
        viewModel.isFormatPaletteVisible = false
        visibilityRevision &+= 1
        let hideRevision = visibilityRevision
        isHiding = true
        store.flush()
        persistFrame()

        let finish: () -> Void = { [weak self, weak panel] in
            guard let self,
                  let panel,
                  self.visibilityRevision == hideRevision,
                  self.isHiding else { return }
            panel.orderOut(nil)
            self.restoreExpandedStateIfNeeded()
            panel.alphaValue = 1
            self.isHiding = false
            if restoreFocus,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                self.previousApplication?.activate(options: [])
            }
        }

        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finish()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: {
                DispatchQueue.main.async(execute: finish)
            }
        }
    }

    func setPinned(_ pinned: Bool) {
        viewModel.isPinned = pinned
        preferences.defaultPinned = pinned
        window?.level = .floating
    }

    func toggleCollapsed() {
        guard let panel = window as? QuickNotePanel,
              panel.isVisible, !isChangingCollapse else { return }
        let collapsing = !viewModel.isCollapsed
        let current = panel.frame
        let target: NSRect

        if collapsing {
            persistFrame()
            expandedSize = current.size
            if let noteID = store.selectedNote?.id,
               let scrollView = editorController.textView?.enclosingScrollView {
                collapsedScrollPosition = (noteID, scrollView.contentView.bounds.origin)
            } else {
                collapsedScrollPosition = nil
            }
            viewModel.isFormatPaletteVisible = false
            viewModel.isSearchVisible = false
            let width = collapsedWidth(for: store.selectedNote?.title ?? "Quick Notes", available: current.width)
            target = NSRect(
                x: current.maxX - width,
                y: current.maxY - collapsedHeight,
                width: width,
                height: collapsedHeight
            )
            panel.minSize = NSSize(width: collapsedMinimumWidth, height: collapsedHeight)
        } else {
            panel.maxSize = expandedMaximum
            target = expandedFrame(from: current)
        }

        isChangingCollapse = true
        editorController.textView?.enclosingScrollView?.verticalScroller?.isHidden = true
        viewModel.isCollapseAnimating = true
        let finish: () -> Void = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.setFrame(target, display: true)
            if collapsing {
                panel.maxSize = NSSize(width: self.expandedMaximum.width, height: self.collapsedHeight)
            } else {
                panel.minSize = self.expandedMinimum
                self.expandedSize = nil
                self.viewModel.focusEditor()
                self.restoreCollapsedScrollPosition()
            }
            self.isChangingCollapse = false
            self.viewModel.isCollapseAnimating = false
            self.persistFrame()
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            viewModel.isCollapsed = collapsing
            finish()
        } else if collapsing {
            let compactHeightFrame = NSRect(
                x: current.minX,
                y: current.maxY - collapsedHeight,
                width: current.width,
                height: collapsedHeight
            )
            animateFrame(panel, to: compactHeightFrame, duration: 0.18) { [weak self, weak panel] in
                guard let self, let panel else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    self.viewModel.isCollapsed = true
                }
                self.animateFrame(panel, to: target, duration: 0.13, completion: finish)
            }
        } else {
            let expandedWidthFrame = NSRect(
                x: target.minX,
                y: current.maxY - collapsedHeight,
                width: target.width,
                height: collapsedHeight
            )
            animateFrame(panel, to: expandedWidthFrame, duration: 0.11) { [weak self, weak panel] in
                guard let self, let panel else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    self.viewModel.isCollapsed = false
                }
                self.animateFrame(panel, to: target, duration: 0.22, completion: finish)
            }
        }
    }

    private func animateFrame(
        _ panel: NSWindow,
        to target: NSRect,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: {
            DispatchQueue.main.async(execute: completion)
        }
    }

    func activeSpaceDidChange() {
        lastSpaceChangeUptime = ProcessInfo.processInfo.systemUptime
        focusLossRevision &+= 1
    }

    func repositionIfNeeded() {
        guard let panel = window, panel.isVisible else { return }
        let screen = panel.screen ?? screenForPresentation()
        panel.setFrame(
            WindowPlacement.clamped(panel.frame, to: quickNoteMovementFrame(for: screen)),
            display: true
        )
        persistFrame()
    }

    func windowDidMove(_ notification: Notification) {
        persistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        if !isChangingCollapse, let panel = window {
            let size = panel.frame.size
            let minimum = viewModel.isCollapsed
                ? NSSize(width: collapsedMinimumWidth, height: collapsedHeight)
                : expandedMinimum
            if size.width < minimum.width || size.height < minimum.height {
                let width = max(size.width, minimum.width)
                let height = max(size.height, minimum.height)
                panel.setFrame(NSRect(
                    x: panel.frame.maxX - width,
                    y: panel.frame.maxY - height,
                    width: width,
                    height: height
                ), display: true)
                return
            }
            if panel.inLiveResize { return }
        }
        persistFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !isChangingCollapse else { return frameSize }
        let minimum = viewModel.isCollapsed
            ? NSSize(width: collapsedMinimumWidth, height: collapsedHeight)
            : expandedMinimum
        return NSSize(
            width: max(frameSize.width, minimum.width),
            height: max(frameSize.height, minimum.height)
        )
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        noteUndoManager
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide(restoreFocus: true)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        scheduleFocusLossHide()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusLossRevision &+= 1
    }

    @objc private func menuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        activeMenus[ObjectIdentifier(menu)] = menu
        focusLossRevision &+= 1
    }

    @objc private func menuDidEndTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        activeMenus.removeValue(forKey: ObjectIdentifier(menu))
        if activeMenus.isEmpty, window?.isKeyWindow == false {
            scheduleFocusLossHide()
        }
    }

    func dismissTrackedMenus() -> Bool {
        let menus = Array(activeMenus.values)
        for menu in menus { menu.cancelTracking() }
        return !menus.isEmpty
    }

    private func scheduleFocusLossHide() {
        guard preferences.hideOnFocusLoss, !viewModel.isPinned, !viewModel.isCollapsed else { return }
        focusLossRevision &+= 1
        let revision = focusLossRevision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  self.focusLossRevision == revision,
                  ProcessInfo.processInfo.systemUptime - self.lastSpaceChangeUptime > 0.5,
                  self.window?.isKeyWindow == false,
                  self.activeMenus.isEmpty,
                  !self.shouldSuppressFocusLoss() else { return }
            if NSApp.isActive { return }
            self.hide(restoreFocus: false)
        }
    }

    private func screenForPresentation() -> NSScreen {
        if let main = NSScreen.main { return main }
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.screens.first
            ?? NSScreen()
    }

    private func resolvedFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        var size = NSSize(width: 280, height: 280)

        if preferences.rememberSize,
           let stored = defaults.string(forKey: StorageKey.size) {
            let parsed = NSSizeFromString(stored)
            if parsed.width > 0, parsed.height > 0 {
                size = parsed
            }
        }

        size.width = min(max(size.width, expandedMinimum.width), min(expandedMaximum.width, visible.width))
        size.height = min(max(size.height, expandedMinimum.height), min(expandedMaximum.height, visible.height))
        var frame = WindowPlacement.defaultFrame(in: visible, size: size)

        if preferences.rememberPosition,
           let offsets = defaults.dictionary(forKey: StorageKey.screenOffsets),
           let stored = offsets[screenIdentifier(screen)] as? [String: Double],
           let leading = stored["leading"],
           let top = stored["top"] {
            frame.origin.x = visible.minX + leading
            frame.origin.y = visible.maxY - top - size.height
        }

        return WindowPlacement.clamped(frame, to: quickNoteMovementFrame(for: screen))
    }

    private func expandedFrame(from compactFrame: NSRect) -> NSRect {
        let storedSize = expandedSize ?? NSSize(width: 280, height: 280)
        let size = NSSize(
            width: max(storedSize.width, expandedMinimum.width),
            height: max(storedSize.height, expandedMinimum.height)
        )
        let frame = NSRect(
            x: compactFrame.maxX - size.width,
            y: compactFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let screen = window?.screen ?? screenForPresentation()
        return WindowPlacement.clamped(frame, to: quickNoteMovementFrame(for: screen))
    }

    private func restoreExpandedStateIfNeeded() {
        guard viewModel.isCollapsed, let panel = window as? QuickNotePanel else { return }
        isChangingCollapse = true
        let target = expandedFrame(from: panel.frame)
        panel.maxSize = expandedMaximum
        viewModel.isCollapsed = false
        panel.setFrame(target, display: panel.isVisible)
        panel.minSize = expandedMinimum
        expandedSize = nil
        isChangingCollapse = false
        persistFrame()
        restoreCollapsedScrollPosition()
    }

    private func restoreCollapsedScrollPosition() {
        guard let position = collapsedScrollPosition else { return }
        collapsedScrollPosition = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.store.selectedNote?.id == position.noteID,
                  let scrollView = self.editorController.textView?.enclosingScrollView else { return }
            scrollView.layoutSubtreeIfNeeded()
            scrollView.contentView.scroll(to: position.origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func persistFrame() {
        guard !viewModel.isCollapsed, !isChangingCollapse else { return }
        guard let panel = window, let screen = panel.screen else { return }
        if preferences.rememberSize {
            defaults.set(NSStringFromSize(panel.frame.size), forKey: StorageKey.size)
        }
        if preferences.rememberPosition {
            var offsets = defaults.dictionary(forKey: StorageKey.screenOffsets) ?? [:]
            offsets[screenIdentifier(screen)] = [
                "leading": panel.frame.minX - screen.visibleFrame.minX,
                "top": screen.visibleFrame.maxY - panel.frame.maxY
            ]
            defaults.set(offsets, forKey: StorageKey.screenOffsets)
        }
    }

    private func collapsedWidth(for title: String, available: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return min(available, min(320, max(collapsedMinimumWidth, ceil(titleWidth + 48))))
    }

    private func screenIdentifier(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}
