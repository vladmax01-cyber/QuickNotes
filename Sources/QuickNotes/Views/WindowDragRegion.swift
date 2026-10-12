import AppKit
import SwiftUI
import QuickNotesCore

private final class WindowDragView: NSView {
    var onDoubleClick: (() -> Void)?
    private var initialWindowOrigin: NSPoint?
    private var initialMouseLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            initialWindowOrigin = nil
            initialMouseLocation = nil
            onDoubleClick?()
            return
        }
        guard let window else { return }
        initialWindowOrigin = window.frame.origin
        initialMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let initialWindowOrigin,
              let initialMouseLocation else { return }
        let mouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        let proposedOrigin = NSPoint(
            x: initialWindowOrigin.x + mouseLocation.x - initialMouseLocation.x,
            y: initialWindowOrigin.y + mouseLocation.y - initialMouseLocation.y
        )
        let proposedFrame = NSRect(origin: proposedOrigin, size: window.frame.size)
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? window.screen
        let constrainedFrame = targetScreen.map {
            let movementFrame = WindowPlacement.movementFrame(
                visibleFrame: $0.visibleFrame,
                fullFrame: $0.frame
            )
            return WindowPlacement.clamped(proposedFrame, to: movementFrame)
        } ?? proposedFrame
        window.setFrameOrigin(constrainedFrame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        initialWindowOrigin = nil
        initialMouseLocation = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

struct WindowDragRegion: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowDragView()
        view.onDoubleClick = onDoubleClick
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowDragView)?.onDoubleClick = onDoubleClick
    }
}
