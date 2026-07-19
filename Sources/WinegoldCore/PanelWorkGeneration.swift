import Foundation

public final class PanelWorkGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var current: UInt64 = 0

    public init() {}

    @discardableResult
    public func begin() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        current &+= 1
        return current
    }

    public func invalidate() {
        lock.lock()
        current &+= 1
        lock.unlock()
    }

    public func accepts(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == current
    }

    public func enqueueIfCurrent(
        _ generation: UInt64,
        enqueue: (@escaping () -> Void) -> Void,
        publication: @escaping () -> Void
    ) {
        guard accepts(generation) else { return }
        enqueue { [weak self] in
            guard self?.accepts(generation) == true else { return }
            publication()
        }
    }
}
