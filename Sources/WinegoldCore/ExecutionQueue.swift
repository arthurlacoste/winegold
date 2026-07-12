import Foundation

public enum QueuedExecutionState: Equatable, Sendable {
    case waiting
    case running
    case succeeded
    case failed
}

public struct QueuedExecution: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let file: URL
    public var state: QueuedExecutionState

    public init(id: UUID = UUID(), file: URL, state: QueuedExecutionState = .waiting) {
        self.id = id
        self.file = file
        self.state = state
    }
}

public struct ExecutionQueue: Equatable, Sendable {
    public private(set) var executions: [QueuedExecution]

    public init(files: [URL]) {
        executions = files.map { QueuedExecution(file: $0) }
    }

    public var activeExecution: QueuedExecution? {
        executions.first { $0.state == .running }
    }

    public var completedCount: Int {
        executions.count { $0.state == .succeeded || $0.state == .failed }
    }

    public var progressText: String {
        guard !executions.isEmpty else { return "0 of 0" }
        let current = min(completedCount + (activeExecution == nil ? 0 : 1), executions.count)
        return "\(current) of \(executions.count)"
    }

    @discardableResult
    public mutating func startNext() -> QueuedExecution? {
        guard activeExecution == nil,
              let index = executions.firstIndex(where: { $0.state == .waiting }) else { return nil }
        executions[index].state = .running
        return executions[index]
    }

    @discardableResult
    public mutating func completeActive(with status: ExecutionStatus) -> QueuedExecution? {
        guard let index = executions.firstIndex(where: { $0.state == .running }) else { return nil }
        executions[index].state = status == .success ? .succeeded : .failed
        return executions[index]
    }
}
