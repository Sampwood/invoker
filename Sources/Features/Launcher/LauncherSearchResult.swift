import Foundation

enum LauncherSearchResult: Identifiable {
    case command(LauncherCommand)
    case application(LauncherApplication)

    var id: String {
        switch self {
        case .command(let command): "command:" + command.id
        case .application(let application): application.id
        }
    }
    var title: String {
        switch self {
        case .command(let command): command.title
        case .application(let application): application.title
        }
    }
    var subtitle: String {
        if case .command(let command) = self { return command.subtitle }
        return ""
    }
    var shortcut: String? {
        if case .command(let command) = self { return command.shortcut }
        return nil
    }
    var systemImage: String {
        if case .command(let command) = self { return command.systemImage }
        return "app"
    }
    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }
}
