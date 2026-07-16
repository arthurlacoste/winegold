import Foundation

public enum SavedRunResolution: Equatable {
    case available(Action)
    case unavailable(String)
}

public struct SavedRunResolver {
    public init() {}

    public func resolve(_ item: RunHistoryItem, actions: [Action]) -> SavedRunResolution {
        guard let action = actions.first(where: { $0.id == item.actionId }) else {
            return .unavailable("This action no longer exists in its recipe.")
        }
        return .available(action)
    }
}
