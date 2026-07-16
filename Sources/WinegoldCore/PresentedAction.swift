import Foundation

public struct PresentedAction: Equatable {
    public let action: Action
    public let parentName: String?
    public let parentExternalID: String?
    public let childActionID: String?
    public let usageCount: Int
    public let localOrderOverride: Int?

    public init(
        action: Action,
        parentName: String? = nil,
        parentExternalID: String? = nil,
        childActionID: String? = nil,
        usageCount: Int = 0,
        localOrderOverride: Int? = nil
    ) {
        self.action = action
        self.parentName = parentName
        self.parentExternalID = parentExternalID
        self.childActionID = childActionID
        self.usageCount = usageCount
        self.localOrderOverride = localOrderOverride
    }
}

public struct ActionPresentationPolicy {
    public let defaultLimit: Int
    public let searchLimit: Int

    public init(defaultLimit: Int = 10, searchLimit: Int = 50) {
        self.defaultLimit = defaultLimit
        self.searchLimit = searchLimit
    }

    public func present(_ actions: [PresentedAction], query: String = "") -> [PresentedAction] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmedQuery.isEmpty ? actions : actions.filter { matches($0, query: trimmedQuery) }
        let sorted = sort(filtered)
        return Array(sorted.prefix(trimmedQuery.isEmpty ? defaultLimit : searchLimit))
    }

    public func sort(_ actions: [PresentedAction]) -> [PresentedAction] {
        let manuallyOrderedParents = Set(actions.compactMap { item in
            item.localOrderOverride == nil ? nil : item.parentExternalID
        })
        return actions.sorted { lhs, rhs in
            if lhs.action.isFavorite != rhs.action.isFavorite { return lhs.action.isFavorite }

            let sameParent = lhs.parentExternalID != nil && lhs.parentExternalID == rhs.parentExternalID
            if sameParent, let parent = lhs.parentExternalID, manuallyOrderedParents.contains(parent) {
                let leftOrder = lhs.localOrderOverride ?? Int.max
                let rightOrder = rhs.localOrderOverride ?? Int.max
                if leftOrder != rightOrder { return leftOrder < rightOrder }
            } else if lhs.usageCount != rhs.usageCount {
                return lhs.usageCount > rhs.usageCount
            }

            if lhs.action.displayOrder != rhs.action.displayOrder {
                return lhs.action.displayOrder < rhs.action.displayOrder
            }
            return lhs.action.name.localizedCaseInsensitiveCompare(rhs.action.name) == .orderedAscending
        }
    }

    private func matches(_ item: PresentedAction, query: String) -> Bool {
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let fields = [
            item.action.name,
            item.action.description,
            item.parentName,
            item.action.category,
            item.childActionID,
            item.parentExternalID
        ].compactMap { $0 }
        return fields.contains { field in
            field.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle)
        }
    }
}
