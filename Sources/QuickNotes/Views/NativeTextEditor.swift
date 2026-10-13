import AppKit
import SwiftUI

final class EscapeAwareTextView: NSTextView {
    var escapeAction: (() -> Void)?
    var isResizingAttachments = false
    var commitPendingChanges: (() -> Void)?
    private var pendingAttachmentResize: DispatchWorkItem?
    private var attachmentSourceSizes: [ObjectIdentifier: NSSize] = [:]
    private var imageDragCandidate: (data: Data, point: NSPoint)?
    private var draggedImageURL: URL?
    private var selectedImageData: Data?
    private var isPastingText = false

    func resetAttachmentSizeCache() {
        attachmentSourceSizes.removeAll(keepingCapacity: true)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 1
        super.setFrameSize(newSize)
        if widthChanged {
            pendingAttachmentResize?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.resizeAttachmentsToFit() }
            pendingAttachmentResize = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    override func paste(_ sender: Any?) {
        isPastingText = true
        super.paste(sender)
        isPastingText = false
        if let storage = textStorage { ChecklistMarkerStyle.normalize(in: storage) }
        resizeAttachmentsToFit()
    }

    func resizeAttachmentsToFit() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let availableWidth = max(80, min(480, bounds.width - textContainerInset.width * 2 - 8))
        let fullRange = NSRange(location: 0, length: storage.length)
        var updates: [(NSTextAttachment, NSRange)] = []
        storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let identity = ObjectIdentifier(attachment)
            let sourceSize: NSSize
            if let cached = attachmentSourceSizes[identity] {
                sourceSize = cached
            } else {
                let image = attachment.image
                    ?? attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:))
                sourceSize = image?.size ?? attachment.bounds.size
                attachmentSourceSizes[identity] = sourceSize
            }
            guard sourceSize.width > 0, sourceSize.height > 0 else { return }
            let scale = min(1, availableWidth / sourceSize.width, 360 / sourceSize.height)
            let target = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            if abs(attachment.bounds.width - target.width) > 0.5
                || abs(attachment.bounds.height - target.height) > 0.5 {
                attachment.bounds = NSRect(origin: .zero, size: target)
                updates.append((attachment, range))
            }
        }
        guard !updates.isEmpty else { return }
        isResizingAttachments = true
        storage.beginEditing()
        for (attachment, range) in updates {
            storage.addAttribute(.attachment, value: attachment, range: range)
        }
        storage.endEditing()
        isResizingAttachments = false
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option) {
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            pasteOptionsMenu().popUp(positioning: nil, at: point, in: self)
            return
        }
        if toggleChecklist(at: point) { return }
        if let image = imageData(at: point) {
            selectedImageData = image.data
            imageDragCandidate = (image.data, point)
            setSelectedRange(NSRange(location: image.location, length: 1))
            return
        }
        imageDragCandidate = nil
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let candidate = imageDragCandidate else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - candidate.point.x, point.y - candidate.point.y) > 4 else { return }
        imageDragCandidate = nil
        beginImageDrag(candidate.data, event: event, at: candidate.point)
    }

    override func mouseUp(with event: NSEvent) {
        imageDragCandidate = nil
        super.mouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let image = imageData(at: point) else { return super.menu(for: event) }
        selectedImageData = image.data
        let menu = NSMenu(title: "Image")
        let copy = menu.addItem(withTitle: "Copy Image", action: #selector(copySelectedImage), keyEquivalent: "")
        copy.target = self
        let save = menu.addItem(withTitle: "Save Image As…", action: #selector(saveSelectedImage), keyEquivalent: "")
        save.target = self
        return menu
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        if range.length == 1,
           let attachment = textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil)
                as? NSTextAttachment,
           let data = imageData(for: attachment) {
            writeImageToPasteboard(data)
        } else {
            super.copy(sender)
        }
    }

    @objc private func copySelectedImage(_ sender: Any?) {
        guard let selectedImageData else { return }
        writeImageToPasteboard(selectedImageData)
    }

    @objc private func saveSelectedImage(_ sender: Any?) {
        guard let selectedImageData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Quick Note Image.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? selectedImageData.write(to: url, options: .atomic)
    }

    private func writeImageToPasteboard(_ data: Data) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: .png)
    }

    private func imageData(at point: NSPoint) -> (data: Data, location: Int)? {
        guard let layoutManager, let textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        let location = layoutManager.characterIndexForGlyph(at: glyph)
        guard location < storage.length,
              let attachment = storage.attribute(.attachment, at: location, effectiveRange: nil)
                as? NSTextAttachment else { return nil }
        let rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer
        )
        guard rect.insetBy(dx: -3, dy: -3).contains(local) else { return nil }
        guard let data = imageData(for: attachment) else { return nil }
        return (data, location)
    }

    private func imageData(for attachment: NSTextAttachment) -> Data? {
        if let contents = attachment.fileWrapper?.regularFileContents,
           let image = NSImage(data: contents) {
            return pngData(for: image) ?? contents
        }
        guard let image = attachment.image else { return nil }
        return pngData(for: image)
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func beginImageDrag(_ data: Data, event: NSEvent, at point: NSPoint) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Quick Notes Image Drags", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Image-\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            draggedImageURL = url
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: .png)
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)
            let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let preview = NSImage(data: data) ?? NSImage(size: NSSize(width: 80, height: 80))
            let size = NSSize(width: min(preview.size.width, 180), height: min(preview.size.height, 180))
            item.setDraggingFrame(NSRect(origin: point, size: size), contents: preview)
            beginDraggingSession(with: [item], event: event, source: self)
        } catch {
            NSSound.beep()
        }
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation {
        .copy
    }

    override func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        super.draggingSession(session, endedAt: screenPoint, operation: operation)
        guard let url = draggedImageURL else { return }
        draggedImageURL = nil
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @discardableResult
    func toggleChecklist(at characterIndex: Int) -> Bool {
        let source = string as NSString
        guard characterIndex <= source.length else { return false }
        let paragraph = source.paragraphRange(for: NSRange(location: characterIndex, length: 0))
        let line = source.substring(with: paragraph)
        let replacement: String
        if line.hasPrefix("○ ") {
            replacement = "◉"
        } else if line.hasPrefix("◉ ") {
            replacement = "○"
        } else {
            return false
        }
        let priorSelection = selectedRange()
        insertText(replacement, replacementRange: NSRange(location: paragraph.location, length: 1))
        setSelectedRange(priorSelection)
        return true
    }

    private func toggleChecklist(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        let characterIndex = characterIndexForInsertion(at: point)
        let source = string as NSString
        guard characterIndex < source.length else { return false }
        let paragraph = source.paragraphRange(for: NSRange(location: characterIndex, length: 0))
        guard source.substring(with: paragraph).hasPrefix("○ ")
                || source.substring(with: paragraph).hasPrefix("◉ ") else { return false }
        let glyph = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: paragraph.location, length: 1),
            actualCharacterRange: nil
        )
        var markerRect = layoutManager.boundingRect(forGlyphRange: glyph, in: textContainer)
        markerRect.origin.x += textContainerOrigin.x
        markerRect.origin.y += textContainerOrigin.y
        guard markerRect.insetBy(dx: -5, dy: -3).contains(point) else { return false }
        return toggleChecklist(at: characterIndex)
    }

    private func pasteOptionsMenu() -> NSMenu {
        let pasteboard = NSPasteboard.general
        let hasText = pasteboard.string(forType: .string) != nil
        let hasImage = NSImage(pasteboard: pasteboard) != nil
        let menu = NSMenu(title: "Paste Options")
        let keep = menu.addItem(withTitle: "Paste · Keep Formatting", action: #selector(pasteKeepingFormatting), keyEquivalent: "")
        keep.target = self
        keep.isEnabled = hasText || hasImage
        let match = menu.addItem(withTitle: "Paste · Match Note Style", action: #selector(pasteMatchingStyle), keyEquivalent: "")
        match.target = self
        match.isEnabled = hasText
        let plain = menu.addItem(withTitle: "Paste · Plain Text", action: #selector(pastePlainText), keyEquivalent: "")
        plain.target = self
        plain.isEnabled = hasText
        menu.addItem(.separator())
        let image = menu.addItem(withTitle: "Paste Image", action: #selector(pasteClipboardImage), keyEquivalent: "")
        image.target = self
        image.isEnabled = hasImage
        return menu
    }

    @objc private func pasteKeepingFormatting(_ sender: Any?) {
        paste(sender)
    }

    @objc func pasteMatchingStyle(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        isPastingText = true
        insertText(text, replacementRange: selectedRange())
        isPastingText = false
        if let storage = textStorage { ChecklistMarkerStyle.normalize(in: storage) }
    }

    @objc func pastePlainText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NSParagraphStyle.default
        ]
        isPastingText = true
        insertText(NSAttributedString(string: text, attributes: attributes), replacementRange: selectedRange())
        isPastingText = false
        if let storage = textStorage { ChecklistMarkerStyle.normalize(in: storage) }
    }

    @objc func pasteClipboardImage(_ sender: Any?) {
        guard let image = NSImage(pasteboard: .general),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let attachment = NSTextAttachment(data: png, ofType: "public.png")
        insertText(NSAttributedString(attachment: attachment), replacementRange: selectedRange())
        resizeAttachmentsToFit()
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let source = string as NSString
        guard selection.length == 0, source.length > 0, selection.location <= source.length else {
            super.insertNewline(sender)
            return
        }

        let paragraph = source.paragraphRange(for: selection)
        var contentEnd = NSMaxRange(paragraph)
        while contentEnd > paragraph.location {
            let character = source.character(at: contentEnd - 1)
            guard character == 10 || character == 13 else { break }
            contentEnd -= 1
        }
        let line = source.substring(with: NSRange(
            location: paragraph.location,
            length: contentEnd - paragraph.location
        ))
        guard selection.location == contentEnd else {
            super.insertNewline(sender)
            return
        }

        guard let marker = ListMarker(in: line) else {
            let followsHeading = hasHeadingStyle(before: contentEnd)
            var continuation = contentEnd > paragraph.location
                ? textStorage?.attributes(at: contentEnd - 1, effectiveRange: nil)
                : nil
            continuation?.removeValue(forKey: .attachment)
            continuation?.removeValue(forKey: .link)
            super.insertNewline(sender)
            if followsHeading {
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacing = 2
                typingAttributes = [
                    .font: NSFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
            } else if let continuation {
                typingAttributes = continuation
            }
            return
        }

        if line.utf16.count == marker.length {
            insertText("", replacementRange: NSRange(location: paragraph.location, length: marker.length))
            return
        }

        super.insertNewline(sender)
        insertText(marker.next, replacementRange: selectedRange())
    }

    private func hasHeadingStyle(before location: Int) -> Bool {
        guard location > 0, let storage = textStorage,
              let font = storage.attribute(.font, at: location - 1, effectiveRange: nil) as? NSFont else {
            return false
        }
        let paragraph = storage.attribute(
            .paragraphStyle, at: location - 1, effectiveRange: nil
        ) as? NSParagraphStyle
        let isBold = NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        return [
            (size: CGFloat(26), spacing: CGFloat(6)),
            (size: CGFloat(20), spacing: CGFloat(5)),
            (size: CGFloat(16), spacing: CGFloat(4))
        ].contains {
            abs(font.pointSize - $0.size) < 0.2
                && (isBold || abs((paragraph?.paragraphSpacing ?? 0) - $0.spacing) < 0.5)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53, markedRange().location == NSNotFound else {
            super.keyDown(with: event)
            return
        }
        escapeAction?()
    }

    override func didChangeText() {
        super.didChangeText()
        if let storage = textStorage {
            if isPastingText {
                ChecklistMarkerStyle.normalize(in: storage)
            } else {
                ChecklistMarkerStyle.normalize(in: storage, paragraphAt: selectedRange().location)
            }
        }
        removeUnderlineFromLineBreaks()
        refreshCenteredTrailingSpaceLayout()
    }

    private func removeUnderlineFromLineBreaks() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let source = storage.string as NSString
        let location = min(selectedRange().location, source.length)
        let candidates = [location - 1, location].filter { $0 >= 0 && $0 < source.length }
        for index in candidates where source.character(at: index) == 10
            || source.character(at: index) == 13 {
            if (storage.attribute(.underlineStyle, at: index, effectiveRange: nil) as? Int ?? 0) != 0 {
                storage.removeAttribute(.underlineStyle, range: NSRange(location: index, length: 1))
            }
        }
    }

    func refreshCenteredTrailingSpaceLayout() {
        guard let storage = textStorage else { return }
        if storage.length == 0 {
            resetCenteredTypingTailIndent()
            return
        }
        let source = string as NSString
        let location = min(selectedRange().location, source.length)
        let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
        guard paragraph.length > 0, paragraph.location < storage.length else {
            resetCenteredTypingTailIndent()
            return
        }
        guard
              let current = storage.attribute(
                  .paragraphStyle, at: paragraph.location, effectiveRange: nil
              ) as? NSParagraphStyle,
              current.alignment == .center else { return }

        var contentEnd = NSMaxRange(paragraph)
        while contentEnd > paragraph.location {
            let character = source.character(at: contentEnd - 1)
            guard character == 10 || character == 13 else { break }
            contentEnd -= 1
        }
        var spaceStart = contentEnd
        while spaceStart > paragraph.location && source.character(at: spaceStart - 1) == 32 {
            spaceStart -= 1
        }
        let spaces = NSRange(location: spaceStart, length: contentEnd - spaceStart)
        let width = spaces.length > 0 ? storage.attributedSubstring(from: spaces).size().width : 0
        let tailIndent = width > 0 ? -width : 0
        guard abs(current.tailIndent - tailIndent) > 0.1 else { return }

        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paragraph) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            style.tailIndent = tailIndent
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
    }

    private func resetCenteredTypingTailIndent() {
        var attributes = typingAttributes
        guard let current = attributes[.paragraphStyle] as? NSParagraphStyle,
              current.alignment == .center, current.tailIndent != 0,
              let style = current.mutableCopy() as? NSMutableParagraphStyle else { return }
        style.tailIndent = 0
        attributes[.paragraphStyle] = style
        typingAttributes = attributes
    }

    override func cancelOperation(_ sender: Any?) {
        if markedRange().location != NSNotFound {
            super.cancelOperation(sender)
        } else {
            escapeAction?()
        }
    }
}

private struct ListMarker {
    let length: Int
    let next: String

    init?(in line: String) {
        for (prefix, continuation) in [
            ("• ", "• "), ("- ", "- "), ("○ ", "○ "), ("◉ ", "○ "),
            ("☐ ", "○ "), ("☑ ", "○ ")
        ] where line.hasPrefix(prefix) {
            length = prefix.utf16.count
            next = continuation
            return
        }

        guard let dot = line.firstIndex(of: "."),
              dot != line.startIndex,
              line[line.index(after: dot)...].hasPrefix(" "),
              let number = Int(line[..<dot]),
              line[..<dot].allSatisfy(\.isNumber) else { return nil }
        length = line[..<line.index(dot, offsetBy: 2)].utf16.count
        next = "\(number == Int.max ? number : number + 1). "
    }
}

struct NativeTextEditor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    let richTextData: Data?
    let focusGeneration: Int
    let controller: RichTextEditorController
    let onChange: (UUID, String, Data?) -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = EscapeAwareTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.escapeAction = onEscape
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindPanel = true
        textView.usesFontPanel = false
        textView.setAccessibilityLabel("Note text")
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 13, height: 12)
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.delegate = context.coordinator

        context.coordinator.noteID = noteID
        context.coordinator.lastFocusGeneration = focusGeneration
        context.coordinator.textView = textView
        textView.commitPendingChanges = { [weak coordinator = context.coordinator] in
            coordinator?.commitPendingChanges()
        }
        context.coordinator.applyContent(text: text, richTextData: richTextData)
        scrollView.documentView = textView
        controller.attach(textView)
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.commitPendingChanges()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EscapeAwareTextView else { return }
        context.coordinator.parent = self
        textView.escapeAction = onEscape
        controller.attach(textView)

        let changedNote = context.coordinator.noteID != noteID
        let changedContent = textView.string != text
            || context.coordinator.lastRichTextData != richTextData
        if changedNote { context.coordinator.commitPendingChanges() }
        if changedNote || (changedContent && !context.coordinator.hasPendingChanges
                           && !context.coordinator.isApplyingExternalContent) {
            context.coordinator.noteID = noteID
            context.coordinator.applyContent(text: text, richTextData: richTextData)
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        }

        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: NativeTextEditor
        weak var textView: NSTextView?
        var noteID: UUID?
        var lastFocusGeneration = 0
        var lastRichTextData: Data?
        var isApplyingExternalContent = false
        private var pendingContentSave: DispatchWorkItem?
        private var terminationObserver: NSObjectProtocol?
        var hasPendingChanges: Bool { pendingContentSave != nil }

        init(parent: NativeTextEditor) {
            self.parent = parent
            super.init()
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.commitPendingChanges()
            }
        }

        deinit {
            if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
            pendingContentSave?.cancel()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, textView.window?.firstResponder === textView else { return }
            parent.controller.rememberPaletteSelection()
        }

        func applyContent(text: String, richTextData: Data?) {
            guard let textView, let storage = textView.textStorage else { return }
            isApplyingExternalContent = true

            let attributed = decodedContent(text: text, richTextData: richTextData)
            storage.setAttributedString(attributed)
            (textView as? EscapeAwareTextView)?.resetAttachmentSizeCache()
            (textView as? EscapeAwareTextView)?.resizeAttachmentsToFit()
            textView.typingAttributes = defaultAttributes
            lastRichTextData = richTextData
            isApplyingExternalContent = false
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard !isApplyingExternalContent, let textView,
                  (textView as? EscapeAwareTextView)?.isResizingAttachments != true else { return }
            pendingContentSave?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.commitPendingChanges() }
            pendingContentSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            if editedMask.contains(.editedCharacters) {
                DispatchQueue.main.async { [weak textView] in
                    (textView as? EscapeAwareTextView)?.refreshCenteredTrailingSpaceLayout()
                }
            }
        }

        func commitPendingChanges() {
            guard pendingContentSave != nil, let textView, let textStorage = textView.textStorage else { return }
            pendingContentSave?.cancel()
            pendingContentSave = nil
            let range = NSRange(location: 0, length: textStorage.length)
            var hasImage = false
            if range.length > 0 {
                textStorage.enumerateAttribute(.attachment, in: range) { value, _, stop in
                    if value != nil {
                        hasImage = true
                        stop.pointee = true
                    }
                }
            }
            let data = textView.string.isEmpty
                ? nil
                : hasImage ? textView.rtfd(from: range) : textView.rtf(from: range)
            lastRichTextData = data
            if let noteID { parent.onChange(noteID, textView.string, data) }
        }

        private var defaultAttributes: [NSAttributedString.Key: Any] {
            [
                .font: NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: NSParagraphStyle.default
            ]
        }

        private func decodedContent(text: String, richTextData: Data?) -> NSAttributedString {
            let content: NSMutableAttributedString
            if let richTextData,
               let decoded = NSAttributedString(rtfd: richTextData, documentAttributes: nil)
                    ?? NSAttributedString(rtf: richTextData, documentAttributes: nil),
               decoded.string == text {
                content = NSMutableAttributedString(attributedString: decoded)
            } else {
                content = NSMutableAttributedString(string: text, attributes: defaultAttributes)
            }

            guard content.length > 0 else { return content }
            let fullRange = NSRange(location: 0, length: content.length)
            content.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            content.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                if value == nil {
                    content.addAttribute(
                        .font,
                        value: NSFont.preferredFont(forTextStyle: .body),
                        range: range
                    )
                }
            }
            QuoteParagraphStyle.repairLegacyBlocks(in: content)
            ChecklistMarkerStyle.normalize(in: content)
            InlineFormatBoundary.normalize(in: content)
            return content
        }
    }
}
