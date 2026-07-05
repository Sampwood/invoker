import Foundation

final class CalendarViewModel: ObservableObject {
    @Published private(set) var displayedMonth: Date
    @Published private(set) var selectedDate: Date

    private let calendar: Calendar
    private let todayProvider: () -> Date

    init(
        calendar: Calendar = .current,
        todayProvider: @escaping () -> Date = Date.init,
        displayedMonth: Date? = nil,
        selectedDate: Date? = nil
    ) {
        self.calendar = calendar
        self.todayProvider = todayProvider

        let today = calendar.startOfDay(for: todayProvider())
        self.displayedMonth = CalendarViewModel.firstDayOfMonth(
            containing: displayedMonth ?? today,
            calendar: calendar
        )
        self.selectedDate = calendar.startOfDay(for: selectedDate ?? today)
    }

    var monthGrid: CalendarMonthGrid {
        let firstDay = displayedMonth
        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstDay)!
        let currentMonth = calendar.component(.month, from: firstDay)
        let today = calendar.startOfDay(for: todayProvider())

        let days = (0..<42).map { offset -> CalendarDay in
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            let normalizedDate = calendar.startOfDay(for: date)

            return CalendarDay(
                date: normalizedDate,
                dayNumber: calendar.component(.day, from: normalizedDate),
                isInDisplayedMonth: calendar.component(.month, from: normalizedDate) == currentMonth,
                isToday: calendar.isDate(normalizedDate, inSameDayAs: today),
                isSelected: calendar.isDate(normalizedDate, inSameDayAs: selectedDate)
            )
        }

        let weeks = stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<start + 7])
        }

        return CalendarMonthGrid(displayedMonth: firstDay, weeks: weeks)
    }

    func goToPreviousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
        displayedMonth = Self.firstDayOfMonth(containing: displayedMonth, calendar: calendar)
    }

    func goToNextMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
        displayedMonth = Self.firstDayOfMonth(containing: displayedMonth, calendar: calendar)
    }

    func goToToday() {
        let today = calendar.startOfDay(for: todayProvider())
        displayedMonth = Self.firstDayOfMonth(containing: today, calendar: calendar)
        selectedDate = today
    }

    func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }

    private static func firstDayOfMonth(containing date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)!
    }
}
