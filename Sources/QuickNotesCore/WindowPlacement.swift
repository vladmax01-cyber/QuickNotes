import CoreGraphics

public enum WindowPlacement {
    public static func movementFrame(
        visibleFrame: CGRect,
        fullFrame: CGRect,
        maximumMenuBarOverlap: CGFloat = 30
    ) -> CGRect {
        let menuBarHeight = max(0, fullFrame.maxY - visibleFrame.maxY)
        let overlap = min(max(0, maximumMenuBarOverlap), menuBarHeight)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: visibleFrame.height + overlap
        )
    }

    public static func defaultFrame(in visibleFrame: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x: visibleFrame.minX + 28,
            y: visibleFrame.maxY - size.height - 8,
            width: size.width,
            height: size.height
        )
    }

    public static func clamped(
        _ frame: CGRect,
        to visibleFrame: CGRect,
        topInset: CGFloat = 0
    ) -> CGRect {
        let safeTopInset = min(max(topInset, 0), visibleFrame.height)
        let usableTop = visibleFrame.maxY - safeTopInset
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, usableTop - visibleFrame.minY)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), usableTop - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
