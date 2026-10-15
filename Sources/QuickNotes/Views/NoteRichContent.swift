import AppKit

enum NoteRichContent {
    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.preferredFont(forTextStyle: .body),
         .foregroundColor: NSColor.labelColor, .paragraphStyle: NSParagraphStyle.default]
    }

    static func decode(text: String, data: Data?) -> NSMutableAttributedString {
        let result: NSMutableAttributedString
        if let data,
           let decoded = NSAttributedString(rtfd: data, documentAttributes: nil)
            ?? NSAttributedString(rtf: data, documentAttributes: nil), decoded.string == text {
            result = NSMutableAttributedString(attributedString: decoded)
        } else {
            result = NSMutableAttributedString(string: text, attributes: bodyAttributes)
        }
        normalize(result)
        return result
    }

    static func normalize(_ content: NSMutableAttributedString) {
        guard content.length > 0 else { return }
        let full = NSRange(location: 0, length: content.length)
        content.enumerateAttributes(in: full) { attributes, range, _ in
            if attributes[.font] == nil {
                content.addAttribute(.font, value: NSFont.preferredFont(forTextStyle: .body), range: range)
            }
            let color = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.deviceRGB)
            // Web pages and RTF encode their default text as literal black or white.
            if color == nil || (color.map {
                max($0.redComponent, $0.greenComponent, $0.blueComponent)
                    - min($0.redComponent, $0.greenComponent, $0.blueComponent) < 0.08
            } ?? false) {
                content.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            } else if let color,
                      let semantic = RichTextEditorController.TextColor.allCases.first(where: {
                          $0 != .automatic && $0.matches(color)
                      }) {
                content.addAttribute(.foregroundColor, value: semantic.nsColor, range: range)
            }
            if let background = (attributes[.backgroundColor] as? NSColor)?.usingColorSpace(.deviceRGB),
               max(background.redComponent, background.greenComponent, background.blueComponent)
                - min(background.redComponent, background.greenComponent, background.blueComponent) < 0.05,
               background.redComponent < 0.1 || background.redComponent > 0.94 {
                content.removeAttribute(.backgroundColor, range: range)
            }
        }
        QuoteParagraphStyle.repairLegacyBlocks(in: content)
        NoteTable.normalize(content)
        ListMarkerAppearance.normalize(in: content)
        InlineFormatBoundary.normalize(in: content)
    }

    static func clipboardContent(from board: NSPasteboard, standardizeFont: Bool = true) -> NSMutableAttributedString? {
        func prepare(_ value: NSMutableAttributedString) {
            if standardizeFont { normalizePaste(value) } else { normalize(value) }
        }
        let html = board.data(forType: .html)
        let htmlText = html.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let htmlHasTable = htmlText.localizedCaseInsensitiveContains("<table")
        let htmlHasImage = htmlText.localizedCaseInsensitiveContains("<img")
        var richFallback: NSMutableAttributedString?
        if let data = board.data(forType: .rtfd),
           let content = NSAttributedString(rtfd: data, documentAttributes: nil) {
            let value = NSMutableAttributedString(attributedString: content)
            prepare(value)
            var hasTable = false
            value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { item, _, _ in
                if (item as? NSParagraphStyle)?.textBlocks.contains(where: { $0 is NSTextTableBlock }) == true {
                    hasTable = true
                }
            }
            if (!htmlHasTable || hasTable) && (!htmlHasImage || value.string.contains("\u{FFFC}")) { return value }
            richFallback = value
        }
        // Browser RTF can be a flattened fallback even when its HTML contains a table.
        if let html, htmlHasTable || htmlHasImage,
           let value = try? NSMutableAttributedString(
                data: html, options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil) {
            prepare(value)
            NoteTable.normalize(value)
            return value
        }
        if let richFallback { return richFallback }
        for (type, documentType) in [(NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd),
                                     (.rtf, .rtf), (.html, .html)] {
            guard let data = board.data(forType: type),
                  let value = try? NSMutableAttributedString(data: data,
                    options: [.documentType: documentType], documentAttributes: nil) else { continue }
            prepare(value)
            NoteTable.normalize(value)
            return value
        }
        guard let text = board.string(forType: .string) else { return nil }
        if let table = NoteTable.fromDelimitedText(text, requiresMarkdown: true) { return table }
        if let document = NoteTable.fromMarkdownDocument(text) { return document }
        if text.contains("\t"), !text.hasPrefix("\t"), let table = NoteTable.fromDelimitedText(text) { return table }
        return NSMutableAttributedString(string: text, attributes: bodyAttributes)
    }

    static func normalizePaste(_ content: NSMutableAttributedString) {
        normalize(content)
        content.enumerateAttribute(.font, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            let source = value as? NSFont ?? .preferredFont(forTextStyle: .body)
            let traits = NSFontManager.shared.traits(of: source)
            let base = NSFont.systemFont(ofSize: min(72, max(9, source.pointSize)))
            let semanticTraits = traits.intersection([.boldFontMask, .italicFontMask])
            let font = NSFontManager.shared.convert(base, toHaveTrait: semanticTraits)
            content.addAttribute(.font, value: font, range: range)
        }
    }

    static func write(_ content: NSAttributedString, to board: NSPasteboard) {
        let range = NSRange(location: 0, length: content.length)
        board.clearContents()
        board.setString(plainText(content), forType: .string)
        for (type, documentType) in [(NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd),
                                     (.rtf, .rtf), (.html, .html)] {
            if let data = try? content.data(from: range, documentAttributes: [.documentType: documentType]) {
                board.setData(type == .html ? embeddedHTML(data, content: content) : data, forType: type)
            }
        }
    }

    private static func embeddedHTML(_ data: Data, content: NSAttributedString) -> Data {
        guard var html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: .caseInsensitive) else { return data }
        var images: [Data] = []
        content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let source = attachment.fileWrapper?.regularFileContents
                ?? attachment.image?.tiffRepresentation
            guard let source, let bitmap = NSBitmapImageRep(data: source),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            images.append(png)
        }
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: html.utf16.count))
        guard matches.count == images.count else { return data }
        for index in matches.indices.reversed() {
            guard let range = Range(matches[index].range, in: html) else { continue }
            html.replaceSubrange(range, with: "<img alt=\"Image\" style=\"max-width:100%;height:auto\" src=\"data:image/png;base64,\(images[index].base64EncodedString())\">")
        }
        return html.data(using: .utf8) ?? data
    }

    static func plainText(_ content: NSAttributedString) -> String {
        let source = content.string as NSString
        var output = ""
        var currentTable: NSTextTable?
        var rows: [Int: [Int: String]] = [:]
        func flushTable() {
            guard let table = currentTable else { return }
            for row in rows.keys.sorted() {
                output += (0..<table.numberOfColumns).map { rows[row]?[$0] ?? "" }.joined(separator: "\t") + "\n"
            }
            currentTable = nil
            rows.removeAll(keepingCapacity: true)
        }
        var location = 0
        while location < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
            let line = source.substring(with: paragraph).replacingOccurrences(of: "\u{FFFC}", with: "[Image]")
            let style = content.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            if let block = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                if currentTable !== block.table { flushTable(); currentTable = block.table }
                let text = line.trimmingCharacters(in: .newlines)
                let prior = rows[block.startingRow]?[block.startingColumn] ?? ""
                rows[block.startingRow, default: [:]][block.startingColumn] = prior.isEmpty ? text : prior + " " + text
            } else {
                flushTable()
                output += line
            }
            location = NSMaxRange(paragraph)
        }
        flushTable()
        return output
    }

    static func tableContents(_ content: NSAttributedString) -> NSAttributedString {
        let source = content.string as NSString
        var rows: [Int: [Int: NSMutableAttributedString]] = [:]
        var columns = 0
        var location = 0
        while location < source.length {
            let range = source.paragraphRange(for: NSRange(location: location, length: 0))
            let style = content.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            if let block = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                columns = max(columns, block.table.numberOfColumns)
                let cell = rows[block.startingRow]?[block.startingColumn] ?? NSMutableAttributedString()
                if rows[block.startingRow]?[block.startingColumn] != nil { cell.append(NSAttributedString(string: "\u{2028}", attributes: bodyAttributes)) }
                var length = range.length
                while length > 0 && [10, 13, 0x85, 0x2028, 0x2029].contains(source.character(at: range.location + length - 1)) {
                    length -= 1
                }
                let part = NSMutableAttributedString(attributedString: content.attributedSubstring(
                    from: NSRange(location: range.location, length: length)))
                part.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: part.length)) { value, run, _ in
                    let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                        ?? NSMutableParagraphStyle()
                    paragraph.textBlocks = []
                    part.addAttribute(.paragraphStyle, value: paragraph, range: run)
                }
                cell.append(part)
                rows[block.startingRow, default: [:]][block.startingColumn] = cell
            }
            location = NSMaxRange(range)
        }
        let result = NSMutableAttributedString()
        for row in rows.keys.sorted() {
            for column in 0..<columns {
                if column > 0 { result.append(NSAttributedString(string: "\t", attributes: bodyAttributes)) }
                if let cell = rows[row]?[column] { result.append(cell) }
            }
            result.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
        }
        InlineFormatBoundary.normalize(in: result)
        return result
    }
}

enum NoteTable {
    static func make(rows: [[String]], header: Bool = true) -> NSMutableAttributedString {
        let columnCount = rows.map(\.count).max() ?? 0
        let result = NSMutableAttributedString()
        guard columnCount > 0 else { return result }
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true
        table.setValue(100, type: .percentageValueType, for: .width)
        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<columnCount {
                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1,
                                            startingColumn: column, columnSpan: 1)
                configure(block, header: header && rowIndex == 0)
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.paragraphSpacing = 3
                var attributes = NoteRichContent.bodyAttributes
                attributes[.paragraphStyle] = style
                if header && rowIndex == 0 { attributes[.font] = NSFont.boldSystemFont(ofSize: 13) }
                let text = column < row.count ? row[column] : ""
                result.append(NSAttributedString(string: text + "\n", attributes: attributes))
            }
        }
        result.append(NSAttributedString(string: "\n", attributes: NoteRichContent.bodyAttributes))
        return result
    }

    static func configure(_ block: NSTextTableBlock, header: Bool?, width: CGFloat? = nil) {
        let contentWidth = width.map {
            max(12, $0 * CGFloat(block.columnSpan) / CGFloat(max(1, block.table.numberOfColumns)) - 13)
        } ?? 0
        block.setValue(contentWidth, type: .absoluteValueType, for: .width)
        block.setValue(0, type: .absoluteValueType, for: .minimumWidth)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setBorderColor(.separatorColor)
        if let header { block.backgroundColor = header ? NSColor.quaternaryLabelColor : .clear }
    }

    @discardableResult
    static func normalize(_ content: NSMutableAttributedString, width: CGFloat? = nil) -> Bool {
        var hasTable = false
        guard content.length > 0 else { return false }
        content.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: content.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            for case let block as NSTextTableBlock in style.textBlocks {
                hasTable = true
                block.table.layoutAlgorithm = .fixedLayoutAlgorithm
                block.table.setValue(width ?? 100, type: width == nil ? .percentageValueType : .absoluteValueType,
                                     for: .width)
                configure(block, header: nil, width: width)
            }
        }
        return hasTable
    }

    static func fromDelimitedText(_ text: String, requiresMarkdown: Bool = false) -> NSMutableAttributedString? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let markdownSeparator = lines.firstIndex { line in
            line.contains("|") && line.contains("-") && line.replacingOccurrences(of: #"[\s|:\-]"#,
                                                           with: "", options: .regularExpression).isEmpty
        }
        if requiresMarkdown && markdownSeparator == nil { return nil }
        let separator: Character = lines.first?.contains("\t") == true ? "\t" : "|"
        let rows = lines.enumerated().compactMap { index, line -> [String]? in
            if index == markdownSeparator { return nil }
            var cells = line.split(separator: separator, omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if separator == "|" {
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
            }
            return cells
        }
        guard rows.count >= 2, let columns = rows.first?.count, (2...12).contains(columns),
              rows.allSatisfy({ $0.count == columns }) else { return nil }
        return make(rows: rows)
    }

    static func fromMarkdownDocument(_ text: String) -> NSMutableAttributedString? {
        let lines = text.components(separatedBy: .newlines)
        let result = NSMutableAttributedString()
        var cursor = 0
        var converted = false
        var fenced = false
        while cursor < lines.count {
            if lines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle() }
            if !fenced, cursor + 1 < lines.count, lines[cursor].contains("|"),
               lines[cursor + 1].contains("-"),
               lines[cursor + 1].replacingOccurrences(of: #"[\s|:\-]"#, with: "",
                   options: .regularExpression).isEmpty {
                var end = cursor + 2
                while end < lines.count && lines[end].contains("|") { end += 1 }
                if let table = fromDelimitedText(lines[cursor..<end].joined(separator: "\n"), requiresMarkdown: true) {
                    result.append(table)
                    cursor = end
                    converted = true
                    continue
                }
            }
            result.append(NSAttributedString(string: lines[cursor] + (cursor + 1 < lines.count ? "\n" : ""),
                                             attributes: NoteRichContent.bodyAttributes))
            cursor += 1
        }
        return converted ? result : nil
    }
}

struct NoteReadingPosition: Codable {
    var location: Int
    var verticalOffset: Double
    var anchor: Int? = nil
    var anchorOffset: Double? = nil
    var atBottom: Bool? = nil
}

enum NoteReadingPositions {
    static func read(_ id: UUID, defaults: UserDefaults) -> NoteReadingPosition? {
        guard let data = defaults.data(forKey: "noteReadingPosition.\(id.uuidString)") else { return nil }
        return try? JSONDecoder().decode(NoteReadingPosition.self, from: data)
    }

    static func save(_ position: NoteReadingPosition, id: UUID, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(position) {
            defaults.set(data, forKey: "noteReadingPosition.\(id.uuidString)")
        }
    }
}
