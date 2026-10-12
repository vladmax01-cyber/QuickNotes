import AppKit

final class WindowResizeOverlay: NSView {
    var isResizeEnabled: () -> Bool = { true }
    var onHeaderDoubleClick: (() -> Void)?
    private let sideWidth: CGFloat = 12
    private let topWidth: CGFloat = 6
    private let bottomWidth: CGFloat = 12
    private let cornerSize: CGFloat = 28
    private var startingFrame: NSRect?
    private var startingMouseLocation: NSPoint?
    private var resizeLeft = false
    private var resizeRight = false
    private var resizeTop = false
    private var resizeBottom = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isResizeEnabled() else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let edges = edges(at: local)
        return edges.left || edges.right || edges.top || edges.bottom ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let edges = edges(at: local)
        if event.clickCount == 2, edges.top {
            startingFrame = nil
            startingMouseLocation = nil
            onHeaderDoubleClick?()
            return
        }
        resizeLeft = edges.left
        resizeRight = edges.right
        resizeTop = edges.top
        resizeBottom = edges.bottom
        startingFrame = window?.frame
        startingMouseLocation = window?.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startingFrame, let startingMouseLocation else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let minimum = window.minSize
        let maximum = window.maxSize
        let deltaX = mouse.x - startingMouseLocation.x
        let deltaY = mouse.y - startingMouseLocation.y
        let availableWidth = screen.map {
            resizeLeft ? startingFrame.maxX - $0.minX : $0.maxX - startingFrame.minX
        } ?? maximum.width
        let availableHeight = screen.map {
            resizeTop ? $0.maxY - startingFrame.minY : startingFrame.maxY - $0.minY
        } ?? maximum.height
        let desiredWidth = startingFrame.width + (resizeLeft ? -deltaX : resizeRight ? deltaX : 0)
        let desiredHeight = startingFrame.height + (resizeBottom ? -deltaY : resizeTop ? deltaY : 0)
        let width = resizeLeft || resizeRight
            ? min(max(desiredWidth, minimum.width), max(minimum.width, min(maximum.width, availableWidth)))
            : startingFrame.width
        let height = resizeTop || resizeBottom
            ? min(max(desiredHeight, minimum.height), max(minimum.height, min(maximum.height, availableHeight)))
            : startingFrame.height
        window.setFrame(NSRect(
            x: resizeLeft ? startingFrame.maxX - width : startingFrame.minX,
            y: resizeBottom ? startingFrame.maxY - height : startingFrame.minY,
            width: width,
            height: height
        ), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        startingFrame = nil
        startingMouseLocation = nil
        resizeLeft = false
        resizeRight = false
        resizeTop = false
        resizeBottom = false
    }

    override func resetCursorRects() {
        guard isResizeEnabled() else { return }
        addCursorRect(
            NSRect(x: bounds.maxX - sideWidth, y: bounds.minY, width: sideWidth, height: bounds.height),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(x: bounds.minX, y: bounds.minY, width: sideWidth, height: bounds.height),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(x: bounds.minX + sideWidth, y: bounds.minY, width: bounds.width - 2 * sideWidth, height: bottomWidth),
            cursor: .resizeUpDown
        )
        addCursorRect(
            NSRect(x: bounds.minX + sideWidth, y: bounds.maxY - topWidth, width: bounds.width - 2 * sideWidth, height: topWidth),
            cursor: .resizeUpDown
        )
        addCursorRect(
            NSRect(x: bounds.maxX - cornerSize, y: bounds.minY, width: cornerSize, height: cornerSize),
            cursor: .resizeLeftRight
        )
    }

    private func edges(at point: NSPoint) -> (left: Bool, right: Bool, top: Bool, bottom: Bool) {
        let bottomRightCorner = point.x >= bounds.maxX - cornerSize
            && point.y <= bounds.minY + cornerSize
        return (
            left: point.x <= bounds.minX + sideWidth,
            right: point.x >= bounds.maxX - sideWidth || bottomRightCorner,
            top: point.y >= bounds.maxY - topWidth,
            bottom: point.y <= bounds.minY + bottomWidth || bottomRightCorner
        )
    }
}
