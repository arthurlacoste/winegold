public struct PanelResizeState: Equatable, Sendable {
    public private(set) var pendingHeight: Double?
    public private(set) var appliedHeight: Double?
    public private(set) var persistedWidth: Int?
    public private(set) var persistedHeight: Int?

    public init() {}

    public mutating func request(height: Double) -> Bool {
        guard abs((pendingHeight ?? appliedHeight ?? -.infinity) - height) >= 1 else { return false }
        pendingHeight = height
        return true
    }

    public mutating func consumePendingHeight() -> Double? {
        guard let pendingHeight else { return nil }
        self.pendingHeight = nil
        appliedHeight = pendingHeight
        return pendingHeight
    }

    public mutating func shouldPersist(width: Int, height: Int) -> Bool {
        guard width != persistedWidth || height != persistedHeight else { return false }
        persistedWidth = width
        persistedHeight = height
        return true
    }
}
