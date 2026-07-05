import SwiftUI

struct CalendarPopoverView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var hoveredDayID: CalendarDay.ID?
    @ObservedObject private var presentationState: CalendarPopoverPresentationState

    private let formatter = CalendarDisplayFormatter()
    private let columns = Array(
        repeating: GridItem(.fixed(CalendarPopoverMetrics.cellWidth), spacing: CalendarPopoverMetrics.columnSpacing),
        count: 7
    )
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    init(presentationState: CalendarPopoverPresentationState = CalendarPopoverPresentationState()) {
        self.presentationState = presentationState
    }

    var body: some View {
        popoverChrome
            .offset(x: CalendarPopoverMetrics.shadowPadding, y: CalendarPopoverMetrics.shadowPadding)
            .frame(
                width: CalendarPopoverMetrics.windowWidth,
                height: CalendarPopoverMetrics.windowHeight,
                alignment: .topLeading
            )
            .background(Color.clear)
    }

    private var popoverChrome: some View {
        ZStack(alignment: .topLeading) {
            bodyShadow
                .offset(y: CalendarPopoverMetrics.arrowHeight - CalendarPopoverMetrics.arrowBodyOverlap)

            CalendarPopoverArrowShape()
                .fill(Color.white)
                .frame(width: CalendarPopoverMetrics.arrowWidth, height: CalendarPopoverMetrics.arrowHeight)
                .overlay(
                    CalendarPopoverArrowStrokeShape()
                        .stroke(
                            Color.black.opacity(CalendarPopoverMetrics.arrowBorderOpacity),
                            lineWidth: CalendarPopoverMetrics.arrowBorderLineWidth
                        )
                )
                .offset(x: presentationState.arrowCenterX - CalendarPopoverMetrics.arrowWidth / 2)
                .zIndex(1)

            calendarBody
                .offset(y: CalendarPopoverMetrics.arrowHeight - CalendarPopoverMetrics.arrowBodyOverlap)
        }
        .frame(width: CalendarPopoverMetrics.panelWidth, height: CalendarPopoverMetrics.panelHeight, alignment: .top)
    }

    private var bodyShadow: some View {
        RoundedRectangle(cornerRadius: CalendarPopoverMetrics.shadowSourceCornerRadius, style: .continuous)
            .fill(Color.white)
            .frame(
                width: CalendarPopoverMetrics.shadowSourceWidth,
                height: CalendarPopoverMetrics.shadowSourceHeight
            )
            .shadow(
                color: .black.opacity(CalendarPopoverMetrics.shadowOpacity),
                radius: CalendarPopoverMetrics.shadowRadius,
                x: 0,
                y: CalendarPopoverMetrics.shadowYOffset
            )
    }

    private var calendarBody: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, CalendarPopoverMetrics.topPadding)
                .padding(.horizontal, CalendarPopoverMetrics.horizontalPadding)

            weekdayHeader
                .padding(.top, 8)

            calendarGrid
                .padding(.top, 4)

            Capsule()
                .fill(Color.black.opacity(0.05))
                .frame(width: 28, height: 4)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(width: CalendarPopoverMetrics.panelWidth, height: CalendarPopoverMetrics.bodyHeight)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CalendarPopoverMetrics.bodyCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CalendarPopoverMetrics.bodyCornerRadius, style: .continuous)
                .stroke(
                    Color.black.opacity(CalendarPopoverMetrics.bodyBorderOpacity),
                    lineWidth: CalendarPopoverMetrics.bodyBorderLineWidth
                )
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            Text(formatter.monthTitle(for: viewModel.displayedMonth))
                .font(.system(size: CalendarPopoverMetrics.titleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.84))
                .lineLimit(1)

            Spacer()

            MonthNavigationButton(
                systemName: "play.fill",
                rotationDegrees: 180,
                helpText: "Previous month"
            ) {
                viewModel.goToPreviousMonth()
            }

            TodayNavigationButton {
                viewModel.goToToday()
            }

            MonthNavigationButton(
                systemName: "play.fill",
                rotationDegrees: 0,
                helpText: "Next month"
            ) {
                viewModel.goToNextMonth()
            }
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: CalendarPopoverMetrics.weekdayFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.83))
                    .frame(width: CalendarPopoverMetrics.cellWidth, height: CalendarPopoverMetrics.weekdayTextHeight)
            }
        }
        .frame(width: CalendarPopoverMetrics.gridWidth)
    }

    private var calendarGrid: some View {
        ZStack {
            CalendarMonthOutlineShape(grid: viewModel.monthGrid)
                .stroke(Color.black.opacity(0.84), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(width: CalendarPopoverMetrics.gridWidth, height: CalendarPopoverMetrics.gridHeight)

            LazyVGrid(columns: columns, spacing: CalendarPopoverMetrics.rowSpacing) {
                ForEach(viewModel.monthGrid.weeks.flatMap { $0 }) { day in
                    dayButton(for: day)
                }
            }
            .frame(width: CalendarPopoverMetrics.gridWidth, height: CalendarPopoverMetrics.gridHeight)
        }
        .frame(width: CalendarPopoverMetrics.gridWidth, height: CalendarPopoverMetrics.gridHeight)
    }

    private func dayButton(for day: CalendarDay) -> some View {
        let isHovered = hoveredDayID == day.id

        return Button {
            viewModel.select(day.date)
        } label: {
            Text("\(day.dayNumber)")
                .font(.system(size: CalendarPopoverMetrics.dayFontSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(textColor(for: day))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: CalendarPopoverMetrics.dayTextWidth, height: CalendarPopoverMetrics.dayTextHeight)
                .background(dayBackground(for: day, isHovered: isHovered))
                .frame(width: CalendarPopoverMetrics.cellWidth, height: CalendarPopoverMetrics.cellHeight)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered in
            hoveredDayID = isHovered ? day.id : nil
        }
    }

    private func textColor(for day: CalendarDay) -> Color {
        if day.isSelected {
            return .white
        }

        if day.isToday {
            return .black.opacity(0.82)
        }

        if day.isInDisplayedMonth {
            return .black.opacity(0.84)
        }

        return .black.opacity(0.24)
    }

    @ViewBuilder
    private func dayBackground(for day: CalendarDay, isHovered: Bool) -> some View {
        if day.isSelected {
            RoundedRectangle(cornerRadius: CalendarPopoverMetrics.dayHoverCornerRadius, style: .continuous)
                .fill(
                    isHovered
                        ? Color(red: 0.08, green: 0.50, blue: 0.76)
                        : Color(red: 0.11, green: 0.58, blue: 0.83)
                )
        } else if day.isToday {
            RoundedRectangle(cornerRadius: CalendarPopoverMetrics.dayHoverCornerRadius, style: .continuous)
                .stroke(Color(red: 0.18, green: 0.61, blue: 0.85), lineWidth: 1.2)
                .background(
                    RoundedRectangle(cornerRadius: CalendarPopoverMetrics.dayHoverCornerRadius, style: .continuous)
                        .fill(
                            isHovered
                                ? Color(red: 0.80, green: 0.91, blue: 0.97)
                                : Color(red: 0.86, green: 0.94, blue: 0.98)
                        )
                )
        } else if isHovered {
            RoundedRectangle(cornerRadius: CalendarPopoverMetrics.dayHoverCornerRadius, style: .continuous)
                .fill(Color.black.opacity(CalendarPopoverMetrics.dayHoverOpacity))
        } else {
            Color.clear
        }
    }
}
