import Combine
import CoreGraphics

@MainActor
final class CalendarPopoverPresentationState: ObservableObject {
    @Published var arrowCenterX: CGFloat

    init(arrowCenterX: CGFloat = CalendarPopoverMetrics.panelWidth / 2) {
        self.arrowCenterX = arrowCenterX
    }
}
