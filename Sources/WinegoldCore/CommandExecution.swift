import Foundation

public struct CommandExecutionRequest {
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectory: String?
    public var timeoutSeconds: Int
    public var environment: [String: String]?

    public init(
        executablePath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        timeoutSeconds: Int = 30,
        environment: [String: String]? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.environment = environment
    }
}
