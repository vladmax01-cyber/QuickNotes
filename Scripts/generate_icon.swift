import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let tile = CGPath(roundedRect: CGRect(x: 54, y: 54, width: 916, height: 916), cornerWidth: 205, cornerHeight: 205, transform: nil)
context.addPath(tile)
context.clip()
let colors = [
    NSColor(calibratedRed: 0.10, green: 0.24, blue: 0.43, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.075, green: 0.105, blue: 0.17, alpha: 1).cgColor
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 80, y: 970), end: CGPoint(x: 940, y: 70), options: [])

context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: NSColor.black.withAlphaComponent(0.26).cgColor)
context.setFillColor(NSColor(calibratedWhite: 0.98, alpha: 1).cgColor)
context.addPath(CGPath(roundedRect: CGRect(x: 232, y: 189, width: 560, height: 652), cornerWidth: 86, cornerHeight: 86, transform: nil))
context.fillPath()
context.setShadow(offset: .zero, blur: 0)

func roundedBar(_ rect: CGRect, color: NSColor) {
    context.setFillColor(color.cgColor)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    context.fillPath()
}

let blue = NSColor(calibratedRed: 0.10, green: 0.43, blue: 0.92, alpha: 1)
roundedBar(CGRect(x: 314, y: 665, width: 124, height: 56), color: blue)
let ink = NSColor(calibratedRed: 0.18, green: 0.27, blue: 0.39, alpha: 1)
roundedBar(CGRect(x: 314, y: 555, width: 396, height: 43), color: ink)
roundedBar(CGRect(x: 314, y: 455, width: 342, height: 43), color: ink)
roundedBar(CGRect(x: 314, y: 355, width: 246, height: 43), color: ink)

NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.dropFirst().first ?? "Resources/QuickNotes-1024.png"
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
