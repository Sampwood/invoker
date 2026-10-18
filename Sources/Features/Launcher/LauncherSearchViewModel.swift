import Foundation
import SwiftUI

@MainActor
final class LauncherSearchViewModel: ObservableObject {
    let registry: LauncherCommandRegistry

    @Published var query = ""
    @Published private(set) var selectedCommandID: String?
    @Published private(set) var focusRequestID = UUID()

    init(registry: LauncherCommandRegistry) {
        self.registry = registry
    }

    var results: [LauncherCommand] {
        registry.matchingCommands(for: query)
    }

    func prepare() {
        query = ""
        selectedCommandID = registry.commands.first?.id
        requestSearchFocus()
    }

    func requestSearchFocus() {
        focusRequestID = UUID()
    }

    func select(_ command: LauncherCommand) {
        selectedCommandID = command.id
    }

    func selectFirstMatch() {
        selectedCommandID = results.first?.id
    }

    func reconcileSelection() {
        guard !results.isEmpty else {
            selectedCommandID = nil
            return
        }

        if let selectedCommandID,
           results.contains(where: { $0.id == selectedCommandID }) {
            return
        }

        selectedCommandID = results.first?.id
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            selectedCommandID = nil
            return
        }

        guard let currentCommandID = selectedCommandID,
              let currentIndex = results.firstIndex(where: { $0.id == currentCommandID })
        else {
            selectedCommandID = results.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedCommandID = results[nextIndex].id
    }

    func selectedCommand() -> LauncherCommand? {
        guard let selectedCommandID else {
            return nil
        }
        return results.first { $0.id == selectedCommandID }
    }
}
