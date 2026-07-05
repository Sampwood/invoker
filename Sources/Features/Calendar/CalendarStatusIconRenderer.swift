import AppKit

enum CalendarStatusIconMetrics {
    static let statusItemLength: CGFloat = 28
    static let imageSize = NSSize(width: 26, height: 20)
    static let badgeRect = NSRect(x: 0.75, y: 2, width: 24.5, height: 16)
    static let badgeCornerRadius: CGFloat = 3
    static let textFontSize: CGFloat = 12
    static let textWeight = NSFont.Weight.semibold
    static let textRect = NSRect(x: 0, y: 2.5, width: 26, height: 15)
}

enum CalendarStatusIconRenderer {
    static func image(for date: Date, calendar: Calendar = .current) -> NSImage {
        let size = CalendarStatusIconMetrics.imageSize
        let formatter = CalendarDisplayFormatter(calendar: calendar)
        let text = formatter.menuBarDayText(for: date) as NSString

        let image = NSImage(size: size, flipped: false) { _ in
            let badgePath = NSBezierPath(
                roundedRect: CalendarStatusIconMetrics.badgeRect,
                xRadius: CalendarStatusIconMetrics.badgeCornerRadius,
                yRadius: CalendarStatusIconMetrics.badgeCornerRadius
            )
            NSColor.white.setFill()
            badgePath.fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: CalendarStatusIconMetrics.textFontSize,
                    weight: CalendarStatusIconMetrics.textWeight
                ),
                .foregroundColor: NSColor(calibratedRed: 0.11, green: 0.42, blue: 0.58, alpha: 1),
                .paragraphStyle: paragraph
            ]

            text.draw(in: CalendarStatusIconMetrics.textRect, withAttributes: attributes)
            return true
        }

        image.isTemplate = false
        return image
    }
}
