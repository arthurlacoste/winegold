import Foundation

public final class CompiledActionCache {
    private var cachedSignature = ""
    private var cachedSet: CompiledActionSet?
    public private(set) var compilationCount = 0

    public init() {}

    public func compiled(actions: [Action]) -> CompiledActionSet {
        let signature = actions.map { action in
            let trigger = action.triggerExpression ?? ""
            return "\(action.id.uuidString)|\(action.enabled)|\(trigger)|\(action.acceptedExtensions.joined(separator: ","))"
        }.joined(separator: "\n")
        if signature == cachedSignature, let cachedSet { return cachedSet }
        let compiled = CompiledActionSet(actions: actions)
        cachedSignature = signature
        cachedSet = compiled
        compilationCount += 1
        return compiled
    }

    public func invalidate() {
        cachedSignature = ""
        cachedSet = nil
    }
}
