import AppKit

enum FormattingPalettePlacement {
    enum Side {
        case left
        case right
    }

    static let gap: CGFloat = 6
    static let noteContentInset: CGFloat = 6

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
        let rightSpace = screenFrame.maxX - noteFrame.maxX
        let leftSpace = noteFrame.minX - screenFrame.minX
        if rightSpace < paletteSize.width + gap && leftSpace < paletteSize.width + gap {
            let belowSpace = noteFrame.minY - screenFrame.minY
            let aboveSpace = screenFrame.maxY - noteFrame.maxY
            if belowSpace >= paletteSize.height + gap || aboveSpace >= paletteSize.height + gap {
                let preferredY = belowSpace >= paletteSize.height + gap
                    ? noteFrame.minY - paletteSize.height - gap
                    : noteFrame.maxY + gap
                return NSPoint(
                    x: min(max(noteFrame.midX - paletteSize.width / 2, screenFrame.minX),
                           max(screenFrame.minX, screenFrame.maxX - paletteSize.width)),
                    y: preferredY
                )
            }
        }
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

    static func popoverWindowX(
        nextTo noteFrame: NSRect,
        windowWidth: CGFloat,
        contentWidth: CGFloat,
        side: Side,
        in screenFrame: NSRect
    ) -> CGFloat {
        let popoverChromeInset = max(0, (windowWidth - contentWidth) / 2)
        let frameGap = gap - noteContentInset - popoverChromeInset
        let preferredX = side == .right
            ? noteFrame.maxX + frameGap
            : noteFrame.minX - windowWidth - frameGap
        return min(max(preferredX, screenFrame.minX),
                   max(screenFrame.minX, screenFrame.maxX - windowWidth))
    }
}

enum FormattingPaletteDismissal {
    enum Interaction: CaseIterable {
        case palette, toggle, note, otherWindow, outsideApp, deactivate
    }

    static func shouldDismiss(pinned: Bool, interaction: Interaction) -> Bool {
        guard !pinned else { return false }
        switch interaction {
        case .palette, .toggle: return false
        case .note, .otherWindow, .outsideApp, .deactivate: return true
        }
    }
}
