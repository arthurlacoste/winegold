import Foundation

public enum TriggerCost: Int, CaseIterable, Comparable, Sendable {
    case cheap
    case metadata
    case content

    public static func < (lhs: TriggerCost, rhs: TriggerCost) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct CompiledActionTrigger {
    public let action: Action
    public let expression: TriggerExpression?
    public let referencedFields: Set<String>
    public let normalizedExtensions: Set<String>
    public let cost: TriggerCost
    public let sourceKey: String
}

public struct CompiledActionSet {
    public let triggers: [CompiledActionTrigger]
    public let sourceKeys: [UUID: String]

    public init(actions: [Action]) {
        var keys: [UUID: String] = [:]
        triggers = actions.compactMap { action -> CompiledActionTrigger? in
            guard action.enabled else { return nil }
            let source = action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = source.isEmpty
                ? "extensions:\(action.acceptedExtensions.joined(separator: ","))"
                : "trigger:\(source)"
            keys[action.id] = key

            if source.isEmpty {
                let extensions = Set(action.acceptedExtensions.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }.filter { !$0.isEmpty })
                guard !extensions.isEmpty else { return nil }
                return CompiledActionTrigger(
                    action: action,
                    expression: nil,
                    referencedFields: ["extension"],
                    normalizedExtensions: extensions,
                    cost: .cheap,
                    sourceKey: key
                )
            }

            guard let expression = try? TriggerParser().parse(source) else { return nil }
            let fields = expression.referencedFields
            return CompiledActionTrigger(
                action: action,
                expression: expression,
                referencedFields: fields,
                normalizedExtensions: [],
                cost: Self.cost(for: fields),
                sourceKey: key
            )
        }
        sourceKeys = keys
    }

    private static func cost(for fields: Set<String>) -> TriggerCost {
        if fields.contains("inside") || fields.contains("text") { return .content }
        let metadataFields: Set<String> = ["mimeType", "uti", "size", "finderTags"]
        return fields.isDisjoint(with: metadataFields) ? .cheap : .metadata
    }
}

public struct ProgressiveMatchBatch {
    public let cost: TriggerCost
    public let actions: [Action]
    public let remaining: Int
}

public struct ProgressiveActionMatcher {
    public init() {}

    public func batches(for files: [URL], compiled: CompiledActionSet) -> [ProgressiveMatchBatch] {
        guard !files.isEmpty else { return [] }
        let items = files.map { DraggedItem(executionURL: $0) }
        return batches(forItems: items, compiled: compiled)
    }

    public func batches(forItems items: [DraggedItem], compiled: CompiledActionSet) -> [ProgressiveMatchBatch] {
        guard !items.isEmpty else { return [] }
        let grouped = Dictionary(grouping: compiled.triggers, by: \.cost)
        var resolved: [Action] = []
        var batches: [ProgressiveMatchBatch] = []

        for cost in TriggerCost.allCases {
            let candidates = grouped[cost] ?? []
            guard !candidates.isEmpty else { continue }
            let values = items.map { $0.values(includeInside: cost == .content) }
            let matches = candidates.compactMap { trigger -> Action? in
                if let expression = trigger.expression {
                    return values.allSatisfy { TriggerEvaluator().evaluate(expression, values: $0) }
                        ? trigger.action : nil
                }
                if trigger.normalizedExtensions.contains("*") { return trigger.action }
                return items.allSatisfy {
                    trigger.normalizedExtensions.contains($0.executionURL.pathExtension.lowercased())
                } ? trigger.action : nil
            }
            resolved.append(contentsOf: matches)
            let remaining = compiled.triggers.filter { $0.cost > cost }.count
            batches.append(ProgressiveMatchBatch(cost: cost, actions: resolved, remaining: remaining))
        }
        return batches
    }
}
