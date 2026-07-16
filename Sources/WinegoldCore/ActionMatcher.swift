import Foundation

public struct ActionMatcher {
    public init() {}

    public func matchingActions(for files: [URL], actions: [Action]) -> [Action] {
        guard !files.isEmpty else { return [] }
        let items = files.map { DraggedItem(executionURL: $0) }
        return matchingActions(forItems: items, actions: actions)
    }

    public func matchingActions(forItems items: [DraggedItem], actions: [Action]) -> [Action] {
        guard !items.isEmpty else { return [] }
        let enabled = actions.filter { $0.enabled }
        let itemValues = items.map { $0.values }
        return enabled.filter { action in
            if let source = action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
                guard let expression = try? TriggerParser().parse(source) else { return false }
                return itemValues.allSatisfy { TriggerEvaluator().evaluate(expression, values: $0) }
            }
            let acceptedExtensions = normalizedExtensions(action.acceptedExtensions)
            guard !acceptedExtensions.isEmpty else { return false }
            if acceptedExtensions.contains("*") { return true }

            return items.allSatisfy { item in
                let file = item.executionURL
                let ext = file.pathExtension.lowercased()
                return acceptedExtensions.contains(ext)
            }
        }
    }

    private func normalizedExtensions(_ extensions: [String]) -> [String] {
        extensions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
