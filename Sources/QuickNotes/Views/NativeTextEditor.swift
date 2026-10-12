import AppKit
import SwiftUI

final class EscapeAwareTextView: NSTextView {
    var escapeAction: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > 1
        super.setFrameSize(newSize)
        if widthChanged {
            DispatchQueue.main.async { [weak self] in self?.resizeAttachmentsToFit() }
        }
    }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        resizeAttachmentsToFit()
    }

    func resizeAttachmentsToFit() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let availableWidth = max(80, min(480, bounds.width - textContainerInset.width * 2 - 8))
        let fullRange = NSRange(location: 0, length: storage.length)
        var updates: [(NSTextAttachment, NSRange)] = []
        storage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let image = attachment.image
                ?? attachment.fileWrapper?.regularFileContents.flatMap(NSImage.init(data:))
            let sourceSize = image?.size ?? attachment.bounds.size
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
        storage.beginEditing()
        for (attachment, range) in updates {
            storage.addAttribute(.attachment, value: attachment, range: range)
        }
        storage.endEditing()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.option) {
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            pasteOptionsMenu().popUp(positioning: nil, at: point, in: self)
            return
        }
        if toggleChecklist(at: point) { return }
        super.mouseDown(with: event)
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
        insertText(text, replacementRange: selectedRange())
    }

    @objc func pastePlainText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NSParagraphStyle.default
        ]
        insertText(NSAttributedString(string: text, attributes: attributes), replacementRange: selectedRange())
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
        refreshCenteredTrailingSpaceLayout()
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
    let onChange: (String, Data?) -> Void
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
        context.coordinator.applyContent(text: text, richTextData: richTextData)
        scrollView.documentView = textView
        controller.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EscapeAwareTextView else { return }
        context.coordinator.parent = self
        textView.escapeAction = onEscape
        controller.attach(textView)

        let changedNote = context.coordinator.noteID != noteID
        let changedContent = textView.string != text
            || context.coordinator.lastRichTextData != richTextData
        if changedNote || (changedContent && !context.coordinator.isApplyingExternalContent) {
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

        init(parent: NativeTextEditor) {
            self.parent = parent
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
            guard !isApplyingExternalContent, let textView else { return }
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
            parent.onChange(textView.string, data)
            if editedMask.contains(.editedCharacters) {
                DispatchQueue.main.async { [weak textView] in
                    (textView as? EscapeAwareTextView)?.refreshCenteredTrailingSpaceLayout()
                }
            }
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
            return content
        }
    }
}
