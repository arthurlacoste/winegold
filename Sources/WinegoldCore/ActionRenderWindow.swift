public struct ActionRenderWindow: Equatable, Sendable {
    public let batchSize: Int
    public private(set) var limit: Int

    public init(batchSize: Int = 20) {
        self.batchSize = max(1, batchSize)
        limit = max(1, batchSize)
    }

    public func visibleCount(total: Int) -> Int { min(max(0, total), limit) }
    public func hasMore(total: Int) -> Bool { visibleCount(total: total) < total }

    public mutating func loadNext(total: Int) -> Bool {
        guard hasMore(total: total) else { return false }
        limit = min(total, limit + batchSize)
        return true
    }

    public mutating func reset() { limit = batchSize }
}
