import XCTest
@testable import Invoker

final class CalendarViewModelTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        gregorian.locale = Locale(identifier: "en_US_POSIX")
        calendar = gregorian
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testMonthGridAlwaysContainsSixWeeksOfSevenDays() {
        let viewModel = makeViewModel(displaying: date(2026, 6, 15), today: date(2026, 6, 24))

        let grid = viewModel.monthGrid

        XCTAssertEqual(grid.weeks.count, 6)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 })
    }

    func testMonthGridMarksOnlyDisplayedMonthDaysAsInMonth() {
        let viewModel = makeViewModel(displaying: date(2026, 6, 15), today: date(2026, 6, 24))

        let daysInDisplayedMonth = viewModel.monthGrid.weeks.flatMap { $0 }.filter(\.isInDisplayedMonth)

        XCTAssertEqual(daysInDisplayedMonth.count, 30)
        XCTAssertEqual(daysInDisplayedMonth.first?.dayNumber, 1)
        XCTAssertEqual(daysInDisplayedMonth.last?.dayNumber, 30)
    }

    func testMonthGridIncludesAdjacentMonthPaddingDays() {
        let viewModel = makeViewModel(displaying: date(2026, 6, 15), today: date(2026, 6, 24))

        let allDays = viewModel.monthGrid.weeks.flatMap { $0 }

        XCTAssertEqual(components(allDays.first!.date), DateComponents(year: 2026, month: 5, day: 31))
        XCTAssertEqual(components(allDays.last!.date), DateComponents(year: 2026, month: 7, day: 11))
        XCTAssertFalse(allDays.first!.isInDisplayedMonth)
        XCTAssertFalse(allDays.last!.isInDisplayedMonth)
    }

    func testFebruaryInLeapYearHasTwentyNineDisplayedDays() {
        let viewModel = makeViewModel(displaying: date(2028, 2, 10), today: date(2028, 2, 20))

        let displayedDays = viewModel.monthGrid.weeks.flatMap { $0 }.filter(\.isInDisplayedMonth)

        XCTAssertEqual(displayedDays.count, 29)
    }

    func testFebruaryInNonLeapYearHasTwentyEightDisplayedDays() {
        let viewModel = makeViewModel(displaying: date(2027, 2, 10), today: date(2027, 2, 20))

        let displayedDays = viewModel.monthGrid.weeks.flatMap { $0 }.filter(\.isInDisplayedMonth)

        XCTAssertEqual(displayedDays.count, 28)
    }

    func testPreviousMonthCrossesYearBoundary() {
        let viewModel = makeViewModel(displaying: date(2026, 1, 15), today: date(2026, 1, 24))

        viewModel.goToPreviousMonth()

        XCTAssertEqual(components(viewModel.displayedMonth), DateComponents(year: 2025, month: 12, day: 1))
    }

    func testNextMonthCrossesYearBoundary() {
        let viewModel = makeViewModel(displaying: date(2026, 12, 15), today: date(2026, 12, 24))

        viewModel.goToNextMonth()

        XCTAssertEqual(components(viewModel.displayedMonth), DateComponents(year: 2027, month: 1, day: 1))
    }

    func testGoToTodayDisplaysAndSelectsToday() {
        let viewModel = makeViewModel(displaying: date(2026, 1, 15), today: date(2026, 6, 24))

        viewModel.goToToday()

        XCTAssertEqual(components(viewModel.displayedMonth), DateComponents(year: 2026, month: 6, day: 1))
        XCTAssertEqual(components(viewModel.selectedDate), DateComponents(year: 2026, month: 6, day: 24))
    }

    func testSelectUpdatesSelectedDateAndSelectedGridDay() {
        let viewModel = makeViewModel(displaying: date(2026, 6, 15), today: date(2026, 6, 24))

        viewModel.select(date(2026, 6, 12))

        let selectedDays = viewModel.monthGrid.weeks.flatMap { $0 }.filter(\.isSelected)
        XCTAssertEqual(components(viewModel.selectedDate), DateComponents(year: 2026, month: 6, day: 12))
        XCTAssertEqual(selectedDays.count, 1)
        XCTAssertEqual(components(selectedDays[0].date), DateComponents(year: 2026, month: 6, day: 12))
    }

    func testTodayHighlightAppearsOnlyOnActualToday() {
        let viewModel = makeViewModel(displaying: date(2026, 6, 15), today: date(2026, 6, 24))

        let todayDays = viewModel.monthGrid.weeks.flatMap { $0 }.filter(\.isToday)

        XCTAssertEqual(todayDays.count, 1)
        XCTAssertEqual(components(todayDays[0].date), DateComponents(year: 2026, month: 6, day: 24))
    }

    private func makeViewModel(displaying displayedMonth: Date, today: Date) -> CalendarViewModel {
        CalendarViewModel(calendar: calendar, todayProvider: { today }, displayedMonth: displayedMonth)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }
}
