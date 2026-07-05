import AppKit
import XCTest
@testable import Invoker

final class CalendarDisplayFormatterTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar = gregorian
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testMenuBarDayTextUsesCurrentDayNumber() {
        let formatter = CalendarDisplayFormatter(calendar: calendar)

        XCTAssertEqual(formatter.menuBarDayText(for: date(2026, 6, 24)), "24")
    }

    func testChineseMonthTitleMatchesReferenceStyle() {
        let formatter = CalendarDisplayFormatter(calendar: calendar)

        XCTAssertEqual(formatter.monthTitle(for: date(2026, 6, 1)), "6月 2026")
    }

    func testCompactPopoverMetricsKeepTextWithinDayCells() {
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.panelWidth, 185)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.bodyHeight, 202)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.horizontalPadding, 8)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.horizontalPadding, 9)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.titleFontSize, 15)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.weekdayFontSize, 12)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.weekdayTextHeight, 16)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.dayFontSize, 12)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.dayFontSize, 13)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.dayTextWidth, CalendarPopoverMetrics.dayFontSize * 1.7)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.dayTextHeight, CalendarPopoverMetrics.dayFontSize + 7)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.cellHeight, 21)
        XCTAssertLessThanOrEqual(
            CalendarPopoverMetrics.gridWidth + CalendarPopoverMetrics.horizontalPadding * 2,
            CalendarPopoverMetrics.panelWidth
        )
    }

    func testPopoverHoverMetricsStayCompactAndVisible() {
        XCTAssertGreaterThan(CalendarPopoverMetrics.headerButtonHoverOpacity, 0.06)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.headerButtonHoverOpacity, 0.12)
        XCTAssertGreaterThan(CalendarPopoverMetrics.headerButtonHoverIconOpacity, 0.5)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.headerButtonHoverIconOpacity, 0.7)
        XCTAssertGreaterThan(CalendarPopoverMetrics.dayHoverOpacity, 0.05)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.dayHoverOpacity, 0.1)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.dayHoverCornerRadius, 4)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.headerButtonHoverSize, 16)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.headerButtonHoverSize, 14)
        XCTAssertEqual(CalendarPopoverMetrics.todayButtonDotSize, 8, accuracy: 0.001)
        XCTAssertEqual(
            CalendarPopoverMetrics.todayButtonHitSize,
            CalendarPopoverMetrics.headerButtonHoverSize,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            CalendarPopoverMetrics.todayButtonHoverDotOpacity,
            CalendarPopoverMetrics.todayButtonDotOpacity
        )
    }

    func testPopoverChromeMetricsUseUnifiedCompactTheme() {
        XCTAssertLessThan(CalendarPopoverMetrics.bodyCornerRadius, 12)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.bodyCornerRadius, 8)
        XCTAssertGreaterThan(CalendarPopoverMetrics.arrowHeight, 0)
        XCTAssertEqual(CalendarPopoverMetrics.arrowBorderOpacity, CalendarPopoverMetrics.bodyBorderOpacity, accuracy: 0.001)
        XCTAssertEqual(CalendarPopoverMetrics.arrowBorderLineWidth, CalendarPopoverMetrics.bodyBorderLineWidth, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.bodyBorderOpacity, 0.26)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.bodyBorderOpacity, 0.34)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.shadowOpacity, 0.12)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.shadowOpacity, 0.15)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.shadowRadius, 4.5)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.shadowRadius, 5.5)
        XCTAssertGreaterThanOrEqual(CalendarPopoverMetrics.shadowYOffset, 1.5)
        XCTAssertLessThanOrEqual(CalendarPopoverMetrics.shadowYOffset, 2.5)
        XCTAssertEqual(CalendarPopoverMetrics.shadowSourceWidth, CalendarPopoverMetrics.panelWidth, accuracy: 0.001)
        XCTAssertEqual(CalendarPopoverMetrics.shadowSourceHeight, CalendarPopoverMetrics.bodyHeight, accuracy: 0.001)
        XCTAssertEqual(CalendarPopoverMetrics.shadowSourceCornerRadius, CalendarPopoverMetrics.bodyCornerRadius, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            CalendarPopoverMetrics.shadowPadding,
            CalendarPopoverMetrics.shadowRadius + abs(CalendarPopoverMetrics.shadowYOffset)
        )
        XCTAssertEqual(CalendarPopoverMetrics.shadowPadding, 12, accuracy: 0.001)
        XCTAssertEqual(
            CalendarPopoverMetrics.windowWidth,
            CalendarPopoverMetrics.panelWidth + CalendarPopoverMetrics.shadowPadding * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CalendarPopoverMetrics.panelHeight,
            CalendarPopoverMetrics.bodyHeight + CalendarPopoverMetrics.arrowHeight - CalendarPopoverMetrics.arrowBodyOverlap,
            accuracy: 0.001
        )
        XCTAssertEqual(
            CalendarPopoverMetrics.windowHeight,
            CalendarPopoverMetrics.panelHeight + CalendarPopoverMetrics.shadowPadding * 2,
            accuracy: 0.001
        )
    }

    func testStatusIconMetricsUseSmallerCenteredBadge() {
        XCTAssertLessThanOrEqual(CalendarStatusIconMetrics.statusItemLength, 24)
        XCTAssertLessThanOrEqual(CalendarStatusIconMetrics.imageSize.width, 22)
        XCTAssertLessThanOrEqual(CalendarStatusIconMetrics.imageSize.height, 20)
        XCTAssertLessThanOrEqual(CalendarStatusIconMetrics.badgeCornerRadius, 3.5)
        XCTAssertLessThanOrEqual(CalendarStatusIconMetrics.badgeRect.minX, 1)
        XCTAssertGreaterThanOrEqual(CalendarStatusIconMetrics.badgeRect.width, 20)
        XCTAssertLessThanOrEqual(CalendarStatusIconMetrics.textWeight.rawValue, NSFont.Weight.semibold.rawValue)
        XCTAssertEqual(CalendarStatusIconMetrics.textRect.midX, CalendarStatusIconMetrics.imageSize.width / 2, accuracy: 0.01)
        XCTAssertEqual(CalendarStatusIconMetrics.textRect.midY, CalendarStatusIconMetrics.imageSize.height / 2, accuracy: 0.01)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
