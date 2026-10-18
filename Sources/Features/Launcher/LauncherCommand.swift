import Foundation

private struct ScoredCommand {
    let command: LauncherCommand
    let score: Int
}

struct LauncherCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: [String]
    let systemImage: String
    let shortcut: String?
    let action: @MainActor () -> Void

    var searchableText: String {
        ([title, subtitle] + keywords).joined(separator: " ")
    }
}

@MainActor
final class LauncherCommandRegistry {
    private(set) var commands: [LauncherCommand]

    init(commands: [LauncherCommand] = []) {
        self.commands = commands
    }

    func register(_ command: LauncherCommand) {
        commands.append(command)
    }

    func command(withID id: String) -> LauncherCommand? {
        commands.first { $0.id == id }
    }

    func matchingCommands(for query: String) -> [LauncherCommand] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return commands
        }

        var scoredCommands: [ScoredCommand] = []
        for command in commands {
            guard let commandScore = score(command, for: normalizedQuery) else {
                continue
            }
            scoredCommands.append(
                ScoredCommand(command: command, score: commandScore)
            )
        }

        scoredCommands.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            return lhs.command.title.localizedStandardCompare(rhs.command.title) == .orderedAscending
        }

        return scoredCommands.map { $0.command }
    }

    private func score(_ command: LauncherCommand, for query: String) -> Int? {
        let title = command.title
        let normalizedTitle = title.lowercased()
        let normalizedQuery = query.lowercased()

        if normalizedTitle == normalizedQuery {
            return 0
        }
        if normalizedTitle.hasPrefix(normalizedQuery) {
            return 1
        }
        if normalizedTitle.localizedCaseInsensitiveContains(query) {
            return 2
        }
        if command.keywords.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return 3
        }
        if command.subtitle.localizedCaseInsensitiveContains(query) {
            return 4
        }
        if command.searchableText.localizedCaseInsensitiveContains(query) {
            return 5
        }
        return nil
    }
}
