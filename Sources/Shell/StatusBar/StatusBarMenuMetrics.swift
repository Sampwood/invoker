import CoreGraphics

enum StatusBarMenuMetrics {
    static let bodyColorName = "white"
    static let bodyWidth: CGFloat = 152
    static let bodyHeight: CGFloat = 84
    static let rowHeight: CGFloat = 34
    static let rowHorizontalPadding: CGFloat = 12
    static let rowCornerRadius: CGFloat = 5
    static let rowHoverOpacity: Double = 0.07
    static let textFontSize: CGFloat = 15
    static let shadowPadding: CGFloat = CalendarPopoverMetrics.shadowPadding
    static let shadowOpacity: Double = CalendarPopoverMetrics.shadowOpacity
    static let shadowRadius: CGFloat = CalendarPopoverMetrics.shadowRadius
    static let shadowYOffset: CGFloat = CalendarPopoverMetrics.shadowYOffset
    static let bodyCornerRadius: CGFloat = CalendarPopoverMetrics.bodyCornerRadius
    static let bodyBorderOpacity: Double = CalendarPopoverMetrics.bodyBorderOpacity
    static let bodyBorderLineWidth: CGFloat = CalendarPopoverMetrics.bodyBorderLineWidth
    static let windowWidth: CGFloat = bodyWidth + shadowPadding * 2
    static let windowHeight: CGFloat = bodyHeight + shadowPadding * 2
}
