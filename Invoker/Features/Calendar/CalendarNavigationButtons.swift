import SwiftUI

struct MonthNavigationButton: View {
    @State private var isHovered = false

    let systemName: String
    let rotationDegrees: Double
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 7, weight: .bold))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(
                    Color.black.opacity(
                        isHovered
                            ? CalendarPopoverMetrics.headerButtonHoverIconOpacity
                            : CalendarPopoverMetrics.headerButtonIconOpacity
                    )
                )
                .frame(
                    width: CalendarPopoverMetrics.headerButtonHoverSize,
                    height: CalendarPopoverMetrics.headerButtonHoverSize
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: CalendarPopoverMetrics.headerButtonHoverCornerRadius,
                        style: .continuous
                    )
                    .fill(
                        Color.black.opacity(
                            isHovered ? CalendarPopoverMetrics.headerButtonHoverOpacity : 0
                        )
                    )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(helpText)
    }
}

struct TodayNavigationButton: View {
    @State private var isHovered = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(
                    Color.black.opacity(
                        isHovered
                            ? CalendarPopoverMetrics.todayButtonHoverDotOpacity
                            : CalendarPopoverMetrics.todayButtonDotOpacity
                    )
                )
                .frame(
                    width: CalendarPopoverMetrics.todayButtonDotSize,
                    height: CalendarPopoverMetrics.todayButtonDotSize
                )
                .frame(
                    width: CalendarPopoverMetrics.todayButtonHitSize,
                    height: CalendarPopoverMetrics.todayButtonHitSize
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: CalendarPopoverMetrics.headerButtonHoverCornerRadius,
                        style: .continuous
                    )
                    .fill(
                        Color.black.opacity(
                            isHovered ? CalendarPopoverMetrics.headerButtonHoverOpacity : 0
                        )
                    )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help("Today")
    }
}
