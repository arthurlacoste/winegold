import Foundation

public struct SavedRunStore {
    private let defaults: UserDefaults
    private let key = "savedRunHistoryItems"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func savedRuns(limit: Int = 20) -> [RunHistoryItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([RunHistoryItem].self, from: data) else {
            return []
        }
        return Array(items.prefix(limit))
    }

    public func isSaved(_ item: RunHistoryItem) -> Bool {
        savedRuns(limit: Int.max).contains { saved in
            saved.id == item.id || SavedRunStore.fingerprint(saved) == SavedRunStore.fingerprint(item)
        }
    }

    public func save(_ item: RunHistoryItem) {
        var items = savedRuns(limit: Int.max)
        items.removeAll { saved in
            saved.id == item.id || SavedRunStore.fingerprint(saved) == SavedRunStore.fingerprint(item)
        }
        items.insert(item, at: 0)
        persist(Array(items.prefix(20)))
    }

    public func unsave(_ item: RunHistoryItem) {
        var items = savedRuns(limit: Int.max)
        items.removeAll { saved in
            saved.id == item.id || SavedRunStore.fingerprint(saved) == SavedRunStore.fingerprint(item)
        }
        persist(items)
    }

    private func persist(_ items: [RunHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }

    private static func fingerprint(_ item: RunHistoryItem) -> String {
        [item.actionId.uuidString, item.actionName, item.inputFiles.joined(separator: "|")].joined(separator: "::")
    }
}
