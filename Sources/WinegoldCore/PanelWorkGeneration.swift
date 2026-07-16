public struct PanelWorkGeneration: Equatable, Sendable {
    public private(set) var current: UInt64 = 0

    public init() {}

    @discardableResult
    public mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    public mutating func invalidate() {
        current &+= 1
    }

    public func accepts(_ generation: UInt64) -> Bool {
        generation == current
    }
}
