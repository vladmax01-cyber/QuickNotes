import AppKit
import PDFKit

@main
enum ContentFeaturesSmoke {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NSError(domain: "ContentFeaturesSmoke", code: 1,
                                              userInfo: [NSLocalizedDescriptionKey: message]) }
        checks += 1
    }

    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try pasteFontRegression()
        try invisibleBoundaryRegression()
        try invisibleListRegression()
        try emptyFormatStateRegression()
        try tables()
        try tableConversionRegression()
        try colorsAndBoundaries()
        try textColorContrast()
        try mediaAndClipboard()
        try tableImages()
        try readingPosition()
        try readingRestoration()
        try exportPDF()
        try exportNames()
        print("Content features passed: \(checks) checks (tables, color, media, clipboard, reading position, PDF)")
    }

    @MainActor
    static func pasteFontRegression() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        for family in ["Times New Roman", "Georgia", "Courier"] {
            for traits: NSFontTraitMask in [[], .boldFontMask, .italicFontMask, [.boldFontMask, .italicFontMask]] {
                let source = NSFontManager.shared.convert(NSFont(name: family, size: 13)!, toHaveTrait: traits)
                let input = NSAttributedString(string: "Hello café 🦆", attributes: [.font: source,
                    .underlineStyle: 1, .strikethroughStyle: 1, .backgroundColor: NSColor.systemYellow,
                    .link: URL(string: "https://example.com")!])
                board.clearContents()
                board.setData(try input.data(from: NSRange(location: 0, length: input.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
                let output = NoteRichContent.clipboardContent(from: board)!
                let font = output.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
                try expect(font.familyName == NSFont.systemFont(ofSize: 13).familyName,
                           "External font remained after paste: \(font.fontName)")
                let mask: NSFontTraitMask = [.boldFontMask, .italicFontMask]
                try expect(NSFontManager.shared.traits(of: font).intersection(mask) == traits,
                           "Standard paste lost bold/italic")
                try expect(output.string == input.string, "Standard paste lost Unicode")
                try expect(output.attribute(.link, at: 0, effectiveRange: nil) != nil,
                           "Standard font paste removed a link")
                try expect(output.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1,
                           "Standard font paste removed underline")
                try expect(output.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int == 1,
                           "Standard font paste removed strike")
                try expect(output.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil,
                           "Standard font paste removed highlight")
                let original = NoteRichContent.clipboardContent(from: board, standardizeFont: false)!
                let originalFont = original.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
                try expect(originalFont.familyName == source.familyName, "Keep Source Formatting changed its font")
            }
        }
        board.clearContents()
        board.setString("<p style='font-family:Times New Roman'>Web note <b>bold</b></p>", forType: .html)
        let html = NoteRichContent.clipboardContent(from: board)!
        try expect((html.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName
            == NSFont.systemFont(ofSize: 13).familyName, "HTML font not standardized")
        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.configureInlineTools()
        try expect(!view.usesRolloverButtonForSelection, "Floating selection-extension control remains enabled")
    }

    @MainActor
    static func invisibleBoundaryRegression() throws {
        for delimiter in ["\n", "\r", "\u{2028}", "\u{2029}", "\u{200B}", "\u{FEFF}", "\u{FFFC}"] {
            let text = NSMutableAttributedString(string: "One" + delimiter + "Two", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .underlineStyle: 1, .underlineColor: NSColor.systemBlue,
                .strikethroughStyle: 1, .strikethroughColor: NSColor.systemBlue,
                .backgroundColor: NSColor.systemCyan, .link: URL(string: "https://example.com")!])
            InlineFormatBoundary.normalize(in: text)
            for key in [NSAttributedString.Key.underlineStyle, .underlineColor, .strikethroughStyle,
                        .strikethroughColor, .backgroundColor, .link] {
                try expect(text.attribute(key, at: 3, effectiveRange: nil) == nil,
                           "Invisible carrier retains decoration: \(delimiter.unicodeScalars.map(\.value)) \(key)")
            }
            try expect(text.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == 1,
                       "Boundary cleanup removed real underline")
            try expect(text.string == "One" + delimiter + "Two", "Boundary cleanup changed content")
            let data = try text.data(from: NSRange(location: 0, length: text.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            let reopened = NoteRichContent.decode(text: text.string, data: data)
            try expect(reopened.attribute(.underlineColor, at: 3, effectiveRange: nil) == nil,
                       "Invisible decoration returned on reload")
        }
    }

    @MainActor
    static func invisibleListRegression() throws {
        for hidden in ["\u{200B}", "\u{FEFF}"] {
            for (prefix, style) in [("○ ", RichTextEditorController.ListStyle.checklist),
                                    ("• ", .bulleted), ("- ", .dashed), ("1. ", .numbered)] {
                let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
                view.isRichText = true
                view.allowsUndo = true
                view.textStorage?.setAttributedString(NSAttributedString(string: hidden + prefix + "Item",
                    attributes: [.font: NSFont.systemFont(ofSize: 13)]))
                ListMarkerAppearance.normalize(in: view.textStorage!)
                let controller = RichTextEditorController()
                controller.attach(view)
                view.setSelectedRange(NSRange(location: hidden.utf16.count + prefix.utf16.count, length: 0))
                controller.refreshFormattingState()
                try expect(controller.formattingState.listStyle == style, "Invisible prefix hid the list's active state")
                let font = view.textStorage?.attribute(.font, at: hidden.utf16.count, effectiveRange: nil) as! NSFont
                if style == .checklist {
                    try expect(font.pointSize == 12, "Invisible prefix changed checklist size")
                    try expect(view.toggleChecklist(at: 0), "Invisible prefix blocked checklist click")
                    try expect(view.string.hasPrefix(hidden + "◉ "), "Checklist toggle replaced the invisible prefix")
                }
                if style == .bulleted { try expect(font.pointSize == 16, "Invisible prefix changed bullet size") }
                controller.applyList(style)
                try expect(view.string == "Item", "List toggle duplicated the marker with an invisible prefix")
            }
            let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 240))
            view.isRichText = true
            view.textStorage?.setAttributedString(NSAttributedString(string: hidden + "○ Item",
                attributes: [.font: NSFont.systemFont(ofSize: 13)]))
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            view.insertNewline(nil)
            try expect(view.string.hasSuffix("\n○ "), "List continuation lost the marker after an invisible prefix")
            view.insertNewline(nil)
            try expect(!view.string.hasSuffix("○ "), "Empty continued list could not be ended")
            view.string = hidden + "3. Item\n"
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            let controller = RichTextEditorController()
            controller.attach(view)
            controller.applyList(.numbered)
            try expect(view.string.hasSuffix("\n4. "), "Invisible prefix restarted numbered continuation at one")
        }
    }

    @MainActor
    static func emptyFormatStateRegression() throws {
        let view = EscapeAwareTextView(frame: .zero)
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: style]
        let controller = RichTextEditorController()
        controller.attach(view)
        controller.refreshFormattingState()
        try expect(controller.formattingState.alignment == .left, "Empty natural paragraph had no active alignment")
        style.baseWritingDirection = .rightToLeft
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: style]
        controller.refreshFormattingState()
        try expect(controller.formattingState.alignment == .right, "Natural RTL alignment was not reflected")
    }

    @MainActor
    static func tableConversionRegression() throws {
        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 300))
        view.isRichText = true
        view.allowsUndo = true
        let table = NoteTable.make(rows: [["Picture", "Notes"], ["", "Keep bold"]])
        let picture = NSTextAttachment()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 12,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let bitmapImage = NSImage(size: NSSize(width: 24, height: 12))
        bitmapImage.addRepresentation(bitmap)
        picture.image = bitmapImage
        let image = NSMutableAttributedString(attributedString: NSAttributedString(attachment: picture))
        let imageLocation = (table.string as NSString).range(of: "\n\n").location + 1
        image.addAttributes(table.attributes(at: imageLocation, effectiveRange: nil), range: NSRange(location: 0, length: 1))
        table.insert(image, at: imageLocation)
        let word = (table.string as NSString).range(of: "Keep bold")
        table.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: word)
        view.textStorage?.setAttributedString(table)
        view.setSelectedRange(NSRange(location: imageLocation, length: 0))
        let controller = RichTextEditorController()
        controller.attach(view)
        controller.tableToText()
        try expect(view.string.contains("\u{FFFC}"), "Convert Table to Text discarded an image")
        let retained = (view.string as NSString).range(of: "Keep bold")
        try expect(retained.location != NSNotFound, "Table conversion lost cell text")
        let font = view.textStorage?.attribute(.font, at: retained.location, effectiveRange: nil) as! NSFont
        try expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "Table conversion discarded bold")
        try expect(view.string.contains("\t"), "Table conversion lost column separation")
        let block = NSTextTableBlock(table: NSTextTable(), startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
        block.backgroundColor = .systemOrange
        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        let colored = NSMutableAttributedString(string: "Custom cell\n", attributes: [.paragraphStyle: style])
        NoteTable.normalize(colored, width: 280)
        try expect(block.backgroundColor == .systemOrange, "Normalizing a pasted table overwrote its cell color")
        for rows in [[["", "🦆"], ["Café", ""]], [["first\nsecond", "third"]]] {
            let source = NoteTable.make(rows: rows)
            let flat = NoteRichContent.tableContents(source)
            try expect(!flat.string.contains("[Image]"), "Table conversion invented placeholders")
            try expect(flat.string.contains("\t"), "Empty or multiline cells lost separation")
            for row in rows {
                for cell in row where !cell.isEmpty {
                    try expect(flat.string.contains(cell.replacingOccurrences(of: "\n", with: "\u{2028}")),
                               "Table conversion lost emoji or a paragraph")
                }
            }
        }
    }

    @MainActor
    static func tables() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let html = "<table><tr><th>Task</th><th>Status</th></tr><tr><td>Read</td><td>Done</td></tr></table>"
        board.setString("Task Status Read Done", forType: .string)
        board.setString(html, forType: .html)
        let content = NoteRichContent.clipboardContent(from: board)!
        try expect(content.string.contains("Read"), "HTML lost cell content")
        let first = content.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        try expect(first?.textBlocks.first is NSTextTableBlock, "HTML table flattened")
        try expect(!QuoteParagraphStyle.isQuoted(first), "Table mistaken for quote")
        try expect(!QuoteParagraphStyle.repairLegacyBlocks(in: content), "Quote migration damaged table")
        let data = try content.data(from: NSRange(location: 0, length: content.length),
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let restored = NoteRichContent.decode(text: content.string, data: data)
        try expect((restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle)?.textBlocks.first is NSTextTableBlock, "Table lost after save/reload")
        for sample in ["| Idea | Status |\n| --- | --- |\n| Café 🦆 | Ready |",
                       "Idea\tStatus\nCafé 🦆\tReady", "| A | B |\n| :--- | ---: |\n| 1 | 2 |"] {
            let table = NoteTable.fromDelimitedText(sample)
            try expect(table != nil, "Delimited table not recognized")
            try expect(table!.string.contains(sample.contains("Café") ? "Café" : "1"), "Table lost Unicode or values")
        }
        try expect(NoteTable.fromDelimitedText("plain text") == nil, "Ordinary prose turned into a table")
        try expect(NoteTable.fromDelimitedText("A|B\nA", requiresMarkdown: false) == nil, "Ragged table accepted")
        try expect(NoteTable.fromDelimitedText("A|B\nC|D", requiresMarkdown: true) == nil, "Prose pipes auto-converted")
        let mixed = NoteTable.fromMarkdownDocument("Before\n| A | B |\n| --- | --- |\n| 1 | 2 |\nAfter")
        try expect(mixed?.string.hasPrefix("Before") == true && mixed?.string.hasSuffix("After") == true,
                   "Mixed Markdown table lost surrounding prose")
        try expect(NoteTable.fromMarkdownDocument("```\n| A | B |\n| --- | --- |\n| 1 | 2 |\n```") == nil,
                   "Code example was turned into a table")

        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 260))
        view.isRichText = true
        view.allowsUndo = true
        let controller = RichTextEditorController()
        controller.attach(view)
        controller.insertTable()
        try expect(view.string == "\n\n\n\n\n", "Empty table dimensions incorrect")
        controller.refreshFormattingState()
        try expect(controller.formattingState.inTable, "Table commands not enabled in a cell")
        view.insertText("Hello", replacementRange: view.selectedRange())
        controller.addTableRow()
        try expect(view.string.components(separatedBy: "\n").count == 8, "Add row lost cells")
        view.setSelectedRange(NSRange(location: 0, length: 5))
        controller.clearFormatting()
        try expect((view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle)?.textBlocks.first is NSTextTableBlock, "Clear formatting destroyed table")
        controller.apply(.heading)
        try expect((view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle)?.textBlocks.first is NSTextTableBlock, "Heading destroyed table")
        controller.tableToText()
        try expect(view.string.contains("Hello"), "Table to text lost cell content")
        try expect((view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
            as? NSParagraphStyle)?.textBlocks.isEmpty == true, "Table to text retained cells")
    }

    @MainActor
    static func colorsAndBoundaries() throws {
        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.isRichText = true
        view.allowsUndo = true
        view.string = "Color stays\nNext line"
        let controller = RichTextEditorController()
        controller.attach(view)
        view.setSelectedRange(NSRange(location: 0, length: 5))
        for color in RichTextEditorController.TextColor.allCases {
            controller.applyTextColor(color)
            controller.refreshFormattingState()
            try expect(controller.formattingState.textColor == color, "Text color state incorrect: \(color)")
            if color != .automatic {
                let data = view.rtf(from: NSRange(location: 0, length: view.string.utf16.count))!
                let decoded = NoteRichContent.decode(text: view.string, data: data)
                let actual = (decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil)
                    as! NSColor).usingColorSpace(.deviceRGB)!
                let expected = color.nsColor.usingColorSpace(.deviceRGB)!
                try expect(abs(actual.redComponent - expected.redComponent) < 0.03,
                           "Text color lost on reload: \(color)")
            }
        }
        controller.applyTextColor(.green)
        controller.apply(.monostyled)
        try expect(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            == RichTextEditorController.TextColor.green.nsColor, "Monostyled reset chosen text color")
        let web = NSMutableAttributedString(string: "Black\nWhite", attributes: NoteRichContent.bodyAttributes)
        web.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: 5))
        web.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 6, length: 5))
        NoteRichContent.normalize(web)
        try expect(web.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .labelColor,
                   "Black pasted text did not adapt")
        try expect(web.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor == .labelColor,
                   "White pasted text did not adapt")
        let media = NSMutableAttributedString(string: "Text\n\u{FFFC}\nNext", attributes: [
            .underlineStyle: 1, .underlineColor: NSColor.systemBlue, .strikethroughStyle: 1,
            .backgroundColor: NSColor.systemMint])
        InlineFormatBoundary.normalize(in: media)
        for location in [4, 5, 6] {
            for key in [NSAttributedString.Key.underlineStyle, .underlineColor, .strikethroughStyle, .backgroundColor] {
                try expect(media.attribute(key, at: location, effectiveRange: nil) == nil,
                           "Decorative line leaked onto media or line break")
            }
        }
        try expect(media.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil,
                   "Boundary cleanup removed actual highlight")
    }

    @MainActor
    static func textColorContrast() throws {
        func luminance(_ color: NSColor) -> Double {
            let rgb = color.usingColorSpace(.deviceRGB)!
            let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { value -> Double in
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            var ratios: [(RichTextEditorController.TextColor, Double)] = []
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let background = luminance(.textBackgroundColor)
                for color in RichTextEditorController.TextColor.allCases {
                    let foreground = luminance(color.nsColor)
                    ratios.append((color, (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)))
                }
            }
            for (color, ratio) in ratios {
                try expect(ratio >= 4.5, "Text color \(color) is unreadable in \(name): \(ratio)")
            }
        }
    }

    @MainActor
    static func mediaAndClipboard() throws {
        let image = NSImage(size: NSSize(width: 1400, height: 800))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 1400, height: 800).fill()
        image.unlockFocus()
        let attachment = NSTextAttachment()
        attachment.image = image
        let media = NSMutableAttributedString(string: "Before", attributes: NoteRichContent.bodyAttributes)
        media.append(NSAttributedString(attachment: attachment))
        media.append(NSAttributedString(string: "After", attributes: NoteRichContent.bodyAttributes))
        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 260, height: 240))
        view.isRichText = true
        view.importsGraphics = true
        view.isHorizontallyResizable = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 13, height: 12)
        view.textContainer?.widthTracksTextView = true
        view.insertPastedContent(media)
        try expect(view.string.contains("Before\n\u{FFFC}\nAfter"), "Image not separated from adjacent text")
        try expect(view.typingAttributes[.attachment] == nil, "Typing inherited image attachment")
        try expect(view.typingAttributes[.underlineStyle] == nil, "Typing after image inherited underline")
        try expect(attachment.bounds.width <= 226, "Image exceeds small note width")
        let ratio = attachment.bounds.width / attachment.bounds.height
        try expect(abs(ratio - 1.75) < 0.01, "Image aspect ratio distorted")
        view.setFrameSize(NSSize(width: 740, height: 400))
        view.resizeAttachmentsToFit()
        try expect(attachment.bounds.width <= 480, "Wide image exceeds compact maximum")
        try expect(attachment.bounds.width > 226, "Image did not expand when room became available")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        NoteRichContent.write(view.textStorage!, to: board)
        try expect(board.data(forType: .rtfd) != nil, "Copy note omitted RTFD images")
        try expect(board.string(forType: .string)?.contains("[Image]") == true, "Plain copy has invisible object marker")
        let restored = NoteRichContent.clipboardContent(from: board)!
        let index = (restored.string as NSString).range(of: "\u{FFFC}").location
        try expect(index != NSNotFound, "Rich clipboard lost image")
        try expect(restored.attribute(.attachment, at: index, effectiveRange: nil) != nil, "Clipboard attachment missing")
    }

    @MainActor
    static func tableImages() throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUICK_NOTES_TEST_OUTPUT"]
            ?? "/tmp/QuickNotesContentSmoke")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func image(_ color: NSColor, size: NSSize) -> String {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            color.setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: size.width * 0.25, y: size.height * 0.25,
                width: size.width * 0.5, height: size.height * 0.5)).fill()
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!.base64EncodedString()
        }
        let blue = image(.systemBlue, size: NSSize(width: 900, height: 450))
        let orange = image(.systemOrange, size: NSSize(width: 480, height: 720))
        let html = """
        <html><body><h2>Table and image compatibility</h2>
        <p>Before the table. A <b>bold</b> and <i>italic</i> reminder.</p>
        <table><tr><th>Item</th><th>Picture</th><th>Notes</th></tr>
        <tr><td>Blue landscape</td><td>Before image<img src="data:image/png;base64,\(blue)">After image</td>
        <td><b>Bold text</b>, <i>italic text</i>, and <a href="https://example.com">example link</a>.</td></tr>
        <tr><td>Orange portrait</td><td><img src="data:image/png;base64,\(orange)"></td>
        <td><u>Underlined</u> and <s>struck text</s>.<p>Second paragraph inside cell.</p></td></tr></table>
        <p>End of clipboard test.</p></body></html>
        """
        try html.write(to: folder.appendingPathComponent("Table Images.html"), atomically: true, encoding: .utf8)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(html, forType: .html)
        let imported = NoteRichContent.clipboardContent(from: board)!
        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        view.isRichText = true
        view.importsGraphics = true
        view.textContainerInset = NSSize(width: 13, height: 12)
        view.textContainer?.widthTracksTextView = true
        view.insertPastedContent(imported)
        let content = view.textStorage!
        var attachments: [(NSTextAttachment, Int)] = []
        content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment { attachments.append((attachment, range.location)) }
        }
        try expect(attachments.count == 2, "Table import lost an image")
        for (attachment, location) in attachments {
            let style = content.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            let block = style?.textBlocks.compactMap { $0 as? NSTextTableBlock }.first
            try expect(block?.startingColumn == 1, "Image escaped its table cell during paste")
            try expect(attachment.bounds.width <= 76, "Image exceeds its cell in a compact note")
            try expect(attachment.bounds.height > 0, "Table image has no display height")
            let bytes = attachment.fileWrapper?.regularFileContents ?? attachment.image?.tiffRepresentation
            try expect(bytes.flatMap(NSImage.init(data:)) != nil, "Imported table image is a broken placeholder")
        }
        for word in ["Before image", "After image", "Second paragraph inside cell."] {
            let range = (content.string as NSString).range(of: word)
            let style = content.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            try expect(style?.textBlocks.first is NSTextTableBlock, "Text escaped table: \(word)")
        }
        let bold = (content.string as NSString).range(of: "Bold text")
        let boldFont = content.attribute(.font, at: bold.location, effectiveRange: nil) as! NSFont
        try expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask), "Cell bold lost")
        let italic = (content.string as NSString).range(of: "italic text")
        try expect(NSFontManager.shared.traits(of: content.attribute(.font, at: italic.location,
            effectiveRange: nil) as! NSFont).contains(.italicFontMask), "Cell italic lost")
        let link = (content.string as NSString).range(of: "example link")
        try expect(content.attribute(.link, at: link.location, effectiveRange: nil) != nil, "Cell link lost")
        let underlined = (content.string as NSString).range(of: "Underlined")
        try expect((content.attribute(.underlineStyle, at: underlined.location, effectiveRange: nil)
            as? Int ?? 0) != 0, "Cell underline lost")
        let strike = (content.string as NSString).range(of: "struck text")
        try expect((content.attribute(.strikethroughStyle, at: strike.location, effectiveRange: nil)
            as? Int ?? 0) != 0, "Cell strikethrough lost")
        view.setFrameSize(NSSize(width: 900, height: 400))
        view.resizeAttachmentsToFit(forceTableLayout: true)
        try expect(attachments[0].0.bounds.width > 200, "Table images did not grow when window widened")
        try expect(abs(attachments[0].0.bounds.width / attachments[0].0.bounds.height - 2) < 0.01,
                   "Landscape image aspect ratio changed")
        try expect(abs(attachments[1].0.bounds.width / attachments[1].0.bounds.height - 2.0 / 3) < 0.01,
                   "Portrait image aspect ratio changed")
        NoteRichContent.write(content, to: board)
        let copied = NoteRichContent.clipboardContent(from: board)!
        try expect(copied.string == content.string, "Rich table copy changed text")
        let data = try content.data(from: NSRange(location: 0, length: content.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        try data.write(to: folder.appendingPathComponent("Table Images.rtfd-data"))
        let restored = NoteRichContent.decode(text: content.string, data: data)
        var restoredImages = 0
        restored.enumerateAttribute(.attachment, in: NSRange(location: 0, length: restored.length)) { value, range, _ in
            guard value is NSTextAttachment else { return }
            restoredImages += 1
            let style = restored.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            precondition(style?.textBlocks.first is NSTextTableBlock, "Reload lost image cell")
        }
        try expect(restoredImages == 2, "Reload lost table images")
        let pdfURL = folder.appendingPathComponent("Table Images.pdf")
        try NoteExport.pdf(restored, to: pdfURL)
        let document = PDFDocument(url: pdfURL)!
        try expect(document.pageCount == 1, "Small image table spills unexpectedly to another page")
        for word in ["Table and image compatibility", "Blue landscape", "Orange portrait", "Before image",
                     "After image", "Second paragraph inside cell.", "End of clipboard test."] {
            try expect(document.string?.contains(word) == true, "Table PDF lost text: \(word)")
        }
        let page = document.page(at: 0)!
        let item = document.findString("Item", withOptions: []).first!.bounds(for: page)
        let picture = document.findString("Picture", withOptions: []).first!.bounds(for: page)
        let notes = document.findString("Notes", withOptions: []).first!.bounds(for: page)
        try expect(abs(item.midY - picture.midY) < 2 && abs(notes.midY - picture.midY) < 2,
                   "Image table PDF column headers misaligned")
        let thumb = page.thumbnail(of: NSSize(width: 1224, height: 1584), for: .mediaBox)
        let bitmap = NSBitmapImageRep(data: thumb.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("Table Images.png"))
    }

    static func readingPosition() throws {
        let name = "QuickNotes.ContentSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = UUID(), second = UUID()
        NoteReadingPositions.save(NoteReadingPosition(location: 24, verticalOffset: 322), id: first, defaults: defaults)
        NoteReadingPositions.save(NoteReadingPosition(location: 5, verticalOffset: 0), id: second, defaults: defaults)
        try expect(NoteReadingPositions.read(first, defaults: defaults)?.location == 24, "Caret not persisted")
        try expect(NoteReadingPositions.read(first, defaults: defaults)?.verticalOffset == 322, "Scroll not persisted")
        try expect(NoteReadingPositions.read(second, defaults: defaults)?.verticalOffset == 0, "Note positions mixed")
        try expect(NoteReadingPositions.read(UUID(), defaults: defaults) == nil, "New note inherited position")
    }

    @MainActor
    static func readingRestoration() throws {
        let name = "QuickNotes.ReadingSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let longID = UUID(), shortID = UUID()
        let longText = (1...100).map { "Line \($0): a little room for thoughts." }.joined(separator: "\n")
        let controller = RichTextEditorController()
        let parent = NativeTextEditor(noteID: longID, text: longText, richTextData: nil, focusGeneration: 0,
            showsVerticalScroller: true, controller: controller, onChange: { _, _, _ in }, onEscape: {},
            rememberReadingPosition: true, readingPositionDefaults: defaults)
        let coordinator = parent.makeCoordinator()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 240))
        scroll.hasVerticalScroller = true
        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 240))
        view.isRichText = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 13, height: 12)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 280, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        coordinator.textView = view
        coordinator.noteID = longID
        coordinator.applyContent(text: longText, richTextData: nil)
        NoteReadingPositions.save(NoteReadingPosition(location: 20, verticalOffset: 500, atBottom: true),
                                  id: longID, defaults: defaults)
        coordinator.restoreReadingPosition()
        waitForLayout { scroll.contentView.bounds.minY > 240 }
        try expect(scroll.contentView.bounds.minY > 240, "Long note did not restore below the top")
        try expect(view.selectedRange().location == 20, "Restored caret incorrect")
        coordinator.saveReadingPosition()
        coordinator.noteID = shortID
        coordinator.applyContent(text: "Short note", richTextData: nil)
        coordinator.restoreReadingPosition()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        try expect(scroll.contentView.bounds.minY == 0, "Short note kept old long-note offset")
        try expect(view.bounds.height <= scroll.contentSize.height + 1, "Short note kept old document height")
        try expect(view.frame.origin == .zero, "Short note retained a negative document frame origin")
        try expect(view.selectedRange().location == 0, "New note started at the end")
        coordinator.noteID = longID
        coordinator.applyContent(text: longText, richTextData: nil)
        coordinator.restoreReadingPosition()
        waitForLayout { scroll.contentView.bounds.minY > 240 }
        try expect(scroll.contentView.bounds.minY > 240, "Switching notes lost the prior reading position")
        var topParent = parent
        topParent.rememberReadingPosition = false
        coordinator.parent = topParent
        coordinator.restoreReadingPosition()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        try expect(scroll.contentView.bounds.minY == 0, "Disabled remember-position ignored")
        try expect(view.selectedRange().location == 0, "Disabled remember-position retained caret")
        coordinator.parent = parent
        coordinator.noteID = longID
        for width: CGFloat in [280, 700] {
            scroll.setFrameSize(NSSize(width: width, height: 240))
            view.setFrameSize(NSSize(width: width, height: 240))
            coordinator.applyContent(text: longText, richTextData: nil)
            for state in [(offset: CGFloat(0), bottom: false), (offset: CGFloat(500), bottom: false),
                          (offset: CGFloat(500), bottom: true)] {
                NoteReadingPositions.save(NoteReadingPosition(location: 20, verticalOffset: state.offset,
                    atBottom: state.bottom), id: longID, defaults: defaults)
                coordinator.restoreReadingPosition()
                waitForLayout { !coordinator.restoringPosition }
                let expected = state.bottom ? max(0, view.bounds.height - scroll.contentSize.height) : state.offset
                try expect(abs(scroll.contentView.bounds.minY - expected) < 1,
                           "Reading position changed after compact/wide layout: width=\(width), bottom=\(state.bottom), expected=\(expected), actual=\(scroll.contentView.bounds.minY)")
                try expect(view.selectedRange().location == 20, "Restoring scroll moved the caret")
            }
        }
    }

    @MainActor
    static func waitForLayout(_ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 1)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    @MainActor
    static func exportNames() throws {
        try expect(NoteExport.safeName("") == "Quick Note", "Empty export name missing fallback")
        try expect(NoteExport.safeName("   ") == "Quick Note", "Whitespace export name missing fallback")
        try expect(NoteExport.safeName("...") == "Quick Note", "Dot-only export name creates hidden file")
        try expect(NoteExport.safeName("a/b:c") == "a b c", "Export name contains path separators")
        try expect(NoteExport.safeName("a\nb\rc") == "a b c", "Export name contains line breaks")
        try expect(NoteExport.safeName("a\u{0}b") == "a b", "Export name contains a null byte")
        try expect(NoteExport.safeName(String(repeating: "A", count: 200)).count == 80,
                   "Long export name exceeds character limit")
        try expect(NoteExport.safeName(String(repeating: "🦆", count: 80)).utf8.count <= 180,
                   "Emoji export name exceeds filesystem byte limit")
        try expect(NoteExport.safeName(String(repeating: "👨‍👩‍👧‍👦", count: 80)).utf8.count <= 180,
                   "Multi-scalar emoji export name exceeds filesystem byte limit")
        try expect(NoteExport.safeName("Café – ideas") == "Café – ideas", "Unicode export name changed")
    }

    @MainActor
    static func exportPDF() throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUICK_NOTES_TEST_OUTPUT"] ?? "/tmp/QuickNotesContentSmoke")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let content = NSMutableAttributedString(string: "A little room for ideas\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 26), .foregroundColor: NSColor.labelColor])
        content.append(NSAttributedString(string: "Keep the good bits close.\n", attributes: NoteRichContent.bodyAttributes))
        content.addAttribute(.backgroundColor, value: NSColor.systemMint.withAlphaComponent(0.4),
                             range: (content.string as NSString).range(of: "good bits"))
        content.append(NoteTable.make(rows: [["Idea", "Next step"], ["A tiny garden", "Find a sunny spot"],
                                            ["A Sunday recipe", "Save the ingredients"]]))
        let image = NSImage(size: NSSize(width: 600, height: 220))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 220).fill()
        image.unlockFocus()
        let attachment = NSTextAttachment()
        attachment.image = image
        content.append(NSAttributedString(attachment: attachment))
        content.append(NSAttributedString(string: "\nAfter the image\n", attributes: NoteRichContent.bodyAttributes))
        for index in 1...85 {
            content.append(NSAttributedString(string: "\(index). Save a thought and keep going.\n",
                                               attributes: NoteRichContent.bodyAttributes))
        }
        let url = folder.appendingPathComponent("Export QA.pdf")
        let originalBounds = attachment.bounds
        try NoteExport.pdf(content, to: url)
        try expect(attachment.bounds == originalBounds, "Export changed the note's original image size")
        let richURL = folder.appendingPathComponent("Export QA.rtfd")
        let wrapper = try content.fileWrapper(from: NSRange(location: 0, length: content.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        try wrapper.write(to: richURL, options: .atomic, originalContentsURL: nil)
        let rich = try NSAttributedString(url: richURL,
            options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
        try expect(rich.string.contains("Find a sunny spot"), "Rich export lost table content")
        try expect(rich.string.contains("\u{FFFC}"), "Rich export lost image")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        NoteRichContent.write(content, to: board)
        let copied = NoteRichContent.clipboardContent(from: board)!
        try expect(copied.string.contains("\u{FFFC}"), "Copying a table with images chose a flattened fallback")
        try expect(board.string(forType: .string)?.contains("Idea\tNext step") == true,
                   "Plain table copy lost column separators")
        if let html = board.data(forType: .html) { try html.write(to: folder.appendingPathComponent("Clipboard QA.html")) }
        try expect(board.string(forType: .html)?.contains("data:image/png;base64,") == true,
                   "HTML clipboard images depend on a missing external file")
        if let html = board.data(forType: .html) {
            board.clearContents()
            board.setData(html, forType: .html)
            let htmlCopy = NoteRichContent.clipboardContent(from: board)
            try expect(htmlCopy?.string.contains("\u{FFFC}") == true,
                       "HTML-only clipboard lost the embedded image")
            let imageIndex = (htmlCopy!.string as NSString).range(of: "\u{FFFC}").location
            let image = htmlCopy!.attribute(.attachment, at: imageIndex, effectiveRange: nil) as? NSTextAttachment
            let bytes = image?.fileWrapper?.regularFileContents ?? image?.image?.tiffRepresentation
            try expect(bytes.flatMap(NSImage.init(data:)) != nil, "HTML clipboard contains a broken image placeholder")
        }
        let document = PDFDocument(url: url)
        try expect(document != nil, "PDF cannot reopen")
        try expect(document!.pageCount >= 2, "Long note PDF was truncated into one page")
        let text = document!.string ?? ""
        for expected in ["A little room", "sunny spot", "ingredients", "After the image", "85."] {
            try expect(text.contains(expected), "PDF missing content: \(expected)")
        }
        let page = document!.page(at: 0)!
        let idea = document!.findString("Idea", withOptions: []).first!
        let next = document!.findString("Next step", withOptions: []).first!
        try expect(abs(idea.bounds(for: page).midY - next.bounds(for: page).midY) < 3,
                   "PDF flattened table columns into separate lines")
        try expect(next.bounds(for: page).maxX <= 576, "PDF table text exceeds the page margin")
        let size = page.bounds(for: .mediaBox).size
        try expect(size.width == 612 && size.height == 792, "PDF paper bounds wrong")
        let thumb = page.thumbnail(of: NSSize(width: 918, height: 1188), for: .mediaBox)
        let bitmap = NSBitmapImageRep(data: thumb.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("Export QA.png"))
        for index in 1..<document!.pageCount {
            let image = document!.page(at: index)!.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: folder.appendingPathComponent("Export QA-page\(index + 1).png"))
        }
        let emptyURL = folder.appendingPathComponent("Empty QA.pdf")
        try NoteExport.pdf(NSAttributedString(string: ""), to: emptyURL)
        try expect(PDFDocument(url: emptyURL)?.pageCount == 1, "Empty note PDF did not create a valid blank page")
    }
}
