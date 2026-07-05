import CoreGraphics

enum StatusBarMenuMetrics {
    static let bodyColorName = "nearWhite"
    static let bodyWidth: CGFloat = 106
    static let bodyHeight: CGFloat = 66
    static let bodyVerticalPadding: CGFloat = 6
    static let rowHeight: CGFloat = 27
    static let rowOuterInset: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 9
    static let rowCornerRadius: CGFloat = 4
    static let rowHoverOpacity: Double = 0.06
    static let textFontSize: CGFloat = 13
    static let shadowPadding: CGFloat = 20
    static let shadowOpacity: Double = 0.12
    static let shadowRadius: CGFloat = 10
    static let shadowYOffset: CGFloat = 2
    static let bodyCornerRadius: CGFloat = 7
    static let bodyBorderOpacity: Double = 0.16
    static let bodyBorderLineWidth: CGFloat = CalendarPopoverMetrics.bodyBorderLineWidth
    static let windowWidth: CGFloat = bodyWidth + shadowPadding * 2
    static let windowHeight: CGFloat = bodyHeight + shadowPadding * 2
}
