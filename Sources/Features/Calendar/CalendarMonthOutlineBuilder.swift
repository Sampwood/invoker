import CoreGraphics

struct CalendarMonthOutlineMetrics: Equatable {
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let outlineInset: CGFloat
    let cornerRadius: CGFloat

    static var calendarPopover: CalendarMonthOutlineMetrics {
        CalendarMonthOutlineMetrics(
            cellWidth: CalendarPopoverMetrics.cellWidth,
            cellHeight: CalendarPopoverMetrics.cellHeight,
            columnSpacing: CalendarPopoverMetrics.columnSpacing,
            rowSpacing: CalendarPopoverMetrics.rowSpacing,
            outlineInset: 1,
            cornerRadius: 3
        )
    }
}

enum CalendarMonthOutlineBuilder {
    static func contourPoints(
        for grid: CalendarMonthGrid,
        in rect: CGRect,
        metrics: CalendarMonthOutlineMetrics
    ) -> [CGPoint] {
        let rowRects = displayedMonthRowRects(for: grid, in: rect, metrics: metrics)
        guard let firstRect = rowRects.first, let lastRect = rowRects.last else {
            return []
        }

        var points: [CGPoint] = []
        append(CGPoint(x: firstRect.minX, y: firstRect.minY), to: &points)
        append(CGPoint(x: firstRect.maxX, y: firstRect.minY), to: &points)

        for index in rowRects.indices.dropLast() {
            let current = rowRects[index]
            let next = rowRects[index + 1]

            if current.maxX != next.maxX {
                append(CGPoint(x: current.maxX, y: next.minY), to: &points)
                append(CGPoint(x: next.maxX, y: next.minY), to: &points)
            }
        }

        append(CGPoint(x: lastRect.maxX, y: lastRect.maxY), to: &points)
        append(CGPoint(x: lastRect.minX, y: lastRect.maxY), to: &points)

        for index in rowRects.indices.dropFirst().reversed() {
            let current = rowRects[index]
            let previous = rowRects[index - 1]

            if current.minX != previous.minX {
                append(CGPoint(x: current.minX, y: current.minY), to: &points)
                append(CGPoint(x: previous.minX, y: current.minY), to: &points)
            }
        }

        append(points[0], to: &points)
        return points
    }

    private static func displayedMonthRowRects(
        for grid: CalendarMonthGrid,
        in rect: CGRect,
        metrics: CalendarMonthOutlineMetrics
    ) -> [CGRect] {
        grid.weeks.enumerated().compactMap { row, week in
            let columns = week.enumerated()
                .filter { $0.element.isInDisplayedMonth }
                .map(\.offset)

            guard let firstColumn = columns.first, let lastColumn = columns.last else {
                return nil
            }

            let cellStepX = metrics.cellWidth + metrics.columnSpacing
            let cellStepY = metrics.cellHeight + metrics.rowSpacing
            let minX = rect.minX + CGFloat(firstColumn) * cellStepX - metrics.outlineInset
            let maxX = rect.minX + CGFloat(lastColumn) * cellStepX + metrics.cellWidth + metrics.outlineInset
            let minY = rect.minY + CGFloat(row) * cellStepY - metrics.outlineInset
            let maxY = rect.minY + CGFloat(row) * cellStepY + metrics.cellHeight + metrics.outlineInset

            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private static func append(_ point: CGPoint, to points: inout [CGPoint]) {
        guard points.last != point else {
            return
        }

        points.append(point)
    }
}
