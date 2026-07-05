import CoreGraphics
import XCTest
@testable import Invoker

final class CalendarMonthOutlineBuilderTests: XCTestCase {
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

    func testJuneTwentyTwentySixOutlineUsesSingleContinuousContour() {
        let viewModel = CalendarViewModel(
            calendar: calendar,
            todayProvider: { self.date(2026, 6, 24) },
            displayedMonth: date(2026, 6, 1)
        )

        let contour = CalendarMonthOutlineBuilder.contourPoints(
            for: viewModel.monthGrid,
            in: CGRect(
                x: 0,
                y: 0,
                width: CalendarPopoverMetrics.gridWidth,
                height: CalendarPopoverMetrics.gridHeight
            ),
            metrics: .calendarPopover
        )

        XCTAssertEqual(contour.count, 9)
        XCTAssertEqual(contour.first, CGPoint(x: 22.5, y: -1))
        XCTAssertEqual(contour.last, contour.first)
    }

    func testPopoverOutlineUsesRoundedCorners() {
        XCTAssertGreaterThan(CalendarMonthOutlineMetrics.calendarPopover.cornerRadius, 0)
        XCTAssertLessThanOrEqual(CalendarMonthOutlineMetrics.calendarPopover.cornerRadius, 4)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
