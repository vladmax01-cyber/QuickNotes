import AppKit

enum QuoteParagraphStyle {
    static let indent: CGFloat = 18

    static func isQuoted(_ style: NSParagraphStyle?) -> Bool {
        guard let style else { return false }
        return !style.textBlocks.isEmpty
            || (style.headIndent >= indent - 0.5 && style.firstLineHeadIndent >= indent - 0.5)
    }

    static func updated(_ source: NSParagraphStyle?, quoted: Bool) -> NSMutableParagraphStyle {
        let style = source?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        style.textBlocks = []
        style.headIndent = quoted ? indent : 0
        style.firstLineHeadIndent = quoted ? indent : 0
        return style
    }

    @discardableResult
    static func repairLegacyBlocks(in content: NSMutableAttributedString) -> Bool {
        guard content.length > 0 else { return false }
        let range = NSRange(location: 0, length: content.length)
        var repairs: [(NSRange, NSMutableParagraphStyle)] = []
        content.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
            guard let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty else { return }
            repairs.append((subrange, updated(style, quoted: true)))
        }
        for (subrange, style) in repairs {
            content.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
        return !repairs.isEmpty
    }
}

enum ChecklistMarkerStyle {
    private static let font = NSFont.systemFont(ofSize: 18, weight: .regular)

    static func normalize(in content: NSMutableAttributedString) {
        let source = content.string as NSString
        var location = 0
        while location < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            normalize(in: content, paragraphAt: location)
            location = NSMaxRange(paragraph)
        }
    }

    static func normalize(in content: NSMutableAttributedString, paragraphAt location: Int) {
        let source = content.string as NSString
        guard source.length > 0, location <= source.length else { return }
        let safeLocation = min(location, source.length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: safeLocation, length: 0))
        guard paragraph.length >= 2 else { return }
        let prefix = source.substring(with: NSRange(location: paragraph.location, length: 2))
        guard prefix == "○ " || prefix == "◉ " else { return }
        let marker = NSRange(location: paragraph.location, length: 1)
        let existing = content.attribute(.font, at: marker.location, effectiveRange: nil) as? NSFont
        if existing?.fontName != font.fontName || abs((existing?.pointSize ?? 0) - font.pointSize) > 0.1 {
            content.addAttribute(.font, value: font, range: marker)
        }
        content.removeAttribute(.underlineStyle, range: marker)
        content.removeAttribute(.strikethroughStyle, range: marker)
        content.removeAttribute(.backgroundColor, range: marker)
    }
}

enum InlineFormatBoundary {
    static func normalize(in content: NSMutableAttributedString) {
        let source = content.string as NSString
        for index in 0..<source.length where source.character(at: index) == 10
            || source.character(at: index) == 13 {
            let range = NSRange(location: index, length: 1)
            content.removeAttribute(.underlineStyle, range: range)
            content.removeAttribute(.strikethroughStyle, range: range)
            content.removeAttribute(.backgroundColor, range: range)
        }
    }
}

@MainActor
final class RichTextEditorController {
    enum TextStyle: String, CaseIterable {
        case title = "Title"
        case heading = "Heading"
        case subheading = "Subheading"
        case body = "Body"
        case monostyled = "Monostyled"
    }

    enum ListStyle {
        case bulleted
        case dashed
        case numbered
        case checklist
        case blockQuote
    }

    enum HighlightColor: String, CaseIterable, Identifiable {
        case yellow = "Yellow"
        case mint = "Mint"
        case blue = "Blue"
        case pink = "Pink"
        case purple = "Purple"

        var id: String { rawValue }

        var nsColor: NSColor {
            let color: NSColor
            switch self {
            case .yellow: color = .systemYellow
            case .mint: color = .systemMint
            case .blue: color = .systemCyan
            case .pink: color = .systemPink
            case .purple: color = .systemPurple
            }
            return color.withAlphaComponent(0.48)
        }
    }

    weak var textView: NSTextView?
    private var paletteSelection: NSRange?
    private(set) var preferredHighlightColor: HighlightColor = .yellow

    func attach(_ textView: NSTextView) {
        self.textView = textView
    }

    func rememberPaletteSelection() {
        paletteSelection = textView?.selectedRange()
    }

    func ensurePaletteSelection() {
        if paletteSelection == nil {
            paletteSelection = textView?.selectedRange()
        }
    }

    func restorePaletteSelection() {
        guard let textView, let paletteSelection,
              NSMaxRange(paletteSelection) <= textView.string.utf16.count else { return }
        if textView.selectedRange() != paletteSelection {
            textView.setSelectedRange(paletteSelection)
        }
    }

    func clearPaletteSelection() {
        paletteSelection = nil
    }

    func revealPaletteResult() {
        guard let textView, let paletteSelection else { return }
        let result = NSRange(
            location: min(NSMaxRange(paletteSelection), textView.string.utf16.count),
            length: 0
        )
        if textView.selectedRange() != result {
            textView.setSelectedRange(result)
        }
    }

    func apply(_ style: TextStyle) {
        guard let textView else { return }
        if NSFontPanel.shared.isVisible {
            NSFontPanel.shared.orderOut(nil)
        }
        let font: NSFont
        let paragraphSpacing: CGFloat

        switch style {
        case .title:
            font = .systemFont(ofSize: 26, weight: .bold)
            paragraphSpacing = 6
        case .heading:
            font = .systemFont(ofSize: 20, weight: .semibold)
            paragraphSpacing = 5
        case .subheading:
            font = .systemFont(ofSize: 16, weight: .semibold)
            paragraphSpacing = 4
        case .body:
            font = .preferredFont(forTextStyle: .body)
            paragraphSpacing = 2
        case .monostyled:
            font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            paragraphSpacing = 2
        }

        let clearsQuoteIndent = style == .title || style == .heading || style == .subheading
        let range = paragraphRange(in: textView)
        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[.font] = font
            attributes[.foregroundColor] = NSColor.labelColor
            let existing = attributes[.paragraphStyle] as? NSParagraphStyle
            let paragraph = clearsQuoteIndent
                ? QuoteParagraphStyle.updated(existing, quoted: false)
                : (existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle())
            paragraph.paragraphSpacing = paragraphSpacing
            attributes[.paragraphStyle] = paragraph
            textView.typingAttributes = attributes
            return
        }

        guard let storage = textView.textStorage else { return }
        let before = NSAttributedString(attributedString: storage)
        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
            let existing = value as? NSParagraphStyle
            let paragraph = clearsQuoteIndent
                ? QuoteParagraphStyle.updated(existing, quoted: false)
                : (existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle())
            paragraph.paragraphSpacing = paragraphSpacing
            storage.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
        }
        storage.endEditing()
        registerFormattingUndo(before, in: textView, name: "Change Text Style")
    }

    func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    func toggleUnderline() {
        toggleIntegerAttribute(.underlineStyle)
    }

    func toggleStrikethrough() {
        toggleIntegerAttribute(.strikethroughStyle)
    }

    func toggleHighlight() {
        guard let textView else { return }
        let range = highlightRange(in: textView)
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if attributes[.backgroundColor] != nil {
                attributes.removeValue(forKey: .backgroundColor)
            } else {
                attributes[.backgroundColor] = preferredHighlightColor.nsColor
            }
            textView.typingAttributes = attributes
            return
        }

        guard let storage = textView.textStorage else { return }
        let before = NSAttributedString(attributedString: storage)
        var fullyHighlighted = true
        storage.enumerateAttribute(.backgroundColor, in: range) { value, _, stop in
            if value == nil {
                fullyHighlighted = false
                stop.pointee = true
            }
        }
        storage.beginEditing()
        if fullyHighlighted {
            storage.removeAttribute(.backgroundColor, range: range)
        } else {
            storage.addAttribute(
                .backgroundColor,
                value: preferredHighlightColor.nsColor,
                range: range
            )
        }
        storage.endEditing()
        registerFormattingUndo(before, in: textView, name: "Highlight")
    }

    func applyHighlight(_ color: HighlightColor) {
        preferredHighlightColor = color
        setHighlight(color.nsColor)
    }

    func removeHighlight() {
        setHighlight(nil)
    }

    private func setHighlight(_ color: NSColor?) {
        guard let textView else { return }
        let range = highlightRange(in: textView)
        if range.length == 0 {
            var attributes = textView.typingAttributes
            attributes[.backgroundColor] = color
            textView.typingAttributes = attributes
            return
        }
        guard let storage = textView.textStorage else { return }
        let before = NSAttributedString(attributedString: storage)
        if let color {
            storage.addAttribute(.backgroundColor, value: color, range: range)
        } else {
            storage.removeAttribute(.backgroundColor, range: range)
        }
        registerFormattingUndo(before, in: textView, name: "Highlight")
    }

    private func highlightRange(in textView: NSTextView) -> NSRange {
        let selection = textView.selectedRange()
        return selection.length == 0
            ? wordRange(at: selection.location, in: textView.string)
            : selection
    }

    private func wordRange(at location: Int, in text: String) -> NSRange {
        let source = text as NSString
        guard source.length > 0 else { return NSRange(location: location, length: 0) }
        let caret = min(location, source.length)
        var result = NSRange(location: caret, length: 0)
        source.enumerateSubstrings(
            in: NSRange(location: 0, length: source.length),
            options: .byWords
        ) { _, wordRange, _, stop in
            if wordRange.location <= caret && caret <= NSMaxRange(wordRange) {
                result = wordRange
                stop.pointee = true
            }
        }
        return result
    }

    func applyList(_ style: ListStyle) {
        guard let textView, let storage = textView.textStorage else { return }
        let before = NSAttributedString(attributedString: storage)
        if case .blockQuote = style {
            toggleBlockQuote(in: textView, storage: storage)
            registerFormattingUndo(before, in: textView, name: "Block Quote")
            return
        }
        let source = textView.string as NSString
        let selection = textView.selectedRange()
        if case .checklist = style, selection.length == 0 {
            let paragraph = source.length == 0
                ? NSRange(location: 0, length: 0)
                : source.paragraphRange(for: NSRange(location: min(selection.location, source.length), length: 0))
            let line = source.substring(with: contentRange(for: paragraph, in: source))
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                storage.replaceCharacters(in: NSRange(location: paragraph.location, length: 0), with: "○ ")
                ChecklistMarkerStyle.normalize(in: storage, paragraphAt: paragraph.location)
                textView.setSelectedRange(NSRange(location: paragraph.location + 2, length: 0))
                registerFormattingUndo(before, in: textView, name: "Change List")
                return
            }
        }
        let selectedParagraphs = lineRanges(in: source, selection: selection)
        guard !selectedParagraphs.isEmpty else { return }
        let selectedRange = NSRange(
            location: selectedParagraphs[0].location,
            length: NSMaxRange(selectedParagraphs[selectedParagraphs.count - 1]) - selectedParagraphs[0].location
        )

        let nonemptyParagraphs = selectedParagraphs.filter { range in
            let line = source.substring(with: contentRange(for: range, in: source))
            let content = (line as NSString).substring(from: recognizedPrefixLength(in: line))
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let allAlreadyStyled = !nonemptyParagraphs.isEmpty && nonemptyParagraphs.allSatisfy { range in
            let line = source.substring(with: contentRange(for: range, in: source))
            return hasPrefix(for: style, in: line)
        }

        var ordinal = 0
        let ordinals = selectedParagraphs.map { range in
            let line = source.substring(with: contentRange(for: range, in: source))
            let content = (line as NSString).substring(from: recognizedPrefixLength(in: line))
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ordinal += 1 }
            return ordinal
        }
        var totalDelta = 0
        storage.beginEditing()
        for (index, paragraphRange) in selectedParagraphs.enumerated().reversed() {
            let contentRange = contentRange(for: paragraphRange, in: source)
            let line = source.substring(with: contentRange)
            let oldPrefixLength = recognizedPrefixLength(in: line)
            let oldPrefixRange = NSRange(location: contentRange.location, length: oldPrefixLength)
            let content = (line as NSString).substring(from: oldPrefixLength)
            let isEmptyParagraph = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let replacement = allAlreadyStyled || isEmptyParagraph ? "" : prefix(for: style, index: ordinals[index] - 1)
            if oldPrefixLength == 0 && replacement.isEmpty { continue }
            storage.replaceCharacters(in: oldPrefixRange, with: replacement)
            totalDelta += replacement.utf16.count - oldPrefixLength
        }
        storage.endEditing()

        ChecklistMarkerStyle.normalize(in: storage)

        let adjustedLength = max(0, selectedRange.length + totalDelta)
        textView.setSelectedRange(NSRange(location: selectedRange.location, length: adjustedLength))
        registerFormattingUndo(before, in: textView, name: "Change List")
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        guard let textView else { return }
        var typingAttributes = textView.typingAttributes
        let typingStyle = QuoteParagraphStyle.updated(
            typingAttributes[.paragraphStyle] as? NSParagraphStyle, quoted: false
        )
        typingStyle.alignment = alignment
        typingStyle.tailIndent = 0
        typingAttributes[.paragraphStyle] = typingStyle

        let range = paragraphRange(in: textView)
        guard range.length > 0, let storage = textView.textStorage else {
            textView.typingAttributes = typingAttributes
            return
        }
        let before = NSAttributedString(attributedString: storage)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
            let style = QuoteParagraphStyle.updated(value as? NSParagraphStyle, quoted: false)
            style.alignment = alignment
            style.tailIndent = 0
            storage.addAttribute(.paragraphStyle, value: style, range: subrange)
        }
        storage.endEditing()
        textView.typingAttributes = typingAttributes
        registerFormattingUndo(before, in: textView, name: "Change Alignment")
    }

    private func toggleBlockQuote(in textView: NSTextView, storage: NSTextStorage) {
        let source = textView.string as NSString
        let paragraphs = lineRanges(in: source, selection: textView.selectedRange())
        guard !paragraphs.isEmpty else {
            var attributes = textView.typingAttributes
            let style = (attributes[.paragraphStyle] as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            attributes[.paragraphStyle] = QuoteParagraphStyle.updated(
                style, quoted: !QuoteParagraphStyle.isQuoted(style)
            )
            textView.typingAttributes = attributes
            return
        }

        let allQuoted = paragraphs.allSatisfy { paragraph in
            guard paragraph.location < storage.length else { return false }
            let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            return QuoteParagraphStyle.isQuoted(style)
        }
        let selection = textView.selectedRange()
        var removedPrefixes: [NSRange] = []
        storage.beginEditing()
        for paragraph in paragraphs.reversed() {
            var adjusted = paragraph
            if !allQuoted {
                let line = source.substring(with: contentRange(for: paragraph, in: source))
                let legacyLength = line.hasPrefix("> ") ? 2 : line.hasPrefix(">") ? 1 : 0
                if legacyLength > 0 {
                    storage.replaceCharacters(
                        in: NSRange(location: paragraph.location, length: legacyLength),
                        with: ""
                    )
                    adjusted.length -= legacyLength
                    removedPrefixes.append(NSRange(location: paragraph.location, length: legacyLength))
                }
            }
            guard adjusted.length > 0, adjusted.location < storage.length else { continue }
            let existing = storage.attribute(.paragraphStyle, at: adjusted.location, effectiveRange: nil) as? NSParagraphStyle
            let style = QuoteParagraphStyle.updated(existing, quoted: !allQuoted)
            storage.addAttribute(.paragraphStyle, value: style, range: adjusted)
        }
        storage.endEditing()

        func adjustedPosition(_ position: Int) -> Int {
            position - removedPrefixes.reduce(0) { count, prefix in
                count + max(0, min(prefix.length, position - prefix.location))
            }
        }
        let adjustedLocation = min(adjustedPosition(selection.location), storage.length)
        let adjustedEnd = min(adjustedPosition(NSMaxRange(selection)), storage.length)
        textView.setSelectedRange(NSRange(location: adjustedLocation, length: max(0, adjustedEnd - adjustedLocation)))
    }

    func changeFontSize(by delta: CGFloat) {
        transformFont { font in
            let size = min(72, max(9, font.pointSize + delta))
            return NSFontManager.shared.convert(font, toSize: size)
        }
    }

    func setFontSize(_ size: CGFloat) {
        guard (9...72).contains(size) else { return }
        transformFont { NSFontManager.shared.convert($0, toSize: size) }
    }

    var currentFontSize: Int {
        guard let textView else { return 13 }
        let selection = textView.window?.firstResponder === textView
            ? textView.selectedRange()
            : (paletteSelection ?? textView.selectedRange())
        let source = textView.string as NSString
        let location = min(selection.location, source.length)
        let characterIndex: Int?
        if selection.length > 0 && location < source.length {
            characterIndex = location
        } else if location > 0 && source.character(at: location - 1) != 10
                    && source.character(at: location - 1) != 13 {
            characterIndex = location - 1
        } else if location < source.length && source.character(at: location) != 10
                    && source.character(at: location) != 13 {
            characterIndex = location
        } else {
            characterIndex = nil
        }
        if let characterIndex, let storage = textView.textStorage {
            let paragraph = source.paragraphRange(for: NSRange(location: characterIndex, length: 0))
            if characterIndex < paragraph.location + 2, paragraph.length >= 2 {
                let prefix = source.substring(with: NSRange(location: paragraph.location, length: 2))
                if prefix == "○ " || prefix == "◉ " {
                    let bodyIndex = paragraph.location + 2
                    if bodyIndex < source.length && source.character(at: bodyIndex) != 10
                        && source.character(at: bodyIndex) != 13,
                       let font = storage.attribute(.font, at: bodyIndex, effectiveRange: nil) as? NSFont {
                        return Int(font.pointSize.rounded())
                    }
                    return Int(NSFont.preferredFont(forTextStyle: .body).pointSize.rounded())
                }
            }
            if let font = storage.attribute(.font, at: characterIndex, effectiveRange: nil) as? NSFont {
                return Int(font.pointSize.rounded())
            }
        }
        let font = textView.typingAttributes[.font] as? NSFont
            ?? .preferredFont(forTextStyle: .body)
        return Int(font.pointSize.rounded())
    }

    private func transformFont(_ convert: (NSFont) -> NSFont) {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = attributes[.font] as? NSFont ?? .preferredFont(forTextStyle: .body)
            attributes[.font] = convert(font)
            textView.typingAttributes = attributes
            return
        }

        guard let storage = textView.textStorage else { return }
        let before = NSAttributedString(attributedString: storage)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? .preferredFont(forTextStyle: .body)
            storage.addAttribute(.font, value: convert(font), range: subrange)
        }
        storage.endEditing()
        registerFormattingUndo(before, in: textView, name: "Change Font Size")
    }

    private func registerFormattingUndo(_ before: NSAttributedString, in textView: NSTextView, name: String) {
        if let storage = textView.textStorage {
            ChecklistMarkerStyle.normalize(in: storage)
            InlineFormatBoundary.normalize(in: storage)
        }
        (textView as? EscapeAwareTextView)?.refreshCenteredTrailingSpaceLayout()
        guard let storage = textView.textStorage,
              !before.isEqual(to: storage),
              let undoManager = textView.undoManager else { return }
        let selection = textView.selectedRange()
        undoManager.registerUndo(withTarget: self) { [weak textView] controller in
            guard let textView else { return }
            controller.restoreFormatting(before, selection: selection, in: textView, name: name)
        }
        undoManager.setActionName(name)
    }

    private func restoreFormatting(_ snapshot: NSAttributedString, selection: NSRange, in textView: NSTextView, name: String) {
        guard let storage = textView.textStorage, let undoManager = textView.undoManager else { return }
        let inverse = NSAttributedString(attributedString: storage)
        let inverseSelection = textView.selectedRange()
        undoManager.registerUndo(withTarget: self) { [weak textView] controller in
            guard let textView else { return }
            controller.restoreFormatting(inverse, selection: inverseSelection, in: textView, name: name)
        }
        undoManager.setActionName(name)
        storage.setAttributedString(snapshot)
        ChecklistMarkerStyle.normalize(in: storage)
        InlineFormatBoundary.normalize(in: storage)
        let location = min(selection.location, storage.length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, storage.length - location)))
    }

    func clearFormatting() {
        guard let textView else { return }
        let range = textView.selectedRange().length == 0
            ? paragraphRange(in: textView)
            : textView.selectedRange()
        guard range.length > 0, let storage = textView.textStorage else {
            textView.typingAttributes = defaultAttributes
            return
        }

        let before = NSAttributedString(attributedString: storage)
        var attachments: [(NSRange, NSTextAttachment)] = []
        storage.enumerateAttribute(.attachment, in: range) { value, subrange, _ in
            if let attachment = value as? NSTextAttachment {
                attachments.append((subrange, attachment))
            }
        }
        storage.beginEditing()
        storage.setAttributes(defaultAttributes, range: range)
        for (subrange, attachment) in attachments {
            storage.addAttribute(.attachment, value: attachment, range: subrange)
        }
        let paragraphs = paragraphRange(in: textView)
        if paragraphs.length > 0 {
            storage.addAttribute(.paragraphStyle, value: NSParagraphStyle.default, range: paragraphs)
        }
        storage.endEditing()
        registerFormattingUndo(before, in: textView, name: "Clear Formatting")
    }

    private var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: NSParagraphStyle.default
        ]
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let fontManager = NSFontManager.shared
        let range = textView.selectedRange()

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = attributes[.font] as? NSFont ?? .preferredFont(forTextStyle: .body)
            let hasTrait = fontManager.traits(of: font).contains(trait)
            attributes[.font] = hasTrait
                ? fontManager.convert(font, toNotHaveTrait: trait)
                : fontManager.convert(font, toHaveTrait: trait)
            textView.typingAttributes = attributes
            return
        }

        guard let storage = textView.textStorage else { return }
        let before = NSAttributedString(attributedString: storage)
        var shouldRemove = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            let font = value as? NSFont ?? .preferredFont(forTextStyle: .body)
            if !fontManager.traits(of: font).contains(trait) {
                shouldRemove = false
                stop.pointee = true
            }
        }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? .preferredFont(forTextStyle: .body)
            let converted = shouldRemove
                ? fontManager.convert(font, toNotHaveTrait: trait)
                : fontManager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
        storage.endEditing()
        registerFormattingUndo(before, in: textView, name: "Change Font Style")
    }

    private func toggleIntegerAttribute(_ key: NSAttributedString.Key) {
        guard let textView else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let isEnabled = (attributes[key] as? Int ?? 0) != 0
            attributes[key] = isEnabled ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attributes
            return
        }

        guard let storage = textView.textStorage else { return }
        let before = NSAttributedString(attributedString: storage)
        var isEnabled = true
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if (value as? Int ?? 0) == 0 {
                isEnabled = false
                stop.pointee = true
            }
        }
        storage.addAttribute(
            key,
            value: isEnabled ? 0 : NSUnderlineStyle.single.rawValue,
            range: range
        )
        registerFormattingUndo(before, in: textView, name: "Change Text Style")
    }

    private func paragraphRange(in textView: NSTextView) -> NSRange {
        let source = textView.string as NSString
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        let selection = textView.selectedRange()
        let location = min(selection.location, source.length)
        let safeSelection = NSRange(
            location: location,
            length: min(selection.length, source.length - location)
        )
        return source.paragraphRange(for: safeSelection)
    }

    private func lineRanges(in source: NSString, selection: NSRange) -> [NSRange] {
        guard source.length > 0 else { return [] }
        let location = min(selection.location, source.length)
        let safeSelection = NSRange(
            location: location,
            length: min(selection.length, source.length - location)
        )
        let fullRange = source.paragraphRange(for: safeSelection)
        var result: [NSRange] = []
        var cursor = fullRange.location

        while cursor < NSMaxRange(fullRange) {
            let paragraph = source.paragraphRange(for: NSRange(location: cursor, length: 0))
            result.append(paragraph)
            let next = NSMaxRange(paragraph)
            if next <= cursor { break }
            cursor = next
        }
        return result
    }

    private func contentRange(for paragraph: NSRange, in source: NSString) -> NSRange {
        var length = paragraph.length
        while length > 0 {
            let character = source.character(at: paragraph.location + length - 1)
            if character == 10 || character == 13 {
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: paragraph.location, length: length)
    }

    private func prefix(for style: ListStyle, index: Int) -> String {
        switch style {
        case .bulleted: return "• "
        case .dashed: return "- "
        case .numbered: return "\(index + 1). "
        case .checklist: return "○ "
        case .blockQuote: return ""
        }
    }

    private func hasPrefix(for style: ListStyle, in line: String) -> Bool {
        switch style {
        case .bulleted: return line.hasPrefix("• ")
        case .dashed: return line.hasPrefix("- ")
        case .numbered:
            return line.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        case .checklist: return line.hasPrefix("○ ") || line.hasPrefix("◉ ")
        case .blockQuote: return false
        }
    }

    private func recognizedPrefixLength(in line: String) -> Int {
        guard let range = line.range(
            of: #"^(?:• |- |\d+\. |○ |◉ |☐ |☑ |> )"#,
            options: .regularExpression
        ) else { return 0 }
        return line[range].utf16.count
    }

}
