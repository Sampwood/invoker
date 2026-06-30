import AppKit

enum StatusBarInteractionAction: Equatable {
    case toggleCalendar
    case showMenu
    case ignore
}

enum StatusBarInteractionRouter {
    static func action(for eventType: NSEvent.EventType) -> StatusBarInteractionAction {
        switch eventType {
        case .leftMouseUp:
            return .toggleCalendar
        case .rightMouseUp:
            return .showMenu
        default:
            return .ignore
        }
    }
}
