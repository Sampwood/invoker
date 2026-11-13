import Foundation

@MainActor
final class LauncherUsageStore {
    static let key = "launcher.usage.v1"
    static let window: TimeInterval = 30 * 24 * 60 * 60
    private let defaults: UserDefaults
    private let now: () -> Date
    private var events: [String: [Date]]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        events = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: [Date]].self, from: $0) } ?? [:]
    }

    func snapshot() -> [String: [Date]] {
        let end = now()
        let start = end.addingTimeInterval(-Self.window)
        let filtered = events.mapValues { $0.filter { $0 >= start && $0 <= end } }.filter { !$0.value.isEmpty }
        if filtered != events { events = filtered; persist() }
        return events
    }

    func record(_ id: String) {
        _ = snapshot()
        events[id, default: []].append(now())
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) { defaults.set(data, forKey: Self.key) }
    }
}
