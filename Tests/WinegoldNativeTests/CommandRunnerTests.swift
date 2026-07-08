import XCTest
@testable import WinegoldCore

final class CommandRunnerTests: XCTestCase {
    private let runner = CommandRunner()

    func testEchoOk() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/echo",
            arguments: ["hello world"]
        )
        let result = await runner.run(request: request)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hello world"))
    }

    func testExitOne() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/bash",
            arguments: ["-c", "exit 1"]
        )
        let result = await runner.run(request: request)
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.exitCode, 1)
    }

    func testNonExistentExecutable() async {
        let request = CommandExecutionRequest(
            executablePath: "/usr/bin/nonexistent_abc123"
        )
        let result = await runner.run(request: request)
        XCTAssertEqual(result.status, .failed)
        XCTAssertFalse(result.stderr.isEmpty)
    }

    func testStderrCaptured() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/bash",
            arguments: ["-c", "echo error >&2; exit 1"]
        )
        let result = await runner.run(request: request)
        XCTAssertFalse(result.stderr.isEmpty)
        XCTAssertTrue(result.stderr.contains("error"))
    }

    func testTimeout() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/sleep",
            arguments: ["10"],
            timeoutSeconds: 1
        )
        let result = await runner.run(request: request)
        XCTAssertEqual(result.status, .timeout)
    }

    func testArgumentsWithSpaces() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/echo",
            arguments: ["file with spaces.txt"]
        )
        let result = await runner.run(request: request)
        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(result.stdout.contains("file with spaces.txt"))
    }
}
