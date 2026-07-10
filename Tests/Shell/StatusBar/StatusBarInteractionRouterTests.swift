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

    func testContextMenuContainsScreenshotUpdateCheckAndQuitItems() {
        XCTAssertEqual(StatusBarMenuContent.items.map(\.title), ["截图", "检查更新...", "退出 Invoker"])
    }

    func testContextMenuUsesCompactSystemLikePanelMetrics() {
        XCTAssertEqual(StatusBarMenuMetrics.bodyColorName, "nearWhite")
        XCTAssertLessThanOrEqual(StatusBarMenuMetrics.bodyWidth, 106)
        XCTAssertEqual(
            StatusBarMenuMetrics.bodyHeight,
            StatusBarMenuMetrics.bodyVerticalPadding * 2 + StatusBarMenuMetrics.rowHeight * 3
        )
        XCTAssertLessThanOrEqual(StatusBarMenuMetrics.rowHeight, 28)
        XCTAssertLessThanOrEqual(StatusBarMenuMetrics.textFontSize, 13)
        XCTAssertLessThanOrEqual(StatusBarMenuMetrics.bodyBorderOpacity, 0.16)
        XCTAssertGreaterThan(StatusBarMenuMetrics.shadowRadius, CalendarPopoverMetrics.shadowRadius)
        XCTAssertGreaterThanOrEqual(
            StatusBarMenuMetrics.shadowPadding,
            StatusBarMenuMetrics.shadowRadius + StatusBarMenuMetrics.shadowYOffset + 6
        )
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
