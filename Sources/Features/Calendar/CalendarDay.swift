import Foundation

struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isSelected: Bool

    var id: Date {
        date
    }
}
