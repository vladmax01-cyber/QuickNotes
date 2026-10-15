import AppKit
import SwiftUI

@MainActor
@main
struct ResizeHitSmoke {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.maxSize = NSSize(width: 4096, height: 4096)
        let content = NSView(frame: panel.contentView!.bounds)
        let controller = NSViewController()
        controller.view = content
        let host = NSHostingController(rootView: Text("First"))
        host.sizingOptions = []
        controller.addChild(host)
        host.view.frame = content.bounds
        host.view.autoresizingMask = [.width, .height]
        content.addSubview(host.view)
        let overlay = WindowResizeOverlay(frame: content.bounds)
        overlay.autoresizingMask = [.width, .height]
        content.addSubview(overlay, positioned: .above, relativeTo: host.view)
        panel.contentViewController = controller
        host.rootView = Text("Replaced")

        for point in [
            NSPoint(x: 295, y: 150), NSPoint(x: 5, y: 150),
            NSPoint(x: 150, y: 5), NSPoint(x: 150, y: 295),
            NSPoint(x: 295, y: 5), NSPoint(x: 5, y: 295)
        ] {
            precondition(content.hitTest(point) === overlay, "Resize edge not hittable: \(point)")
        }
        precondition(content.hitTest(NSPoint(x: 150, y: 150)) !== overlay)
        precondition(content.hitTest(NSPoint(x: 278, y: 22)) === overlay, "Visible corner grip is too small to grab")
        precondition(panel.contentView?.hitTest(NSPoint(x: 5, y: 150)) === overlay)
        precondition(panel.contentView?.hitTest(NSPoint(x: 150, y: 295)) === overlay)
        var collapseCount = 0
        overlay.onHeaderDoubleClick = { collapseCount += 1 }
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 150, y: 295), in: panel, clickCount: 2))
        precondition(collapseCount == 1, "Top resize edge swallowed the collapse gesture")

        panel.setContentSize(NSSize(width: 400, height: 360))
        panel.setFrameOrigin(NSPoint(x: 200, y: 500))
        precondition(overlay.frame.size == content.bounds.size)
        precondition(content.hitTest(NSPoint(x: 395, y: 200)) === overlay)
        precondition(content.hitTest(NSPoint(x: 200, y: 5)) === overlay)

        panel.minSize = NSSize(width: 280, height: 280)
        let initialSize = panel.frame.size
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 395, y: 5), in: panel))
        overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 425, y: -25), in: panel))
        precondition(panel.frame.width == initialSize.width + 30)
        precondition(panel.frame.height == initialSize.height + 30)
        overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 425, y: -25), in: panel))

        overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: panel.frame.width - 5, y: 5), in: panel))
        overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 10, y: panel.frame.height - 10), in: panel))
        precondition(panel.frame.width == 280 && panel.frame.height == 280)
        overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 10, y: panel.frame.height - 10), in: panel))

        // Left and top drags anchor the opposite edges instead of moving the note.
        panel.setFrame(NSRect(x: 200, y: 500, width: 400, height: 360), display: true)
        let anchoredRight = panel.frame.maxX
        let anchoredBottom = panel.frame.minY
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 5, y: panel.frame.height - 5), in: panel))
        overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: -35, y: panel.frame.height + 25), in: panel))
        precondition(panel.frame.width == 440 && panel.frame.height == 390)
        precondition(panel.frame.maxX == anchoredRight && panel.frame.minY == anchoredBottom)
        overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: -35, y: panel.frame.height + 25), in: panel))

        panel.setFrame(NSRect(x: 200, y: 500, width: 400, height: 360), display: true)
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 5, y: panel.frame.height - 5), in: panel))
        overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 250, y: 5), in: panel))
        precondition(panel.frame.width == 280 && panel.frame.height == 280)
        overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 250, y: 5), in: panel))

        panel.setFrame(NSRect(x: 200, y: 300, width: 400, height: 360), display: true)
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: NSPoint(x: 380, y: 20), in: panel))
        overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: NSPoint(x: 880, y: 20), in: panel))
        precondition(panel.frame.width >= 900, "Window stopped growing at the former 800-point limit")
        overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: NSPoint(x: 880, y: 20), in: panel))

        overlay.isResizeEnabled = { false }
        precondition(content.hitTest(NSPoint(x: content.bounds.maxX - 5, y: 5)) !== overlay)
        print("Resize hit regions passed")
    }

    private static func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow, clickCount: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }
}
