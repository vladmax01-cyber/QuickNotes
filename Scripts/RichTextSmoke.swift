import AppKit

enum RichTextSmokeFailure: Error {
    case failed(String)
}

@main
enum RichTextSmoke {
    @MainActor
    static func main() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = "First line\nSecond line"

        let controller = RichTextEditorController()
        controller.attach(textView)

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.toggleBold()
        guard let boldFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask) else {
            throw RichTextSmokeFailure.failed("Bold formatting was not applied")
        }

        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        controller.applyList(.bulleted)
        guard textView.string == "• First line\n• Second line" else {
            throw RichTextSmokeFailure.failed("Bulleted list formatting was incorrect: \(textView.string)")
        }

        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        controller.applyList(.bulleted)
        guard textView.string == "First line\nSecond line" else {
            throw RichTextSmokeFailure.failed("Bulleted list could not be toggled off")
        }

        NSFontPanel.shared.orderFront(nil)
        guard NSFontPanel.shared.isVisible else {
            throw RichTextSmokeFailure.failed("Font panel test setup failed")
        }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.apply(.heading)
        guard let headingFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              headingFont.pointSize == 20 else {
            throw RichTextSmokeFailure.failed("Heading style was not applied")
        }
        guard !NSFontPanel.shared.isVisible else {
            throw RichTextSmokeFailure.failed("Heading style left the system font panel visible")
        }

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.toggleHighlight()
        guard textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil else {
            throw RichTextSmokeFailure.failed("Highlight formatting was not applied")
        }

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        controller.toggleHighlight()
        guard textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil else {
            throw RichTextSmokeFailure.failed("Highlight could not be toggled off at the cursor")
        }
        controller.toggleHighlight()
        guard textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil else {
            throw RichTextSmokeFailure.failed("Highlight could not be applied at the cursor")
        }

        guard let rtf = textView.rtf(
            from: NSRange(location: 0, length: textView.string.utf16.count)
        ), let decoded = NSAttributedString(rtf: rtf, documentAttributes: nil),
              decoded.string == textView.string,
              decoded.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil else {
            throw RichTextSmokeFailure.failed("Rich text could not be serialized and restored")
        }

        try testListsAndSpecialCharacters()
        try testChecklistParagraphs()
        try testChecklistMarkerAppearance()
        try testHeadingContinuation()
        try testEmptyParagraphFormatting()
        try testBodyContinuationWithStaleTypingAttributes()
        try testPaletteFollowsTypingSelection()
        try testBlockQuote()
        try testAlignment()
        try testAlignmentWithIndentAndSpaces()
        try testMixedFormattingAndUndo()
        try testCutCopyPaste()
        try testHighlightColorsAndPaletteSelection()
        try testNumericFontSize()
        try testAllTextStylesAndAlignments()
        try testFormatBoundariesAndLists()
        try testImagePersistence()
        try testUnderlineLineBreak()
        print("All text styles and alignments, inline formats, lists, paste, undo, and image persistence passed")
    }

    @MainActor
    private static func testAlignment() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.string = "First line\nSecond line"
        let controller = RichTextEditorController()
        controller.attach(textView)

        let glyphRange = NSRange(location: 0, length: 5)
        let initialX = textView.layoutManager?.boundingRect(
            forGlyphRange: glyphRange,
            in: textView.textContainer!
        ).minX ?? 0

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        controller.setAlignment(.center)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let centeredX = textView.layoutManager?.boundingRect(
            forGlyphRange: glyphRange,
            in: textView.textContainer!
        ).minX ?? 0
        guard centeredX > initialX + 5 else {
            throw RichTextSmokeFailure.failed("Center alignment did not move the visible glyphs")
        }
        let firstStyle = textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let secondStyle = textView.textStorage?.attribute(.paragraphStyle, at: 12, effectiveRange: nil) as? NSParagraphStyle
        guard firstStyle?.alignment == .center, secondStyle?.alignment != .center else {
            throw RichTextSmokeFailure.failed("Center alignment did not affect only the current paragraph")
        }
        let range = NSRange(location: 0, length: textView.string.utf16.count)
        guard let rtf = textView.rtf(from: range),
              let decoded = NSAttributedString(rtf: rtf, documentAttributes: nil),
              (decoded.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .center else {
            throw RichTextSmokeFailure.failed("Center alignment did not survive save and reload")
        }

        let emptyTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        emptyTextView.isRichText = true
        let emptyController = RichTextEditorController()
        emptyController.attach(emptyTextView)
        emptyController.setAlignment(.center)
        emptyTextView.insertText("Centered", replacementRange: NSRange(location: 0, length: 0))
        let insertedStyle = emptyTextView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        guard insertedStyle?.alignment == .center else {
            throw RichTextSmokeFailure.failed("Center alignment did not apply to new text in an empty note")
        }
    }

    @MainActor
    private static func testAlignmentWithIndentAndSpaces() throws {
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.string = "Quick Note"
        let quoted = QuoteParagraphStyle.updated(nil, quoted: true)
        textView.textStorage?.addAttribute(
            .paragraphStyle, value: quoted, range: NSRange(location: 0, length: 10)
        )
        let controller = RichTextEditorController()
        controller.attach(textView)
        textView.setSelectedRange(NSRange(location: 10, length: 0))

        for textStyle in [
            RichTextEditorController.TextStyle.title, .heading, .subheading
        ] {
            controller.apply(textStyle)
            let paragraph = textView.textStorage?.attribute(
                .paragraphStyle, at: 0, effectiveRange: nil
            ) as? NSParagraphStyle
            guard paragraph?.headIndent == 0, paragraph?.firstLineHeadIndent == 0 else {
                throw RichTextSmokeFailure.failed("A heading kept the block quote indent")
            }
            textView.textStorage?.addAttribute(
                .paragraphStyle, value: quoted, range: NSRange(location: 0, length: 10)
            )
        }

        controller.setAlignment(.center)
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            throw RichTextSmokeFailure.failed("Text layout was unavailable")
        }
        let titleGlyphs = NSRange(location: 0, length: 10)
        func titleRect() -> NSRect {
            layoutManager.ensureLayout(for: container)
            return layoutManager.boundingRect(forGlyphRange: titleGlyphs, in: container)
        }
        let centered = titleRect()
        guard abs(centered.midX - container.containerSize.width / 2) < 1,
              let centeredStyle = textView.textStorage?.attribute(
                  .paragraphStyle, at: 0, effectiveRange: nil
              ) as? NSParagraphStyle,
              centeredStyle.headIndent == 0, centeredStyle.firstLineHeadIndent == 0 else {
            throw RichTextSmokeFailure.failed("The quoted heading stayed off center")
        }

        textView.insertText(" ", replacementRange: textView.selectedRange())
        let afterSpace = titleRect()
        guard afterSpace.minX < centered.minX - 1,
              let spacedStyle = textView.textStorage?.attribute(
                  .paragraphStyle, at: 0, effectiveRange: nil
              ) as? NSParagraphStyle,
              spacedStyle.alignment == .center, spacedStyle.tailIndent < 0 else {
            throw RichTextSmokeFailure.failed("A centered trailing space did not move the heading left")
        }

        textView.insertText(" ", replacementRange: textView.selectedRange())
        let afterTwoSpaces = titleRect()
        guard afterTwoSpaces.minX < afterSpace.minX - 1 else {
            throw RichTextSmokeFailure.failed("A second centered space did not move the heading farther left")
        }
        textView.deleteBackward(nil)
        guard abs(titleRect().minX - afterSpace.minX) < 1 else {
            throw RichTextSmokeFailure.failed("Deleting one centered space did not restore its position")
        }
        textView.deleteBackward(nil)
        guard textView.string == "Quick Note",
              abs(titleRect().minX - centered.minX) < 1,
              let restoredStyle = textView.textStorage?.attribute(
                  .paragraphStyle, at: 0, effectiveRange: nil
              ) as? NSParagraphStyle,
              restoredStyle.tailIndent == 0 else {
            throw RichTextSmokeFailure.failed("Deleting a centered space did not restore the layout")
        }

        for alignment in [NSTextAlignment.left, .right, .center, .left] {
            controller.setAlignment(alignment)
            let style = textView.textStorage?.attribute(
                .paragraphStyle, at: 0, effectiveRange: nil
            ) as? NSParagraphStyle
            guard style?.alignment == alignment, style?.headIndent == 0,
                  style?.firstLineHeadIndent == 0, style?.tailIndent == 0 else {
                throw RichTextSmokeFailure.failed("Changing alignment retained an indent")
            }
        }

        guard let rtf = textView.rtf(from: NSRange(location: 0, length: textView.string.utf16.count)),
              let restored = NSAttributedString(rtf: rtf, documentAttributes: nil),
              let style = restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
              style.alignment == .left, style.headIndent == 0 else {
            throw RichTextSmokeFailure.failed("The corrected alignment did not survive save and reload")
        }

        let emptyView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        emptyView.isRichText = true
        let emptyController = RichTextEditorController()
        emptyController.attach(emptyView)
        emptyController.setAlignment(.center)
        emptyView.insertText(" ", replacementRange: emptyView.selectedRange())
        guard let spaceStyle = emptyView.textStorage?.attribute(
            .paragraphStyle, at: 0, effectiveRange: nil
        ) as? NSParagraphStyle,
              spaceStyle.alignment == .center, spaceStyle.tailIndent < 0 else {
            throw RichTextSmokeFailure.failed("A centered empty paragraph lost its alignment after a space")
        }
        emptyView.insertText("A", replacementRange: emptyView.selectedRange())
        guard let contentStyle = emptyView.textStorage?.attribute(
            .paragraphStyle, at: 0, effectiveRange: nil
        ) as? NSParagraphStyle,
              contentStyle.tailIndent == 0 else {
            throw RichTextSmokeFailure.failed("A centered paragraph kept a space offset after more text")
        }
        emptyView.insertNewline(nil)
        let newParagraph = emptyView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        guard newParagraph?.alignment == .center, newParagraph?.tailIndent == 0 else {
            throw RichTextSmokeFailure.failed("A new centered paragraph inherited a stale space offset")
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let undoView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        undoView.isRichText = true
        undoView.allowsUndo = true
        undoView.string = "Centered"
        window.contentView?.addSubview(undoView)
        window.makeFirstResponder(undoView)
        let undoController = RichTextEditorController()
        undoController.attach(undoView)
        let editor = NativeTextEditor(
            noteID: UUID(), text: "Centered", richTextData: nil, focusGeneration: 0,
            controller: undoController, onChange: { _, _, _ in }, onEscape: {}
        )
        let coordinator = editor.makeCoordinator()
        coordinator.textView = undoView
        undoView.delegate = coordinator
        undoView.textStorage?.delegate = coordinator
        undoView.setSelectedRange(NSRange(location: 8, length: 0))
        undoController.setAlignment(.center)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        undoView.insertText(" ", replacementRange: undoView.selectedRange())
        undoView.undoManager?.undo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        guard undoView.string == "Centered",
              let undoneStyle = undoView.textStorage?.attribute(
                  .paragraphStyle, at: 0, effectiveRange: nil
              ) as? NSParagraphStyle,
              undoneStyle.alignment == .center, undoneStyle.tailIndent == 0 else {
            throw RichTextSmokeFailure.failed("Undo did not remove a centered space cleanly")
        }
        undoView.undoManager?.redo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        guard undoView.string == "Centered ",
              let redoneStyle = undoView.textStorage?.attribute(
                  .paragraphStyle, at: 0, effectiveRange: nil
              ) as? NSParagraphStyle,
              redoneStyle.tailIndent < 0 else {
            throw RichTextSmokeFailure.failed("Redo did not restore centered space layout")
        }
    }

    @MainActor
    private static func testMixedFormattingAndUndo() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 280))
        textView.isRichText = true
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        textView.insertText("First line\nSecond line", replacementRange: NSRange(location: 0, length: 0))
        let controller = RichTextEditorController()
        controller.attach(textView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.toggleUnderline()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        textView.setSelectedRange(NSRange(location: 0, length: 10))
        controller.toggleUnderline()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        guard (textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int ?? 0) != 0,
              (textView.textStorage?.attribute(.underlineStyle, at: 7, effectiveRange: nil) as? Int ?? 0) != 0 else {
            throw RichTextSmokeFailure.failed("Mixed underline selection was toggled off instead of filled in")
        }

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        controller.setAlignment(.center)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        textView.setSelectedRange(NSRange(location: 1, length: 2))
        controller.clearFormatting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let firstStyle = textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let lastStyle = textView.textStorage?.attribute(.paragraphStyle, at: 9, effectiveRange: nil) as? NSParagraphStyle
        guard firstStyle?.alignment == NSParagraphStyle.default.alignment,
              lastStyle?.alignment == NSParagraphStyle.default.alignment else {
            throw RichTextSmokeFailure.failed("Clearing a partial selection left one paragraph with split alignment")
        }

        textView.setSelectedRange(NSRange(location: 0, length: 10))
        controller.applyList(.blockQuote)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        guard QuoteParagraphStyle.isQuoted(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle),
              textView.undoManager?.undoActionName == "Block Quote" else {
            throw RichTextSmokeFailure.failed("Formatting did not enter the undo history")
        }
        textView.undoManager?.undo()
        guard !QuoteParagraphStyle.isQuoted(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle),
              textView.string == "First line\nSecond line" else {
            throw RichTextSmokeFailure.failed("Command-Z did not undo formatting without deleting text")
        }
        textView.undoManager?.redo()
        guard QuoteParagraphStyle.isQuoted(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) else {
            throw RichTextSmokeFailure.failed("Shift-Command-Z did not restore formatting")
        }
    }

    @MainActor
    private static func testCutCopyPaste() throws {
        let pasteboard = NSPasteboard.general
        let originals: [[(NSPasteboard.PasteboardType, Data)]] = try (pasteboard.pasteboardItems ?? []).map { item in
            try item.types.map { type in
                guard let data = item.data(forType: type) else {
                    throw RichTextSmokeFailure.failed("Cannot safely preserve the current clipboard")
                }
                return (type, data)
            }
        }
        var lastOwnChangeCount = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == lastOwnChangeCount {
                pasteboard.clearContents()
                let items = originals.map { fields -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in fields { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 250),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 250))
        textView.isRichText = true
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        textView.insertText("Hello", replacementRange: NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        textView.setSelectedRange(NSRange(location: 1, length: 3))
        textView.cut(nil)
        lastOwnChangeCount = pasteboard.changeCount
        guard textView.string == "Ho", pasteboard.string(forType: .string) == "ell" else {
            throw RichTextSmokeFailure.failed("Command-X did not cut the selected text")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        textView.undoManager?.undo()
        guard textView.string == "Hello" else {
            throw RichTextSmokeFailure.failed("Command-Z did not restore cut text")
        }
        textView.undoManager?.redo()
        guard textView.string == "Ho" else {
            throw RichTextSmokeFailure.failed("Shift-Command-Z did not repeat the cut")
        }
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.paste(nil)
        guard textView.string == "Hello" else {
            throw RichTextSmokeFailure.failed("Paste did not restore the cut text")
        }
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        textView.copy(nil)
        lastOwnChangeCount = pasteboard.changeCount
        guard pasteboard.string(forType: .string) == "Hello" else {
            throw RichTextSmokeFailure.failed("Copy did not place the selected text on the clipboard")
        }
    }

    @MainActor
    private static func testHighlightColorsAndPaletteSelection() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.string = "Colorful text"
        let controller = RichTextEditorController()
        controller.attach(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.rememberPaletteSelection()
        controller.applyHighlight(.mint)
        let mint = textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
        controller.rememberPaletteSelection()
        controller.revealPaletteResult()
        guard textView.selectedRange() == NSRange(location: 8, length: 0) else {
            throw RichTextSmokeFailure.failed("Formatted text remained selected and hid its highlight")
        }
        controller.restorePaletteSelection()
        guard textView.selectedRange() == NSRange(location: 0, length: 8) else {
            throw RichTextSmokeFailure.failed("Palette lost the original text selection")
        }
        controller.applyHighlight(.pink)
        let pink = textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
        guard let mint, let pink, !mint.isEqual(pink) else {
            throw RichTextSmokeFailure.failed("Highlight colors did not differ")
        }
        guard let rtf = textView.rtf(from: NSRange(location: 0, length: textView.string.utf16.count)),
              let decoded = NSAttributedString(rtf: rtf, documentAttributes: nil),
              decoded.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil else {
            throw RichTextSmokeFailure.failed("Colored highlight did not survive save and reload")
        }
        controller.removeHighlight()
        guard textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil else {
            throw RichTextSmokeFailure.failed("Remove Highlight did not clear the color")
        }
    }

    @MainActor
    private static func testListsAndSpecialCharacters() throws {
        let first = "Café 📝 — Ελληνικά"
        let second = "日本語 e\u{301} ☑ שלום"
        let cases: [(RichTextEditorController.ListStyle, String, String, String)] = [
            (.bulleted, "• ", "• ", "• "),
            (.dashed, "- ", "- ", "- "),
            (.numbered, "1. ", "2. ", "3. "),
            (.checklist, "○ ", "○ ", "○ ")
        ]

        for (style, firstPrefix, secondPrefix, continuation) in cases {
            let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            textView.isRichText = true
            textView.string = "\(first)\n\(second)"
            let controller = RichTextEditorController()
            controller.attach(textView)
            textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
            controller.applyList(style)
            let expected = "\(firstPrefix)\(first)\n\(secondPrefix)\(second)"
            guard textView.string == expected else {
                throw RichTextSmokeFailure.failed("List insertion changed text: \(textView.string)")
            }
            guard textView.selectedRange() == NSRange(location: 0, length: expected.utf16.count) else {
                throw RichTextSmokeFailure.failed("List insertion did not preserve the selected paragraphs")
            }

            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            textView.insertNewline(nil)
            guard textView.string == expected + "\n" + continuation else {
                throw RichTextSmokeFailure.failed("List did not continue: \(textView.string)")
            }
            textView.insertNewline(nil)
            guard textView.string == expected + "\n" else {
                throw RichTextSmokeFailure.failed("Empty list item did not exit the list: \(textView.string)")
            }

            textView.setSelectedRange(NSRange(location: 0, length: expected.utf16.count))
            controller.applyList(style)
            guard textView.string == "\(first)\n\(second)\n" else {
                throw RichTextSmokeFailure.failed("List could not be toggled off: \(textView.string)")
            }
            let entireRange = NSRange(location: 0, length: textView.string.utf16.count)
            guard let rtf = textView.rtf(from: entireRange),
                  let restored = NSAttributedString(rtf: rtf, documentAttributes: nil),
                  restored.string == textView.string else {
                throw RichTextSmokeFailure.failed("Unicode did not survive RTF round trip")
            }
        }
    }

    @MainActor
    private static func testChecklistParagraphs() throws {
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        let controller = RichTextEditorController()
        controller.attach(textView)

        controller.applyList(.checklist)
        let initialMarkerFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        guard textView.string == "○ ", textView.selectedRange().location == 2,
              abs((initialMarkerFont?.pointSize ?? 0) - 18) < 0.1 else {
            throw RichTextSmokeFailure.failed("Checklist could not be inserted before typing")
        }
        textView.insertText("First", replacementRange: textView.selectedRange())
        let typedFont = textView.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        guard textView.string == "○ First", abs((typedFont?.pointSize ?? 0) - 18) > 0.1 else {
            throw RichTextSmokeFailure.failed("Typing after an inserted checklist marker failed")
        }

        textView.string = "First\n\n   \nSecond\n"
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        controller.applyList(.checklist)
        let secondMarker = (textView.string as NSString).range(of: "○ Second").location
        let secondMarkerFont = secondMarker < textView.string.utf16.count
            ? textView.textStorage?.attribute(.font, at: secondMarker, effectiveRange: nil) as? NSFont
            : nil
        guard textView.string == "○ First\n\n   \n○ Second\n",
              abs((secondMarkerFont?.pointSize ?? 0) - 18) < 0.1 else {
            throw RichTextSmokeFailure.failed("Checklist added markers to empty paragraphs: \(textView.string)")
        }
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        controller.applyList(.checklist)
        guard textView.string == "First\n\n   \nSecond\n" else {
            throw RichTextSmokeFailure.failed("Checklist with blank paragraphs could not be toggled off")
        }

        textView.setSelectedRange(NSRange(location: 6, length: 0))
        controller.applyList(.checklist)
        guard textView.string == "First\n○ \n   \nSecond\n",
              textView.selectedRange().location == 8 else {
            throw RichTextSmokeFailure.failed("Checklist could not start on a blank paragraph")
        }

        textView.string = "First\n○ \nSecond"
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        controller.applyList(.checklist)
        guard textView.string == "○ First\n\n○ Second" else {
            throw RichTextSmokeFailure.failed("Checklist left a marker on an empty selected paragraph")
        }
    }

    @MainActor
    private static func testChecklistMarkerAppearance() throws {
        let content = NSMutableAttributedString(string: "○ First\n○ Second")
        content.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 13),
            range: NSRange(location: 0, length: content.length)
        )
        content.addAttribute(
            .font,
            value: NSFont(name: "LucidaGrande-Bold", size: 20)!,
            range: NSRange(location: 0, length: 1)
        )
        let secondMarker = (content.string as NSString).range(of: "○", options: [], range: NSRange(location: 1, length: content.length - 1)).location
        guard let rtf = content.rtf(from: NSRange(location: 0, length: content.length),
                                    documentAttributes: [:]) else {
            throw RichTextSmokeFailure.failed("Could not prepare checklist appearance test")
        }
        let editor = NativeTextEditor(
            noteID: UUID(), text: content.string, richTextData: rtf, focusGeneration: 0,
            controller: RichTextEditorController(), onChange: { _, _, _ in }, onEscape: {}
        )
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = editor.makeCoordinator()
        coordinator.textView = textView
        coordinator.applyContent(text: content.string, richTextData: rtf)
        guard let storage = textView.textStorage,
              let first = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              let second = storage.attribute(.font, at: secondMarker, effectiveRange: nil) as? NSFont,
              let body = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont,
              first.fontName == second.fontName,
              abs(first.pointSize - 18) < 0.1,
              abs(second.pointSize - 18) < 0.1,
              abs(body.pointSize - 13) < 0.1,
              storage.string == content.string else {
            throw RichTextSmokeFailure.failed("Checklist circles did not match while body text stayed intact")
        }
    }

    @MainActor
    private static func testHeadingContinuation() throws {
        for style in [RichTextEditorController.TextStyle.title, .heading, .subheading] {
            let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            textView.isRichText = true
            textView.insertText("Heading", replacementRange: NSRange(location: 0, length: 0))
            let controller = RichTextEditorController()
            controller.attach(textView)
            textView.setSelectedRange(NSRange(location: 7, length: 0))
            controller.apply(style)
            textView.insertNewline(nil)
            textView.insertText("Body text", replacementRange: textView.selectedRange())

            guard textView.string == "Heading\nBody text",
                  let headingFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                  let bodyFont = textView.textStorage?.attribute(.font, at: 8, effectiveRange: nil) as? NSFont,
                  abs(bodyFont.pointSize - NSFont.preferredFont(forTextStyle: .body).pointSize) < 0.1,
                  bodyFont.pointSize < headingFont.pointSize else {
                throw RichTextSmokeFailure.failed("\(style.rawValue) continued into the next paragraph")
            }
            let range = NSRange(location: 0, length: textView.string.utf16.count)
            guard let rtf = textView.rtf(from: range),
                  let restored = NSAttributedString(rtf: rtf, documentAttributes: nil),
                  restored.string == textView.string,
                  let restoredBody = restored.attribute(.font, at: 8, effectiveRange: nil) as? NSFont,
                  abs(restoredBody.pointSize - bodyFont.pointSize) < 0.1 else {
                throw RichTextSmokeFailure.failed("\(style.rawValue) body style did not survive save and reload")
            }
        }
    }

    @MainActor
    private static func testEmptyParagraphFormatting() throws {
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        let controller = RichTextEditorController()
        controller.attach(textView)

        controller.apply(.subheading)
        textView.insertText("First", replacementRange: textView.selectedRange())
        let savedRange = NSRange(location: 0, length: textView.string.utf16.count)
        guard let saved = textView.rtf(from: savedRange),
              let restored = NSAttributedString(rtf: saved, documentAttributes: nil) else {
            throw RichTextSmokeFailure.failed("Subheading could not be reloaded before continuing")
        }
        textView.textStorage?.setAttributedString(restored)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertNewline(nil)
        guard controller.currentFontSize == Int(NSFont.preferredFont(forTextStyle: .body).pointSize.rounded()) else {
            throw RichTextSmokeFailure.failed("New paragraph kept the subheading typing size")
        }
        textView.insertText("Body", replacementRange: textView.selectedRange())
        guard let firstFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              let bodyFont = textView.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont,
              textView.string == "First\nBody", firstFont.pointSize == 16,
              bodyFont.pointSize < firstFont.pointSize else {
            throw RichTextSmokeFailure.failed("A reopened subheading did not continue as body text")
        }

        textView.insertNewline(nil)
        controller.rememberPaletteSelection()
        controller.apply(.heading)
        controller.rememberPaletteSelection()
        controller.revealPaletteResult()
        textView.insertText("New heading", replacementRange: textView.selectedRange())
        guard textView.string == "First\nBody\nNew heading",
              let newFont = textView.textStorage?.attribute(.font, at: 11, effectiveRange: nil) as? NSFont,
              newFont.pointSize == 20,
              let previousFont = textView.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont,
              previousFont.pointSize == bodyFont.pointSize else {
            throw RichTextSmokeFailure.failed("Formatting an empty new line changed the previous paragraph")
        }

        let legacy = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        legacy.isRichText = true
        legacy.textStorage?.setAttributedString(NSAttributedString(
            string: "Older heading",
            attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold)]
        ))
        let legacyRange = NSRange(location: 0, length: legacy.string.utf16.count)
        guard let legacyRTF = legacy.rtf(from: legacyRange),
              let legacyRestored = NSAttributedString(rtf: legacyRTF, documentAttributes: nil) else {
            throw RichTextSmokeFailure.failed("Older subheading could not be restored")
        }
        legacy.textStorage?.setAttributedString(legacyRestored)
        legacy.setSelectedRange(NSRange(location: legacy.string.utf16.count, length: 0))
        legacy.insertNewline(nil)
        legacy.insertText("Body", replacementRange: legacy.selectedRange())
        guard let legacyBody = legacy.textStorage?.attribute(.font, at: 14, effectiveRange: nil) as? NSFont,
              legacyBody.pointSize == NSFont.preferredFont(forTextStyle: .body).pointSize else {
            throw RichTextSmokeFailure.failed("An older saved subheading continued into body text")
        }
    }

    @MainActor
    private static func testPaletteFollowsTypingSelection() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let textView = EscapeAwareTextView(frame: window.contentView!.bounds)
        textView.isRichText = true
        textView.string = "First\nSecond"
        textView.textStorage?.addAttribute(
            .font, value: NSFont.preferredFont(forTextStyle: .body),
            range: NSRange(location: 0, length: textView.string.utf16.count)
        )
        textView.textStorage?.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 16, weight: .semibold),
            range: NSRange(location: 0, length: 5)
        )
        window.contentView?.addSubview(textView)
        let controller = RichTextEditorController()
        controller.attach(textView)
        let editor = NativeTextEditor(
            noteID: UUID(), text: textView.string, richTextData: nil,
            focusGeneration: 0, controller: controller,
            onChange: { _, _, _ in }, onEscape: {}
        )
        let coordinator = editor.makeCoordinator()
        coordinator.textView = textView
        textView.delegate = coordinator
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.rememberPaletteSelection()
        textView.setSelectedRange(NSRange(location: 12, length: 0))

        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView?.addSubview(button)
        window.makeFirstResponder(button)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.ensurePaletteSelection()
        guard controller.currentFontSize == Int(NSFont.preferredFont(forTextStyle: .body).pointSize.rounded()) else {
            throw RichTextSmokeFailure.failed("Palette showed the font size from a previous paragraph")
        }
        controller.restorePaletteSelection()
        guard textView.selectedRange().location == 12 else {
            throw RichTextSmokeFailure.failed("Formatting palette kept the old cursor position")
        }
    }

    @MainActor
    private static func testBodyContinuationWithStaleTypingAttributes() throws {
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.insertText("Body", replacementRange: NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 16, weight: .semibold)]
        let controller = RichTextEditorController()
        controller.attach(textView)
        guard controller.currentFontSize == Int(NSFont.preferredFont(forTextStyle: .body).pointSize.rounded()) else {
            throw RichTextSmokeFailure.failed("Font size showed an old style instead of the text at the cursor")
        }
        textView.insertNewline(nil)
        textView.insertText("Still body", replacementRange: textView.selectedRange())
        guard textView.string == "Body\nStill body",
              let nextFont = textView.textStorage?.attribute(.font, at: 5, effectiveRange: nil) as? NSFont,
              nextFont.pointSize == NSFont.preferredFont(forTextStyle: .body).pointSize else {
            throw RichTextSmokeFailure.failed("A normal paragraph resumed an old subheading style")
        }
    }

    @MainActor
    private static func testBlockQuote() throws {
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.string = "First quote\nSecond quote"
        let controller = RichTextEditorController()
        controller.attach(textView)
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        controller.applyList(.blockQuote)
        guard textView.string == "First quote\nSecond quote",
              QuoteParagraphStyle.isQuoted(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle),
              QuoteParagraphStyle.isQuoted(textView.textStorage?.attribute(.paragraphStyle, at: 13, effectiveRange: nil) as? NSParagraphStyle) else {
            throw RichTextSmokeFailure.failed("Block quote inserted visible markers or did not style both paragraphs")
        }
        let range = NSRange(location: 0, length: textView.string.utf16.count)
        guard let rtf = textView.rtf(from: range),
              let restored = NSAttributedString(rtf: rtf, documentAttributes: nil),
              restored.string == textView.string,
              QuoteParagraphStyle.isQuoted(restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) else {
            throw RichTextSmokeFailure.failed("Block quote did not survive save and reload")
        }

        textView.setSelectedRange(range)
        controller.applyList(.blockQuote)
        guard !QuoteParagraphStyle.isQuoted(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) else {
            throw RichTextSmokeFailure.failed("Block quote could not be turned off")
        }

        textView.string = "> Old quote"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        controller.applyList(.blockQuote)
        guard textView.string == "Old quote", textView.selectedRange().location == 2,
              QuoteParagraphStyle.isQuoted(textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) else {
            throw RichTextSmokeFailure.failed("Legacy quote marker was not converted cleanly")
        }

        let emptyTextView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        emptyTextView.isRichText = true
        let emptyController = RichTextEditorController()
        emptyController.attach(emptyTextView)
        emptyController.applyList(.blockQuote)
        emptyTextView.insertText("Fresh quote", replacementRange: NSRange(location: 0, length: 0))
        guard emptyTextView.string == "Fresh quote",
              QuoteParagraphStyle.isQuoted(emptyTextView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) else {
            throw RichTextSmokeFailure.failed("Block quote did not work in an empty note")
        }

        let longQuote = "A block quote should wrap as a readable paragraph at the minimum note width, while keeping the rest of the formatting intact."
        let narrowView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 280))
        narrowView.isRichText = true
        narrowView.textContainer?.containerSize = NSSize(width: 240, height: CGFloat.greatestFiniteMagnitude)
        narrowView.textContainer?.widthTracksTextView = true
        narrowView.string = longQuote
        let narrowController = RichTextEditorController()
        narrowController.attach(narrowView)
        narrowView.setSelectedRange(NSRange(location: 0, length: longQuote.utf16.count))
        narrowController.applyList(.blockQuote)
        guard let layout = narrowView.layoutManager, let container = narrowView.textContainer else {
            throw RichTextSmokeFailure.failed("Quote layout could not be measured")
        }
        layout.ensureLayout(for: container)
        var lineCount = 0
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, _, _ in
            lineCount += 1
        }
        guard lineCount > 1, lineCount < 15,
              (narrowView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.isEmpty == true else {
            throw RichTextSmokeFailure.failed("Block quote squeezed text into narrow columns: \(lineCount) lines")
        }

        let legacy = NSMutableAttributedString(string: longQuote)
        let legacyStyle = NSMutableParagraphStyle()
        legacyStyle.alignment = .center
        let oldBlock = NSTextBlock()
        oldBlock.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
        legacyStyle.textBlocks = [oldBlock]
        legacy.addAttribute(.paragraphStyle, value: legacyStyle, range: NSRange(location: 0, length: legacy.length))
        legacy.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: NSRange(location: 0, length: 5))
        guard QuoteParagraphStyle.repairLegacyBlocks(in: legacy),
              let repaired = legacy.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
              repaired.textBlocks.isEmpty, QuoteParagraphStyle.isQuoted(repaired),
              repaired.alignment == .center,
              legacy.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil,
              legacy.string == longQuote else {
            throw RichTextSmokeFailure.failed("Legacy quote repair changed text or unrelated formatting")
        }

        let archived = NSMutableAttributedString(string: longQuote)
        archived.addAttribute(.paragraphStyle, value: legacyStyle, range: NSRange(location: 0, length: archived.length))
        let archivedData = try archived.data(
            from: NSRange(location: 0, length: archived.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        guard let decodedLegacy = NSAttributedString(rtf: archivedData, documentAttributes: nil) else {
            throw RichTextSmokeFailure.failed("Legacy quote RTF could not be decoded")
        }
        let migrated = NSMutableAttributedString(attributedString: decodedLegacy)
        QuoteParagraphStyle.repairLegacyBlocks(in: migrated)
        let migratedStyle = migrated.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        guard migrated.string == longQuote, migratedStyle?.textBlocks.isEmpty == true,
              QuoteParagraphStyle.isQuoted(migratedStyle) else {
            throw RichTextSmokeFailure.failed("Saved legacy quote did not migrate cleanly")
        }
    }

    @MainActor
    private static func testNumericFontSize() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.string = "Size"
        let controller = RichTextEditorController()
        controller.attach(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        controller.setFontSize(23)
        guard controller.currentFontSize == 23 else {
            throw RichTextSmokeFailure.failed("Numeric font size was not applied")
        }
        controller.setFontSize(100)
        guard controller.currentFontSize == 23 else {
            throw RichTextSmokeFailure.failed("Out-of-range font size was accepted")
        }
        controller.setFontSize(48)
        controller.changeFontSize(by: 1)
        guard controller.currentFontSize == 49 else {
            throw RichTextSmokeFailure.failed("Increase Size stopped at 48 while the numeric control allowed 72")
        }
    }

    @MainActor
    private static func testAllTextStylesAndAlignments() throws {
        let styles: [(RichTextEditorController.TextStyle, CGFloat)] = [
            (.title, 26), (.heading, 20), (.subheading, 16), (.body, 13), (.monostyled, 13)
        ]
        for (style, size) in styles {
            let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            textView.isRichText = true
            textView.string = "○ Task\nBody"
            let controller = RichTextEditorController()
            controller.attach(textView)
            textView.setSelectedRange(NSRange(location: 0, length: 6))
            controller.apply(style)
            guard let storage = textView.textStorage,
                  let marker = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                  let body = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont,
                  abs(marker.pointSize - 18) < 0.1,
                  abs(body.pointSize - size) < 0.1 else {
                throw RichTextSmokeFailure.failed("\(style.rawValue) changed the checklist marker or missed its body")
            }
            let range = NSRange(location: 0, length: storage.length)
            guard let rtf = textView.rtf(from: range),
                  let restored = NSAttributedString(rtf: rtf, documentAttributes: nil),
                  restored.string == textView.string else {
                throw RichTextSmokeFailure.failed("\(style.rawValue) failed the rich text round trip")
            }
        }

        for alignment in [NSTextAlignment.left, .center, .right, .justified] {
            let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            textView.isRichText = true
            textView.string = "First\nSecond"
            let controller = RichTextEditorController()
            controller.attach(textView)
            textView.setSelectedRange(NSRange(location: 1, length: 0))
            controller.setAlignment(alignment)
            let first = textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            let second = textView.textStorage?.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle
            guard first?.alignment == alignment,
                  second?.alignment != alignment || alignment == .left else {
                throw RichTextSmokeFailure.failed("Alignment affected the wrong paragraph")
            }
        }
    }

    @MainActor
    private static func testFormatBoundariesAndLists() throws {
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.string = "○ Task\nNext"
        let controller = RichTextEditorController()
        controller.attach(textView)
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)

        textView.setSelectedRange(fullRange)
        controller.apply(.heading)
        controller.toggleBold()
        controller.toggleItalic()
        controller.setFontSize(24)
        controller.toggleUnderline()
        controller.toggleStrikethrough()
        controller.applyHighlight(.yellow)
        guard let storage = textView.textStorage,
              let markerFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              abs(markerFont.pointSize - 18) < 0.1,
              storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil,
              storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil,
              storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil else {
            throw RichTextSmokeFailure.failed("Text formats changed the checklist circle")
        }
        let lineBreak = (textView.string as NSString).range(of: "\n").location
        guard storage.attribute(.underlineStyle, at: lineBreak, effectiveRange: nil) == nil,
              storage.attribute(.strikethroughStyle, at: lineBreak, effectiveRange: nil) == nil,
              storage.attribute(.backgroundColor, at: lineBreak, effectiveRange: nil) == nil else {
            throw RichTextSmokeFailure.failed("Inline formatting crossed the line break")
        }
        textView.setSelectedRange(NSRange(location: 0, length: 1))
        guard controller.currentFontSize == 24 else {
            throw RichTextSmokeFailure.failed("Font size control reported the checklist circle size")
        }
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        guard controller.currentFontSize == 24 else {
            throw RichTextSmokeFailure.failed("Font size control reported the checklist prefix size")
        }
        textView.setSelectedRange(NSRange(location: 0, length: 1))
        controller.clearFormatting()
        guard let clearedMarker = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              abs(clearedMarker.pointSize - 18) < 0.1 else {
            throw RichTextSmokeFailure.failed("Clear Formatting changed the checklist circle")
        }

        for (style, first, second) in [
            (RichTextEditorController.ListStyle.bulleted, "• ", "• "),
            (.dashed, "- ", "- "),
            (.numbered, "1. ", "2. ")
        ] {
            let listView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            listView.isRichText = true
            listView.string = "Alpha\n\nBeta"
            let listController = RichTextEditorController()
            listController.attach(listView)
            listView.setSelectedRange(NSRange(location: 0, length: listView.string.utf16.count))
            listController.applyList(style)
            guard listView.string == "\(first)Alpha\n\n\(second)Beta" else {
                throw RichTextSmokeFailure.failed("List numbered or marked an empty paragraph: \(listView.string)")
            }
        }

        let pasteView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        pasteView.isRichText = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("○ One\n○ Two", forType: .string)
        pasteView.pastePlainText(nil)
        let secondMarker = (pasteView.string as NSString).range(of: "○ Two").location
        guard secondMarker != NSNotFound,
              let firstFont = pasteView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              let secondFont = pasteView.textStorage?.attribute(.font, at: secondMarker, effectiveRange: nil) as? NSFont,
              firstFont.fontName == secondFont.fontName,
              abs(firstFont.pointSize - 18) < 0.1 else {
            throw RichTextSmokeFailure.failed("Pasted checklist circles did not match")
        }
        let matchingView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        matchingView.isRichText = true
        matchingView.pasteMatchingStyle(nil)
        let matchingSecond = (matchingView.string as NSString).range(of: "○ Two").location
        guard matchingSecond != NSNotFound,
              let matchingFirstFont = matchingView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              let matchingSecondFont = matchingView.textStorage?.attribute(.font, at: matchingSecond, effectiveRange: nil) as? NSFont,
              matchingFirstFont.fontName == matchingSecondFont.fontName,
              abs(matchingFirstFont.pointSize - 18) < 0.1 else {
            throw RichTextSmokeFailure.failed("Match Note Style paste left mismatched checklist circles")
        }

        let copied = NSMutableAttributedString(string: "○ One\n○ Two")
        copied.addAttribute(.font, value: NSFont.systemFont(ofSize: 24), range: NSRange(location: 0, length: 1))
        copied.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: NSRange(location: 6, length: 1))
        guard let copiedRTF = copied.rtf(from: NSRange(location: 0, length: copied.length), documentAttributes: [:]) else {
            throw RichTextSmokeFailure.failed("Could not prepare rich checklist paste")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(copiedRTF, forType: .rtf)
        let richPasteView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        richPasteView.isRichText = true
        richPasteView.paste(nil)
        let richSecond = (richPasteView.string as NSString).range(of: "○ Two").location
        guard richSecond != NSNotFound,
              let richFirstFont = richPasteView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              let richSecondFont = richPasteView.textStorage?.attribute(.font, at: richSecond, effectiveRange: nil) as? NSFont,
              richFirstFont.fontName == richSecondFont.fontName,
              abs(richFirstFont.pointSize - 18) < 0.1 else {
            throw RichTextSmokeFailure.failed("Keep Formatting paste left mismatched checklist circles")
        }

        let undoWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let undoView = EscapeAwareTextView(frame: undoWindow.contentView!.bounds)
        undoView.isRichText = true
        undoView.allowsUndo = true
        undoView.string = "○ Task"
        undoView.textStorage?.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 25), range: NSRange(location: 0, length: 1)
        )
        undoWindow.contentView?.addSubview(undoView)
        undoWindow.makeFirstResponder(undoView)
        let undoController = RichTextEditorController()
        undoController.attach(undoView)
        undoView.setSelectedRange(NSRange(location: 0, length: undoView.string.utf16.count))
        undoController.toggleBold()
        undoView.undoManager?.undo()
        guard let undoMarker = undoView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
              abs(undoMarker.pointSize - 18) < 0.1 else {
            throw RichTextSmokeFailure.failed("Undo restored the uneven checklist circle")
        }
    }

    @MainActor
    private static func testImagePersistence() throws {
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        textView.isRichText = true
        textView.importsGraphics = true
        textView.string = "○ Task"
        guard textView.toggleChecklist(at: 0), textView.string == "◉ Task",
              textView.toggleChecklist(at: 0), textView.string == "○ Task" else {
            throw RichTextSmokeFailure.failed("Checklist circle did not toggle")
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1200,
            pixelsHigh: 800,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw RichTextSmokeFailure.failed("Could not create sample image")
        }
        bitmap.setColor(NSColor(calibratedRed: 0, green: 0.45, blue: 1, alpha: 1), atX: 0, y: 0)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RichTextSmokeFailure.failed("Could not encode sample image")
        }
        let attachment = NSTextAttachment(data: png, ofType: "public.png")
        textView.textStorage?.setAttributedString(NSAttributedString(attachment: attachment))
        textView.resizeAttachmentsToFit()
        guard attachment.bounds.width <= 480, attachment.bounds.height <= 360 else {
            throw RichTextSmokeFailure.failed("Pasted image exceeded the editor bounds")
        }
        let range = NSRange(location: 0, length: textView.string.utf16.count)
        guard let data = textView.rtfd(from: range),
              let restored = NSAttributedString(rtfd: data, documentAttributes: nil),
              restored.string == textView.string,
              restored.attribute(.attachment, at: 0, effectiveRange: nil) != nil else {
            throw RichTextSmokeFailure.failed("Pasted image did not survive RTFD round trip")
        }
        let controller = RichTextEditorController()
        controller.attach(textView)
        textView.setSelectedRange(range)
        textView.copy(nil)
        guard let copied = NSPasteboard.general.data(forType: .png),
              NSImage(data: copied) != nil else {
            throw RichTextSmokeFailure.failed("Selected image could not be copied out as PNG")
        }
        controller.clearFormatting()
        guard textView.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil) != nil else {
            throw RichTextSmokeFailure.failed("Clear Formatting removed an embedded image")
        }
    }

    @MainActor
    private static func testUnderlineLineBreak() throws {
        let content = NSMutableAttributedString(string: "Title\nBody")
        content.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 6)
        )
        guard let rtf = content.rtf(from: NSRange(location: 0, length: content.length),
                                    documentAttributes: [:]) else {
            throw RichTextSmokeFailure.failed("Could not prepare underlined test note")
        }
        let editor = NativeTextEditor(
            noteID: UUID(), text: content.string, richTextData: rtf, focusGeneration: 0,
            controller: RichTextEditorController(), onChange: { _, _, _ in }, onEscape: {}
        )
        let textView = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let coordinator = editor.makeCoordinator()
        coordinator.textView = textView
        coordinator.applyContent(text: content.string, richTextData: rtf)
        guard textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil,
              textView.textStorage?.attribute(.underlineStyle, at: 5, effectiveRange: nil) == nil else {
            throw RichTextSmokeFailure.failed("Underline continued across a line break")
        }
    }
}
