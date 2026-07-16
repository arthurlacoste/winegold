import Foundation

public struct KeyboardActionSelection: Equatable {
    public private(set) var index: Int

    public init(index: Int = 0) {
        self.index = max(0, index)
    }

    public mutating func reset() {
        index = 0
    }

    public mutating func moveUp(count: Int) {
        guard count > 0 else { index = 0; return }
        index = index <= 0 ? count - 1 : index - 1
    }

    public mutating func moveDown(count: Int) {
        guard count > 0 else { index = 0; return }
        index = (index + 1) % count
    }

    public mutating func select(index: Int, count: Int) {
        guard count > 0 else { self.index = 0; return }
        self.index = min(max(index, 0), count - 1)
    }

    public mutating func clamp(count: Int) {
        guard count > 0 else { index = 0; return }
        index = min(max(index, 0), count - 1)
    }
}
