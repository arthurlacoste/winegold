import Foundation

public struct ActionMatcher {
    public init() {}

    public func matchingActions(for files: [URL], actions: [Action]) -> [Action] {
        guard !files.isEmpty else { return [] }
        return matchingActions(forItems: files.map { DraggedItem(executionURL: $0) }, actions: actions)
    }

    public func matchingActions(forItems items: [DraggedItem], actions: [Action]) -> [Action] {
        guard !items.isEmpty else { return [] }
        return actions.filter { $0.enabled && matches($0, forItems: items) }
    }

    public func matches(_ action: Action, forItems items: [DraggedItem]) -> Bool {
        guard !items.isEmpty else { return false }
        if let source = action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            guard let expression = try? TriggerParser().parse(source) else { return false }
            let includeInside = expression.referencedFields.contains("inside")
            return items.allSatisfy {
                TriggerEvaluator().evaluate(expression, values: $0.values(includeInside: includeInside))
            }
        }
        let accepted = normalizedExtensions(action.acceptedExtensions)
        guard !accepted.isEmpty else { return false }
        if accepted.contains("*") { return true }
        return items.allSatisfy { accepted.contains($0.executionURL.pathExtension.lowercased()) }
    }

    private func normalizedExtensions(_ extensions: [String]) -> [String] {
        extensions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
    }
}
