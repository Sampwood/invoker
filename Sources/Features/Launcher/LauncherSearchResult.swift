import Foundation

enum LauncherSearchResult: Identifiable {
    case command(LauncherCommand)
    case application(LauncherApplication)
    case calculation(value: String, quoteTime: Date? = nil)

    var id: String {
        switch self {
        case .command(let command): "command:" + command.id
        case .application(let application): application.id
        case .calculation: "calculation"
        }
    }
    var title: String {
        switch self {
        case .command(let command): command.title
        case .application(let application): application.title
        case .calculation(let value, let quoteTime): quoteTime == nil ? value : "¥" + value
        }
    }
    var subtitle: String {
        if case .command(let command) = self { return command.subtitle }
        if case .calculation(_, let quoteTime?) = self {
            return "报价时间：\(quoteTime.formatted(date: .numeric, time: .shortened))"
        }
        return ""
    }
    var shortcut: String? {
        if case .command(let command) = self { return command.shortcut }
        return nil
    }
    var systemImage: String {
        if case .command(let command) = self { return command.systemImage }
        if case .calculation = self { return "equal.circle" }
        return "app"
    }
    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }
}
