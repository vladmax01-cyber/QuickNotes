import AppKit
import SwiftUI

@main
struct FormatVisualSmoke {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let symbols = ["bold", "italic", "underline", "strikethrough", "highlighter",
                       "checklist", "list.bullet", "list.number"]
        var checks = 0
        let sheet = NSImage(size: NSSize(width: 8 * 44, height: 2 * 44))
        sheet.lockFocusFlipped(true)
        for (row, scheme) in [ColorScheme.light, .dark].enumerated() {
            for (column, symbol) in symbols.enumerated() {
                let color: Color = scheme == .dark ? .white : .black
                let background: Color = scheme == .dark ? Color(white: 0.20) : Color(white: 0.94)
                let renderer = ImageRenderer(content: FormatControlGlyph(symbol: symbol)
                    .foregroundStyle(color).frame(width: 28, height: 28).background(background)
                    .environment(\.colorScheme, scheme))
                renderer.scale = 2
                guard let cg = renderer.cgImage else { throw failure("Glyph could not render: \(symbol)") }
                precondition(cg.width == 56 && cg.height == 56)
                checks += 1
                let bitmap = NSBitmapImageRep(cgImage: cg)
                let corner = bitmap.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
                var ink = 0
                var minX = 56, maxX = 0, minY = 56, maxY = 0
                for y in 0..<56 {
                    for x in 0..<56 {
                        let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if abs(pixel.redComponent - corner.redComponent) > 0.15 {
                            ink += 1
                            minX = min(minX, x); maxX = max(maxX, x)
                            minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                }
                guard ink > 15, minX > 2, maxX < 53, minY > 2, maxY < 53 else {
                    throw failure("Missing or clipped glyph: \(symbol), bounds \(minX),\(minY),\(maxX),\(maxY)")
                }
                checks += 1
                NSImage(cgImage: cg, size: NSSize(width: 28, height: 28)).draw(
                    in: NSRect(x: column * 44 + 8, y: row * 44 + 8, width: 28, height: 28))
            }
        }
        sheet.unlockFocus()
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QUICK_NOTES_TEST_OUTPUT"]
            ?? "/tmp/QuickNotesContentSmoke")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("Format Symbols.png"))
        print("Format symbol rendering passed: \(checks) checks, 8 symbols in light and dark")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "FormatVisualSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
