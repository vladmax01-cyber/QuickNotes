import AppKit

@main
struct PalettePlacementSmoke {
    static func main() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let palette = NSSize(width: 266, height: 360)

        let roomOnRight = NSRect(x: 100, y: 300, width: 280, height: 280)
        precondition(FormattingPalettePlacement.side(of: roomOnRight, paletteWidth: palette.width, in: screen) == .right)
        precondition(FormattingPalettePlacement.origin(nextTo: roomOnRight, paletteSize: palette, in: screen).x == 386)

        let roomOnLeft = NSRect(x: 700, y: 300, width: 280, height: 280)
        precondition(FormattingPalettePlacement.side(of: roomOnLeft, paletteWidth: palette.width, in: screen) == .left)
        precondition(FormattingPalettePlacement.origin(nextTo: roomOnLeft, paletteSize: palette, in: screen).x == 428)

        let nearTop = NSRect(x: 100, y: 650, width: 280, height: 280)
        precondition(FormattingPalettePlacement.origin(nextTo: nearTop, paletteSize: palette, in: screen).y == 440)

        let narrowScreen = NSRect(x: 0, y: 0, width: 500, height: 300)
        let crampedNote = NSRect(x: 100, y: 20, width: 280, height: 280)
        let crampedOrigin = FormattingPalettePlacement.origin(nextTo: crampedNote, paletteSize: palette, in: narrowScreen)
        precondition(crampedOrigin.x >= narrowScreen.minX)
        precondition(crampedOrigin.x + palette.width <= narrowScreen.maxX)
        precondition(crampedOrigin.y == narrowScreen.minY)

        print("Formatting palette placement passed")
    }
}
