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
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(sort(actions).prefix(defaultLimit)) }
        let ranked = actions.compactMap { item -> (PresentedAction, Int)? in
            let value = score(item, query: query)
            return value > 0 ? (item, value) : nil
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return sort([lhs.0, rhs.0]).first == lhs.0
        }.map(\.0)
        return Array(ranked.prefix(searchLimit))
    }

    public func sort(_ actions: [PresentedAction]) -> [PresentedAction] {
        let manuallyOrderedParents = Set(actions.compactMap { $0.localOrderOverride == nil ? nil : $0.parentExternalID })
        return actions.sorted { lhs, rhs in
            if lhs.action.isFavorite != rhs.action.isFavorite { return lhs.action.isFavorite }
            let sameParent = lhs.parentExternalID != nil && lhs.parentExternalID == rhs.parentExternalID
            if sameParent, let parent = lhs.parentExternalID, manuallyOrderedParents.contains(parent) {
                let left = lhs.localOrderOverride ?? Int.max, right = rhs.localOrderOverride ?? Int.max
                if left != right { return left < right }
            } else if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
            if lhs.action.displayOrder != rhs.action.displayOrder { return lhs.action.displayOrder < rhs.action.displayOrder }
            return lhs.action.name.localizedCaseInsensitiveCompare(rhs.action.name) == .orderedAscending
        }
    }

    public func score(_ item: PresentedAction, query: String) -> Int {
        let needle = folded(query)
        guard !needle.isEmpty else { return 1 }
        let name = folded(item.action.name)
        if name == needle { return 1000 }
        if name.hasPrefix(needle) { return 850 }
        if name.contains(needle) { return 700 }
        if folded(item.parentName).contains(needle) { return 600 }
        if item.action.acceptedExtensions.map(folded).contains(where: { $0 == needle || $0.contains(needle) }) { return 550 }
        if folded(item.action.category).contains(needle) { return 500 }
        if folded(item.childActionID).contains(needle) || folded(item.parentExternalID).contains(needle) { return 450 }
        if folded(item.action.description).contains(needle) { return 350 }
        if folded(item.action.triggerExpression).contains(needle) { return 250 }
        return 0
    }

    private func folded(_ value: String?) -> String {
        (value ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
