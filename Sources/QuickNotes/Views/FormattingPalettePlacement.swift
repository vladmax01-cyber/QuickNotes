import AppKit

enum FormattingPalettePlacement {
    enum Side {
        case left
        case right
    }

    static let gap: CGFloat = 6

    static func side(
        of noteFrame: NSRect,
        paletteWidth: CGFloat,
        in screenFrame: NSRect
    ) -> Side {
        let rightSpace = screenFrame.maxX - noteFrame.maxX
        let leftSpace = noteFrame.minX - screenFrame.minX
        if rightSpace >= paletteWidth + gap { return .right }
        if leftSpace >= paletteWidth + gap { return .left }
        return rightSpace >= leftSpace ? .right : .left
    }

    static func origin(
        nextTo noteFrame: NSRect,
        paletteSize: NSSize,
        in screenFrame: NSRect
    ) -> NSPoint {
        let preferredX = side(
            of: noteFrame,
            paletteWidth: paletteSize.width,
            in: screenFrame
        ) == .right
            ? noteFrame.maxX + gap
            : noteFrame.minX - paletteSize.width - gap
        return NSPoint(
            x: min(max(preferredX, screenFrame.minX),
                   max(screenFrame.minX, screenFrame.maxX - paletteSize.width)),
            y: min(max(noteFrame.maxY - paletteSize.height, screenFrame.minY),
                   max(screenFrame.minY, screenFrame.maxY - paletteSize.height))
        )
    }
}
