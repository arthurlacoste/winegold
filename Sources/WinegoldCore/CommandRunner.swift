import Foundation

public enum CommandRunnerError: LocalizedError {
    case executableNotFound(String)
    case notExecutable(String)
    case timeout(seconds: Int)
    case processError(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path): return "Exécutable introuvable : \(path)"
        case .notExecutable(let path): return "Non exécutable : \(path)"
        case .timeout(let seconds): return "Timeout après \(seconds)s"
        case .processError(let msg): return msg
        }
    }
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var didTimeout: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public actor CommandRunner {
    public init() {}

    public func run(request: CommandExecutionRequest) async -> CommandResult {
        let startTime = Date()
        let id = UUID()

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: request.executablePath, isDirectory: &isDir) else {
            return CommandResult(
                id: id,
                actionId: UUID(),
                status: .failed,
                exitCode: nil,
                stdout: "",
                stderr: "\(CommandRunnerError.executableNotFound(request.executablePath).localizedDescription)\n",
                startedAt: startTime,
                endedAt: Date()
            )
        }
        guard fm.isExecutableFile(atPath: request.executablePath) else {
            return CommandResult(
                id: id,
                actionId: UUID(),
                status: .failed,
                exitCode: nil,
                stdout: "",
                stderr: "\(CommandRunnerError.notExecutable(request.executablePath).localizedDescription)\n",
                startedAt: startTime,
                endedAt: Date()
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = request.arguments

        if let wd = request.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }

        var env = ProcessInfo.processInfo.environment
        if let customEnv = request.environment {
            env.merge(customEnv) { _, new in new }
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let timeoutState = TimeoutState()

        return await withTaskGroup(of: CommandResult.self) { group in
            group.addTask {
                do {
                    try process.run()
                } catch {
                    return CommandResult(
                        id: id,
                        actionId: UUID(),
                        status: .failed,
                        exitCode: nil,
                        stdout: "",
                        stderr: "\(CommandRunnerError.processError(error.localizedDescription).localizedDescription)\n",
                        startedAt: startTime,
                        endedAt: Date()
                    )
                }

                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(request.timeoutSeconds) * 1_000_000_000)
                    guard !Task.isCancelled, process.isRunning else { return }
                    timeoutState.markTimedOut()
                    process.terminate()
                }

                process.waitUntilExit()
                timeoutTask.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                var stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let status: ExecutionStatus
                if timeoutState.didTimeout {
                    status = .timeout
                    if stderr.isEmpty {
                        stderr = "\(CommandRunnerError.timeout(seconds: request.timeoutSeconds).localizedDescription)\n"
                    }
                } else if process.terminationStatus == 0 {
                    status = .success
                } else {
                    status = .failed
                }

                return CommandResult(
                    id: id,
                    actionId: UUID(),
                    status: status,
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr,
                    startedAt: startTime,
                    endedAt: Date()
                )
            }

            return await group.next() ?? CommandResult(
                id: id, actionId: UUID(), status: .failed, startedAt: startTime, endedAt: Date()
            )
        }
    }
}
