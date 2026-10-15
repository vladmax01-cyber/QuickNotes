import AppKit
import UniformTypeIdentifiers

@MainActor
enum NoteExport {
    static var isPresenting = false
    private static var sharingPicker: NSSharingServicePicker?
    private static let sharingDelegate = NoteSharingDelegate()

    static func pdf(_ content: NSAttributedString, to url: URL) throws {
        let fullContent = NSRange(location: 0, length: content.length)
        let archived = try content.data(from: fullContent,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let printable = NoteRichContent.decode(text: content.string, data: archived)
        let light = NSAppearance(named: .aqua)!
        light.performAsCurrentDrawingAppearance {
            let full = NSRange(location: 0, length: printable.length)
            printable.enumerateAttributes(in: full) { attributes, range, _ in
                if let color = attributes[.foregroundColor] as? NSColor {
                    printable.addAttribute(.foregroundColor, value: color.usingColorSpace(.deviceRGB)
                        ?? NSColor.black, range: range)
                }
                if let background = attributes[.backgroundColor] as? NSColor {
                    printable.addAttribute(.backgroundColor,
                        value: background.usingColorSpace(.deviceRGB) ?? background, range: range)
                }
            }
        }
        InlineFormatBoundary.normalize(in: printable)
        NoteTable.normalize(printable, width: 540)
        let view = EscapeAwareTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 720))
        view.appearance = light
        view.isRichText = true
        view.drawsBackground = true
        view.backgroundColor = .white
        view.textContainerInset = NSSize(width: 0, height: 0)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: 540, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = NSSize(width: 540, height: 0)
        view.maxSize = NSSize(width: 540, height: CGFloat.greatestFiniteMagnitude)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textStorage?.setAttributedString(printable)
        view.resizeAttachmentsToFit()
        if let container = view.textContainer, let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            view.setFrameSize(NSSize(width: 540, height: max(1, ceil(layout.usedRect(for: container).maxY))))
        }
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func save(_ content: NSAttributedString, title: String, kind: String) {
        guard !isPresenting else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeName(title) + "." + kind
        panel.allowedContentTypes = kind == "pdf" ? [.pdf] : kind == "txt" ? [.plainText] : [.rtfd]
        isPresenting = true
        defer { isPresenting = false }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch kind {
            case "pdf": try pdf(content, to: url)
            case "txt":
                try NoteRichContent.plainText(content)
                    .write(to: url, atomically: true, encoding: .utf8)
            default:
                let wrapper = try content.fileWrapper(from: NSRange(location: 0, length: content.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
                try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            }
        } catch { NSApp.presentError(error) }
    }

    static func share(_ content: NSAttributedString, title: String, asPDF: Bool) {
        guard !isPresenting else { return }
        guard let view = NSApp.windows.first(where: { $0.isVisible && $0.title == "Quick Notes" })?.contentView
            ?? NSApp.keyWindow?.contentView else { return }
        isPresenting = true
        do {
            let items: [Any]
            if asPDF {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Quick Notes Sharing")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let oldFiles = (try? FileManager.default.contentsOfDirectory(at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                for file in oldFiles where file.pathExtension == "pdf" || UUID(uuidString: file.lastPathComponent) != nil {
                    if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate, Date().timeIntervalSince(modified) > 86_400 {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
                let session = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
                let url = session.appendingPathComponent(safeName(title) + ".pdf")
                try pdf(content, to: url)
                items = [url]
            } else {
                items = [NoteRichContent.plainText(content)]
            }
            let picker = NSSharingServicePicker(items: items)
            sharingPicker = picker
            picker.delegate = sharingDelegate
            isPresenting = true
            DispatchQueue.main.async {
                guard view.window?.isVisible == true else { isPresenting = false; return }
                picker.show(relativeTo: NSRect(x: view.bounds.maxX - 40,
                    y: view.isFlipped ? 12 : view.bounds.maxY - 36, width: 24, height: 24),
                    of: view, preferredEdge: .minY)
            }
        } catch {
            isPresenting = false
            NSApp.presentError(error)
        }
    }

    static func safeName(_ title: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))
        let cleaned = title.components(separatedBy: forbidden)
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var name = String(cleaned.prefix(80))
        while name.utf8.count > 180 { name.removeLast() }
        return name.isEmpty || name.allSatisfy({ $0 == "." }) ? "Quick Note" : name
    }

}

@MainActor
private final class NoteSharingDelegate: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        NoteExport.isPresenting = false
    }
}
