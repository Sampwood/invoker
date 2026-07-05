import CoreGraphics

struct CalendarPopoverPresentationLayout: Equatable {
    let origin: CGPoint
    let arrowCenterX: CGFloat
}

enum CalendarPopoverPresentationGeometry {
    static let horizontalMargin: CGFloat = 6
    static let verticalOffset: CGFloat = 4

    static func layout(
        buttonRectOnScreen: CGRect,
        screenFrame: CGRect,
        panelSize: CGSize
    ) -> CalendarPopoverPresentationLayout {
        let preferredBodyX = buttonRectOnScreen.midX - CalendarPopoverMetrics.panelWidth / 2
        let minX = screenFrame.minX + horizontalMargin
        let maxX = max(minX, screenFrame.maxX - CalendarPopoverMetrics.panelWidth - horizontalMargin)
        let bodyX = min(max(preferredBodyX, minX), maxX)
        let x = bodyX - CalendarPopoverMetrics.shadowPadding
        let y = buttonRectOnScreen.minY
            - CalendarPopoverMetrics.panelHeight
            - verticalOffset
            - CalendarPopoverMetrics.shadowPadding
        let preferredArrowCenterX = buttonRectOnScreen.midX - bodyX
        let arrowCenterX = min(
            max(preferredArrowCenterX, CalendarPopoverMetrics.arrowHorizontalMargin),
            min(
                CalendarPopoverMetrics.panelWidth - CalendarPopoverMetrics.arrowHorizontalMargin,
                panelSize.width - CalendarPopoverMetrics.shadowPadding - CalendarPopoverMetrics.arrowHorizontalMargin
            )
        )

        return CalendarPopoverPresentationLayout(
            origin: CGPoint(x: x, y: y),
            arrowCenterX: arrowCenterX
        )
    }
}
