import AppKit
import SwiftUI

final class NoteEditorScrollView: NSScrollView {
    var onFirstLayout: (() -> Void)?
    private var hasInitialLayout = false

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard !hasInitialLayout, newSize.width > 80, newSize.height > 40,
              documentView != nil else { return }
        hasInitialLayout = true
        onFirstLayout?()
    }
}

final class NoteHighlightLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        guard rectCount > 0,
              let storage = textStorage,
              charRange.location >= 2,
              charRange.location < storage.length,
              let highlight = storage.attribute(.backgroundColor, at: charRange.location,
                                                effectiveRange: nil) as? NSColor,
              highlight.isEqual(color) else {
            super.fillBackgroundRectArray(rectArray, count: rectCount,
                                          forCharacterRange: charRange, color: color)
            return
        }

        let source = storage.string as NSString
        let breakIndex = charRange.location - 1
        let previousIndex = breakIndex - 1
        guard Self.isLineBreak(source.character(at: breakIndex)),
              !Self.isLineBreak(source.character(at: previousIndex)),
              let previousHighlight = storage.attribute(.backgroundColor, at: previousIndex,
                                                        effectiveRange: nil) as? NSColor,
              previousHighlight.isEqual(highlight) else {
            super.fillBackgroundRectArray(rectArray, count: rectCount,
                                          forCharacterRange: charRange, color: color)
            return
        }

        var rects = (0..<rectCount).map { rectArray[$0] }
        let inset = min(2, rects[0].height / 8)
        rects[0].origin.y += inset
        rects[0].size.height -= inset
        rects.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            super.fillBackgroundRectArray(baseAddress, count: rectCount,
                                          forCharacterRange: charRange, color: color)
        }
    }

    private static func isLineBreak(_ value: unichar) -> Bool {
        switch value {
        case 10, 11, 12, 13, 0x85, 0x2028, 0x2029: return true
        default: return false
        }
    }
}

final class EscapeAwareTextView: NSTextView {
    var escapeAction: (() -> Void)?
    var isResizingAttachments = false
    var commitPendingChanges: (() -> Void)?
    var editorInteraction: (() -> Void)?
    private var pendingAttachmentResize: DispatchWorkItem?
    private let attachmentSourceSizes = NSMapTable<NSTextAttachment, NSValue>.weakToStrongObjects()
    private var imageDragCandidate: (data: Data, point: NSPoint)?
    private var draggedImageURL: URL?
    private var selectedImageData: Data?
    private var isPastingText = false
    private var lastTableWidth: CGFloat = 0

    func configureInlineTools() {
        usesRolloverButtonForSelection = false
    }

    func resetAttachmentSizeCache() {
        attachmentSourceSizes.removeAllObjects()
        lastTableWidth = 0
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
        let board = NSPasteboard.general
        if ![NSPasteboard.PasteboardType.rtfd, .rtf, .html].contains(where: { board.data(forType: $0) != nil }),
           NSImage(pasteboard: board) != nil {
            pasteClipboardImage(sender)
            return
        }
        if let content = NoteRichContent.clipboardContent(from: .general) {
            insertPastedContent(content)
            return
        }
        if NSImage(pasteboard: .general) != nil {
            pasteClipboardImage(sender)
            return
        }
        isPastingText = true
        super.paste(sender)
        isPastingText = false
        if let storage = textStorage { ListMarkerAppearance.normalize(in: storage) }
        resizeAttachmentsToFit(forceTableLayout: true)
    }

    func insertPastedContent(_ content: NSMutableAttributedString) {
        var imageLocations: [Int] = []
        if content.length > 0 {
            content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
                if value != nil { imageLocations.append(range.location) }
            }
        }
        for location in imageLocations.reversed() {
            let style = content.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            if style?.textBlocks.contains(where: { $0 is NSTextTableBlock }) == true { continue }
            let source = content.string as NSString
            if location + 1 < source.length && source.character(at: location + 1) != 10 {
                content.insert(NSAttributedString(string: "\n", attributes: NoteRichContent.bodyAttributes),
                               at: location + 1)
            }
            if location > 0 && source.character(at: location - 1) != 10 {
                content.insert(NSAttributedString(string: "\n", attributes: NoteRichContent.bodyAttributes), at: location)
            }
        }
        NoteRichContent.normalize(content)
        let selection = selectedRange()
        let source = string as NSString
        let hasAttachment = content.string.contains("\u{FFFC}")
        var hasTable = false
        content.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: content.length)) { value, _, stop in
            if (value as? NSParagraphStyle)?.textBlocks.contains(where: { $0 is NSTextTableBlock }) == true {
                hasTable = true
                stop.pointee = true
            }
        }
        if hasAttachment || hasTable {
            if selection.location > 0 && source.character(at: selection.location - 1) != 10 {
                content.insert(NSAttributedString(string: "\n", attributes: NoteRichContent.bodyAttributes), at: 0)
            }
            if !content.string.hasSuffix("\n") {
                content.append(NSAttributedString(string: "\n", attributes: NoteRichContent.bodyAttributes))
            }
            if let style = content.attribute(.paragraphStyle, at: content.length - 1,
                effectiveRange: nil) as? NSParagraphStyle, !style.textBlocks.isEmpty {
                content.append(NSAttributedString(string: "\n", attributes: NoteRichContent.bodyAttributes))
            }
        }
        isPastingText = true
        insertText(content, replacementRange: selection)
        isPastingText = false
        if hasAttachment || hasTable { typingAttributes = NoteRichContent.bodyAttributes }
        resizeAttachmentsToFit(forceTableLayout: true)
    }

    func resizeAttachmentsToFit(forceTableLayout: Bool = false) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let tableWidth = max(80, bounds.width - textContainerInset.width * 2 - 10)
        if forceTableLayout || abs(lastTableWidth - tableWidth) > 0.5 {
            lastTableWidth = tableWidth
            if NoteTable.normalize(storage, width: tableWidth) {
                layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length),
                                                actualCharacterRange: nil)
            }
        }
        let availableWidth = max(80, min(480, bounds.width - textContainerInset.width * 2 - 8))
        let fullRange = NSRange(location: 0, length: storage.length)
        var updates: [(NSTextAttachment, NSRange)] = []
        storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let sourceSize: NSSize
            if let cached = attachmentSourceSizes.object(forKey: attachment) {
                sourceSize = cached.sizeValue
            } else {
                let image = attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:))
                    ?? attachment.image
                sourceSize = image?.size ?? attachment.bounds.size
                attachmentSourceSizes.setObject(NSValue(size: sourceSize), forKey: attachment)
            }
            guard sourceSize.width > 0, sourceSize.height > 0 else { return }
            let style = storage.attribute(.paragraphStyle, at: range.location,
                                          effectiveRange: nil) as? NSParagraphStyle
            let cellWidth = style?.textBlocks.compactMap { $0 as? NSTextTableBlock }
                .map { max(1, $0.value(for: .width)) }.min() ?? availableWidth
            let scale = min(1, min(availableWidth, cellWidth) / sourceSize.width, 360 / sourceSize.height)
            let target = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            if abs(attachment.bounds.width - target.width) > 0.5
                || abs(attachment.bounds.height - target.height) > 0.5 {
                attachment.bounds = NSRect(origin: .zero, size: target)
                if let source = attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:))
                    ?? attachment.image,
                   let display = source.copy() as? NSImage {
                    display.size = target
                    attachment.attachmentCell = NSTextAttachmentCell(imageCell: display)
                }
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
        var notifyInteraction = true
        defer {
            if notifyInteraction {
                let interaction = editorInteraction
                DispatchQueue.main.async { interaction?() }
            }
        }
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option) {
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            pasteOptionsMenu().popUp(positioning: nil, at: point, in: self)
            return
        }
        if toggleChecklist(at: point) { return }
        if let image = imageData(at: point) {
            notifyInteraction = false
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
        if imageDragCandidate != nil { editorInteraction?() }
        imageDragCandidate = nil
        super.mouseUp(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let image = imageData(at: point) else {
            let menu = super.menu(for: event) ?? NSMenu()
            menu.addItem(.separator())
            let paste = NSMenuItem(title: "Paste Options", action: nil, keyEquivalent: "")
            paste.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            paste.submenu = pasteOptionsMenu()
            menu.addItem(paste)
            return menu
        }
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
        } else if range.length > 0, let storage = textStorage, NSMaxRange(range) <= storage.length {
            NoteRichContent.write(storage.attributedSubstring(from: range), to: .general)
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
            let scale = min(1, 180 / max(1, preview.size.width), 180 / max(1, preview.size.height))
            let size = NSSize(width: preview.size.width * scale, height: preview.size.height * scale)
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
        editorInteraction?()
        guard let url = draggedImageURL else { return }
        draggedImageURL = nil
        // Some destinations retain a file URL and read it after the drop has completed.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 86_400) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @discardableResult
    func toggleChecklist(at characterIndex: Int) -> Bool {
        let source = string as NSString
        guard characterIndex <= source.length else { return false }
        let paragraph = source.paragraphRange(for: NSRange(location: characterIndex, length: 0))
        let rawLine = source.substring(with: paragraph)
        let line = ListPrefix.visibleLine(rawLine)
        let replacement: String
        if line.hasPrefix("○ ") {
            replacement = "◉"
        } else if line.hasPrefix("◉ ") {
            replacement = "○"
        } else {
            return false
        }
        let priorSelection = selectedRange()
        insertText(replacement, replacementRange: NSRange(location: paragraph.location + ListPrefix.invisibleLength(in: rawLine), length: 1))
        setSelectedRange(priorSelection)
        return true
    }

    private func toggleChecklist(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        let characterIndex = characterIndexForInsertion(at: point)
        let source = string as NSString
        guard characterIndex < source.length else { return false }
        let paragraph = source.paragraphRange(for: NSRange(location: characterIndex, length: 0))
        let rawLine = source.substring(with: paragraph)
        let line = ListPrefix.visibleLine(rawLine)
        guard line.hasPrefix("○ ") || line.hasPrefix("◉ ") else { return false }
        let glyph = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: paragraph.location + ListPrefix.invisibleLength(in: rawLine), length: 1),
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
            || [.rtf, .rtfd, .html].contains(where: { pasteboard.data(forType: $0) != nil })
        let hasImage = NSImage(pasteboard: pasteboard) != nil
        let menu = NSMenu(title: "Paste Options")
        let keep = menu.addItem(withTitle: "Keep Formatting", action: #selector(pasteKeepingFormatting), keyEquivalent: "")
        keep.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        keep.target = self
        keep.isEnabled = hasText || hasImage
        let match = menu.addItem(withTitle: "Match Note Style", action: #selector(pasteMatchingStyle), keyEquivalent: "")
        match.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        match.target = self
        match.isEnabled = hasText
        let plain = menu.addItem(withTitle: "Plain Text", action: #selector(pastePlainText), keyEquivalent: "")
        plain.image = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: nil)
        plain.target = self
        plain.isEnabled = hasText
        menu.addItem(.separator())
        let image = menu.addItem(withTitle: "Paste Image", action: #selector(pasteClipboardImage), keyEquivalent: "")
        image.target = self
        image.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        image.isEnabled = hasImage
        return menu
    }

    @objc private func pasteKeepingFormatting(_ sender: Any?) {
        guard let content = NoteRichContent.clipboardContent(from: .general, standardizeFont: false) else {
            paste(sender)
            return
        }
        insertPastedContent(content)
    }

    @objc func pasteMatchingStyle(_ sender: Any?) {
        guard let content = NoteRichContent.clipboardContent(from: .general) else { return }
        let full = NSRange(location: 0, length: content.length)
        content.addAttribute(.font, value: typingAttributes[.font]
            ?? NSFont.preferredFont(forTextStyle: .body), range: full)
        content.addAttribute(.foregroundColor, value: typingAttributes[.foregroundColor]
            ?? NSColor.labelColor, range: full)
        insertPastedContent(content)
    }

    @objc func pastePlainText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string)
            ?? NoteRichContent.clipboardContent(from: .general)?.string else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NSParagraphStyle.default
        ]
        isPastingText = true
        insertText(NSAttributedString(string: text, attributes: attributes), replacementRange: selectedRange())
        isPastingText = false
        if let storage = textStorage { ListMarkerAppearance.normalize(in: storage) }
    }

    @objc func pasteClipboardImage(_ sender: Any?) {
        guard let image = NSImage(pasteboard: .general),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let attachment = NSTextAttachment(data: png, ofType: "public.png")
        insertPastedContent(NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment)))
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let source = string as NSString
        guard selection.length == 0, source.length > 0, selection.location <= source.length else {
            super.insertNewline(sender)
            return
        }

        let paragraph = source.paragraphRange(for: selection)
        if selection.location > 0,
           textStorage?.attribute(.attachment, at: selection.location - 1, effectiveRange: nil) != nil {
            super.insertNewline(sender)
            typingAttributes = NoteRichContent.bodyAttributes
            return
        }
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
            if let storage = textStorage, paragraph.location < storage.length {
                ListMarkerAppearance.clearIndent(in: storage, paragraphAt: paragraph.location)
            }
            if let current = typingAttributes[.paragraphStyle] as? NSParagraphStyle {
                var attributes = typingAttributes
                let style = current.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                style.headIndent = 0
                style.firstLineHeadIndent = 0
                attributes[.paragraphStyle] = style
                typingAttributes = attributes
            }
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
                ListMarkerAppearance.normalize(in: storage)
            } else {
                ListMarkerAppearance.normalize(in: storage, paragraphAt: selectedRange().location)
                ListMarkerAppearance.clearOrphanedIndent(in: storage,
                                                         paragraphAt: selectedRange().location)
            }
        }
        removeInlineFormattingFromLineBreaks()
        refreshCenteredTrailingSpaceLayout()
    }

    private func removeInlineFormattingFromLineBreaks() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let source = storage.string as NSString
        let location = min(selectedRange().location, source.length)
        let candidates = [location - 1, location].filter { $0 >= 0 && $0 < source.length }
        for index in candidates where source.character(at: index) == 10
            || source.character(at: index) == 11 || source.character(at: index) == 12
            || source.character(at: index) == 13 || source.character(at: index) == 0x85
            || source.character(at: index) == 0x2028
            || source.character(at: index) == 0x2029 || source.character(at: index) == 0xFFFC
            || source.character(at: index) == 0x200B || source.character(at: index) == 0xFEFF {
            let range = NSRange(location: index, length: 1)
            for key in [NSAttributedString.Key.underlineStyle, .underlineColor,
                        .strikethroughStyle, .strikethroughColor, .backgroundColor, .link] {
                if storage.attribute(key, at: index, effectiveRange: nil) != nil {
                    storage.removeAttribute(key, range: range)
                }
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

    init?(in rawLine: String) {
        let line = ListPrefix.visibleLine(rawLine)
        let leading = ListPrefix.invisibleLength(in: rawLine)
        for (prefix, continuation) in [
            ("• ", "• "), ("- ", "- "), ("○ ", "○ "), ("◉ ", "○ "),
            ("☐ ", "○ "), ("☑ ", "○ ")
        ] where line.hasPrefix(prefix) {
            length = leading + prefix.utf16.count
            next = continuation
            return
        }

        guard let dot = line.firstIndex(of: "."),
              dot != line.startIndex,
              line[line.index(after: dot)...].hasPrefix(" "),
              let number = Int(line[..<dot]),
              line[..<dot].allSatisfy(\.isNumber) else { return nil }
        length = leading + line[..<line.index(dot, offsetBy: 2)].utf16.count
        next = "\(number == Int.max ? number : number + 1). "
    }
}

struct NativeTextEditor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    let richTextData: Data?
    let focusGeneration: Int
    let showsVerticalScroller: Bool
    let controller: RichTextEditorController
    let onChange: (UUID, String, Data?) -> Void
    let onEscape: () -> Void
    var rememberReadingPosition = true
    var readingPositionDefaults: UserDefaults = .standard
    var onEditorInteraction: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NoteEditorScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.verticalScroller?.isHidden = !showsVerticalScroller

        let storage = NSTextStorage()
        let layoutManager = NoteHighlightLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        layoutManager.addTextContainer(container)
        let textView = EscapeAwareTextView(frame: .zero, textContainer: container)
        textView.configureInlineTools()
        textView.delegate = context.coordinator
        textView.escapeAction = onEscape
        textView.editorInteraction = onEditorInteraction
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
        scrollView.onFirstLayout = { [weak coordinator = context.coordinator] in
            coordinator?.restoreReadingPosition()
        }
        scrollView.documentView = textView
        context.coordinator.observeScrolling(in: scrollView)
        controller.attach(textView)
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.commitPendingChanges()
        coordinator.saveReadingPosition()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EscapeAwareTextView else { return }
        if scrollView.verticalScroller?.isHidden == showsVerticalScroller {
            scrollView.verticalScroller?.isHidden = !showsVerticalScroller
        }
        context.coordinator.parent = self
        textView.escapeAction = onEscape
        textView.editorInteraction = onEditorInteraction
        controller.attach(textView)

        let changedNote = context.coordinator.noteID != noteID
        let changedContent = textView.string != text
            || context.coordinator.lastRichTextData != richTextData
        if changedNote {
            context.coordinator.commitPendingChanges()
            context.coordinator.saveReadingPosition()
        }
        if changedNote || (changedContent && !context.coordinator.hasPendingChanges
                           && !context.coordinator.isApplyingExternalContent) {
            context.coordinator.noteID = noteID
            context.coordinator.applyContent(text: text, richTextData: richTextData)
            textView.undoManager?.removeAllActions()
            context.coordinator.restoreReadingPosition()
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
        private var formattingRefreshQueued = false
        private var scrollObserver: NSObjectProtocol?
        private var pendingPositionSave: DispatchWorkItem?
        private(set) var restoringPosition = false
        private var restorationRevision = 0
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
                self?.saveReadingPosition()
            }
        }

        deinit {
            if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
            pendingContentSave?.cancel()
            pendingPositionSave?.cancel()
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func observeScrolling(in scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
            ) { [weak self] _ in
                guard let self, !self.restoringPosition else { return }
                self.pendingPositionSave?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.saveReadingPosition() }
                self.pendingPositionSave = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        }

        func saveReadingPosition() {
            pendingPositionSave?.cancel()
            pendingPositionSave = nil
            guard !restoringPosition, !isApplyingExternalContent, parent.rememberReadingPosition,
                  let id = noteID, let textView, let scroll = textView.enclosingScrollView else { return }
            let y = max(0, scroll.contentView.bounds.minY)
            var position = NoteReadingPosition(location: textView.selectedRange().location, verticalOffset: y)
            if let layout = textView.layoutManager, let container = textView.textContainer,
               layout.numberOfGlyphs > 0 {
                let glyph = min(layout.numberOfGlyphs - 1, layout.glyphIndex(
                    for: NSPoint(x: 0, y: max(0, y - textView.textContainerOrigin.y)), in: container))
                position.anchor = layout.characterIndexForGlyph(at: glyph)
                position.anchorOffset = y - layout.lineFragmentRect(forGlyphAt: glyph,
                    effectiveRange: nil).minY - textView.textContainerOrigin.y
            }
            position.atBottom = textView.bounds.height > scroll.contentSize.height
                && abs(y - max(0, textView.bounds.height - scroll.contentSize.height)) < 2
            NoteReadingPositions.save(position, id: id, defaults: parent.readingPositionDefaults)
        }

        func restoreReadingPosition() {
            guard let id = noteID, let textView else { return }
            restorationRevision &+= 1
            let revision = restorationRevision
            pendingPositionSave?.cancel()
            let position = parent.rememberReadingPosition
                ? NoteReadingPositions.read(id, defaults: parent.readingPositionDefaults) : nil
            restoringPosition = true
            textView.setSelectedRange(NSRange(location: min(position?.location ?? 0,
                                                            textView.string.utf16.count), length: 0))
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, self.noteID == id, self.restorationRevision == revision, let textView,
                      let scroll = textView.enclosingScrollView else { return }
                textView.setFrameOrigin(.zero)
                scroll.layoutSubtreeIfNeeded()
                if let container = textView.textContainer, let layout = textView.layoutManager {
                    layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count))
                    let height = ceil(layout.usedRect(for: container).maxY + textView.textContainerInset.height * 2)
                    textView.setFrameSize(NSSize(width: textView.frame.width,
                                                height: max(height, scroll.contentSize.height)))
                }
                let maxY = max(0, textView.bounds.height - scroll.contentSize.height)
                var y = position?.verticalOffset ?? 0
                if let anchor = position?.anchor, let layout = textView.layoutManager,
                   anchor < textView.string.utf16.count {
                    let glyph = layout.glyphIndexForCharacter(at: anchor)
                    y = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
                        + textView.textContainerOrigin.y + (position?.anchorOffset ?? 0)
                }
                if position?.atBottom == true { y = maxY }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
                scroll.reflectScrolledClipView(scroll.contentView)
                if maxY == 0 { scroll.verticalScroller?.floatValue = 0 }
                textView.needsDisplay = true
                scroll.contentView.needsDisplay = true
                self.restoringPosition = false
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, textView.window?.firstResponder === textView else { return }
            textView.setNeedsDisplay(textView.visibleRect)
            textView.enclosingScrollView?.contentView.needsDisplay = true
            parent.controller.noteSelectionChanged()
            parent.controller.rememberPaletteSelection()
            scheduleFormattingRefresh()
            if !restoringPosition { saveReadingPosition() }
        }

        private func scheduleFormattingRefresh() {
            guard !formattingRefreshQueued else { return }
            formattingRefreshQueued = true
            DispatchQueue.main.async { [weak self] in
                self?.formattingRefreshQueued = false
                self?.parent.controller.refreshFormattingState()
            }
        }

        func applyContent(text: String, richTextData: Data?) {
            guard let textView, let storage = textView.textStorage else { return }
            isApplyingExternalContent = true

            let attributed = NoteRichContent.decode(text: text, data: richTextData)
            storage.setAttributedString(attributed)
            (textView as? EscapeAwareTextView)?.resetAttachmentSizeCache()
            (textView as? EscapeAwareTextView)?.resizeAttachmentsToFit()
            textView.typingAttributes = defaultAttributes
            MainActor.assumeIsolated { parent.controller.noteTextChanged() }
            lastRichTextData = richTextData
            isApplyingExternalContent = false
            scheduleFormattingRefresh()
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard !isApplyingExternalContent, let textView,
                  (textView as? EscapeAwareTextView)?.isResizingAttachments != true else { return }
            scheduleFormattingRefresh()
            pendingContentSave?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.commitPendingChanges() }
            pendingContentSave = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            if editedMask.contains(.editedCharacters) {
                MainActor.assumeIsolated { parent.controller.noteTextChanged() }
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

    }
}
