import SwiftUI

struct CalendarPopoverArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CalendarPopoverArrowStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct CalendarMonthOutlineShape: Shape {
    let grid: CalendarMonthGrid

    func path(in rect: CGRect) -> Path {
        let contour = CalendarMonthOutlineBuilder.contourPoints(
            for: grid,
            in: rect,
            metrics: .calendarPopover
        )
        var path = Path()
        guard let firstPoint = contour.first else {
            return path
        }

        let cornerRadius = CalendarMonthOutlineMetrics.calendarPopover.cornerRadius
        guard cornerRadius > 0 else {
            path.move(to: firstPoint)

            for point in contour.dropFirst() {
                path.addLine(to: point)
            }

            return path
        }

        return roundedPath(for: contour, cornerRadius: cornerRadius)
    }

    private func roundedPath(for contour: [CGPoint], cornerRadius: CGFloat) -> Path {
        let points = contour.last == contour.first ? Array(contour.dropLast()) : contour
        guard points.count > 2 else {
            var path = Path()
            if let firstPoint = points.first {
                path.move(to: firstPoint)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            return path
        }

        var path = Path()
        let start = offsetPoint(from: points[0], toward: points[1], by: cornerRadius)
        path.move(to: start)

        for index in points.indices.dropFirst() {
            let previous = points[index - 1]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let incoming = offsetPoint(from: current, toward: previous, by: cornerRadius)
            let outgoing = offsetPoint(from: current, toward: next, by: cornerRadius)

            path.addLine(to: incoming)
            path.addQuadCurve(to: outgoing, control: current)
        }

        let firstIncoming = offsetPoint(from: points[0], toward: points[points.count - 1], by: cornerRadius)
        path.addLine(to: firstIncoming)
        path.addQuadCurve(to: start, control: points[0])
        path.closeSubpath()
        return path
    }

    private func offsetPoint(from point: CGPoint, toward target: CGPoint, by distance: CGFloat) -> CGPoint {
        let dx = target.x - point.x
        let dy = target.y - point.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let cappedDistance = min(distance, length / 2)

        return CGPoint(
            x: point.x + dx / length * cappedDistance,
            y: point.y + dy / length * cappedDistance
        )
    }
}
