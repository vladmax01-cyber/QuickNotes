import CoreGraphics
import XCTest
@testable import QuickNotesCore

final class WindowPlacementTests: XCTestCase {
    func testMovementFrameAllowsLimitedMenuBarOverlap() {
        let fullFrame = CGRect(x: 0, y: 0, width: 1_710, height: 1_107)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_710, height: 1_073.5)

        let movementFrame = WindowPlacement.movementFrame(
            visibleFrame: visibleFrame,
            fullFrame: fullFrame
        )

        XCTAssertEqual(movementFrame.maxY, visibleFrame.maxY + 30)
        XCTAssertEqual(movementFrame.minY, visibleFrame.minY)
    }

    func testMovementFrameDoesNotExceedShortMenuBar() {
        let fullFrame = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_200, height: 790)

        let movementFrame = WindowPlacement.movementFrame(
            visibleFrame: visibleFrame,
            fullFrame: fullFrame
        )

        XCTAssertEqual(movementFrame, fullFrame)
    }

    func testDefaultFrameUsesUpperLeftInsetOfVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_200, height: 800)

        let frame = WindowPlacement.defaultFrame(
            in: visibleFrame,
            size: CGSize(width: 460, height: 420)
        )

        XCTAssertEqual(frame, CGRect(x: 128, y: 422, width: 460, height: 420))
    }

    func testClampingPreservesFrameAlreadyInsideVisibleArea() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_200, height: 800)
        let frame = CGRect(x: 200, y: 150, width: 460, height: 420)

        XCTAssertEqual(WindowPlacement.clamped(frame, to: visibleFrame), frame)
    }

    func testClampingMovesFrameInsideEveryEdge() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_200, height: 800)
        let frame = CGRect(x: -500, y: 900, width: 460, height: 420)

        XCTAssertEqual(
            WindowPlacement.clamped(frame, to: visibleFrame),
            CGRect(x: 100, y: 430, width: 460, height: 420)
        )
    }

    func testClampingShrinksOversizedFrameToVisibleArea() {
        let visibleFrame = CGRect(x: -300, y: 40, width: 800, height: 600)
        let frame = CGRect(x: -1_000, y: -1_000, width: 1_400, height: 900)

        XCTAssertEqual(
            WindowPlacement.clamped(frame, to: visibleFrame),
            visibleFrame
        )
    }

    func testClampingMovesFrameBackFromRightAndBottomEdges() {
        let visibleFrame = CGRect(x: -900, y: 25, width: 900, height: 700)
        let frame = CGRect(x: -200, y: -100, width: 400, height: 300)

        XCTAssertEqual(
            WindowPlacement.clamped(frame, to: visibleFrame),
            CGRect(x: -400, y: 25, width: 400, height: 300)
        )
    }

    func testClampingCanReserveTwoPointsBelowMenuBar() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_200, height: 800)
        let frame = CGRect(x: 200, y: 700, width: 460, height: 420)

        let clamped = WindowPlacement.clamped(frame, to: visibleFrame, topInset: 2)

        XCTAssertEqual(clamped.maxY, visibleFrame.maxY - 2)
        XCTAssertEqual(clamped.minX, frame.minX)
    }
}
