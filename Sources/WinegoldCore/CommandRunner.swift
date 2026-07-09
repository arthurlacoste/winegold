import Foundation

public enum CommandRunnerError: LocalizedError {
    case executableNotFound(String)
    case notExecutable(String)
    case timeout(seconds: Int)
    case processError(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path): return "Executable not found: \(path)"
        case .notExecutable(let path): return "Not executable: \(path)"
        case .timeout(let seconds): return "Timeout after \(seconds)s"
        case .processError(let msg): return msg
        }
    }
}

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutValue = ""
    private var stderrValue = ""

    func appendStdout(_ data: Data) {
        guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return }
        lock.lock(); stdoutValue += string; lock.unlock()
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return }
        lock.lock(); stderrValue += string; lock.unlock()
    }

    var snapshot: (stdout: String, stderr: String) {
        lock.lock(); defer { lock.unlock() }
        return (stdoutValue, stderrValue)
    }

    func snapshot(maxCharacters: Int) -> (stdout: String, stderr: String) {
        lock.lock(); defer { lock.unlock() }
        return (
            stdout: Self.suffix(stdoutValue, maxCharacters: maxCharacters),
            stderr: Self.suffix(stderrValue, maxCharacters: maxCharacters)
        )
    }

    private static func suffix(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return "…\n" + value.suffix(maxCharacters)
    }
}

private final class OutputUpdateGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSentAt = Date.distantPast
    private let minimumInterval: TimeInterval

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    func shouldSend(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard now.timeIntervalSince(lastSentAt) >= minimumInterval else { return false }
        lastSentAt = now
        return true
    }
}

public typealias CommandOutputHandler = @Sendable (_ stdout: String, _ stderr: String) -> Void

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
        await run(request: request, onOutput: nil)
    }

    public func run(request: CommandExecutionRequest, onOutput: CommandOutputHandler?) async -> CommandResult {
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

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let timeoutState = TimeoutState()
        let outputCapture = OutputCapture()
        let outputGate = OutputUpdateGate(minimumInterval: 0.2)
        let maxLiveCharacters = 12_000

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            outputCapture.appendStdout(data)
            guard onOutput != nil, outputGate.shouldSend() else { return }
            let snapshot = outputCapture.snapshot(maxCharacters: maxLiveCharacters)
            onOutput?(snapshot.stdout, snapshot.stderr)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            outputCapture.appendStderr(data)
            guard onOutput != nil, outputGate.shouldSend() else { return }
            let snapshot = outputCapture.snapshot(maxCharacters: maxLiveCharacters)
            onOutput?(snapshot.stdout, snapshot.stderr)
        }

        return await withTaskGroup(of: CommandResult.self) { group in
            group.addTask {
                do {
                    try process.run()
                    try? stdinPipe.fileHandleForWriting.close()
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

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                outputCapture.appendStdout(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
                outputCapture.appendStderr(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                let snapshot = outputCapture.snapshot
                let stdout = snapshot.stdout
                var stderr = snapshot.stderr

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
