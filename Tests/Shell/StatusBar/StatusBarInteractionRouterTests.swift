import AppKit
import XCTest
@testable import Invoker

final class StatusBarInteractionRouterTests: XCTestCase {
    func testLeftMouseUpTogglesCalendar() {
        XCTAssertEqual(StatusBarInteractionRouter.action(for: .leftMouseUp), .toggleCalendar)
    }

    func testRightMouseUpShowsMenu() {
        XCTAssertEqual(StatusBarInteractionRouter.action(for: .rightMouseUp), .showMenu)
    }

    func testContextMenuOnlyContainsQuitItem() {
        XCTAssertEqual(StatusBarMenuContent.items.map(\.title), ["退出 Invoker"])
    }

    func testContextMenuUsesCompactWhitePanelMetrics() {
        XCTAssertEqual(StatusBarMenuMetrics.bodyColorName, "white")
        XCTAssertLessThanOrEqual(StatusBarMenuMetrics.bodyWidth, CalendarPopoverMetrics.panelWidth)
        XCTAssertLessThanOrEqual(StatusBarMenuMetrics.bodyHeight, 48)
        XCTAssertEqual(StatusBarMenuMetrics.bodyCornerRadius, CalendarPopoverMetrics.bodyCornerRadius, accuracy: 0.001)
        XCTAssertEqual(StatusBarMenuMetrics.bodyBorderOpacity, CalendarPopoverMetrics.bodyBorderOpacity, accuracy: 0.001)
        XCTAssertEqual(StatusBarMenuMetrics.shadowRadius, CalendarPopoverMetrics.shadowRadius, accuracy: 0.001)
    }

    func testOtherEventsAreIgnored() {
        XCTAssertEqual(StatusBarInteractionRouter.action(for: .leftMouseDown), .ignore)
    }

    func testPopoverGeometryKeepsArrowAlignedWhenPanelIsClampedToRightEdge() {
        let layout = CalendarPopoverPresentationGeometry.layout(
            buttonRectOnScreen: CGRect(x: 1450, y: 900, width: 28, height: 22),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            panelSize: CGSize(width: CalendarPopoverMetrics.windowWidth, height: CalendarPopoverMetrics.windowHeight)
        )

        XCTAssertEqual(layout.origin.x, 1326 - CalendarPopoverMetrics.shadowPadding, accuracy: 0.001)
        XCTAssertEqual(layout.arrowCenterX, 138, accuracy: 0.001)
    }
}
