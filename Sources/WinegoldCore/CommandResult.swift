import Foundation

public enum ExecutionStatus: String, Codable {
    case pending
    case running
    case success
    case failed
    case cancelled
    case timeout
}

public struct CommandResult: Identifiable, Codable {
    public var id: UUID
    public var actionId: UUID
    public var actionName: String
    public var inputFiles: [String]
    public var outputFiles: [String]
    public var status: ExecutionStatus
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        actionId: UUID,
        actionName: String = "",
        inputFiles: [String] = [],
        outputFiles: [String] = [],
        status: ExecutionStatus = .pending,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.actionId = actionId
        self.actionName = actionName
        self.inputFiles = inputFiles
        self.outputFiles = outputFiles
        self.status = status
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
