import Foundation

struct CalendarDisplayFormatter {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func menuBarDayText(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    func monthTitle(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.month ?? 1)月 \(components.year ?? 1)"
    }
}
