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
        let parsedExpressions: [UUID: TriggerExpression] = Dictionary(uniqueKeysWithValues: enabled.compactMap { action in
            guard let source = action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty,
                  let expression = try? TriggerParser().parse(source) else { return nil }
            return (action.id, expression)
        })
        let itemValues = items.map { $0.values(includeInside: false) }
        let needsInside = parsedExpressions.values.contains { $0.referencedFields.contains("inside") }
        let itemValuesWithInside = needsInside ? items.map { $0.values(includeInside: true) } : []

        return enabled.filter { action in
            if let source = action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
                guard let expression = parsedExpressions[action.id] else { return false }
                let values = expression.referencedFields.contains("inside") ? itemValuesWithInside : itemValues
                return values.allSatisfy { TriggerEvaluator().evaluate(expression, values: $0) }
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
