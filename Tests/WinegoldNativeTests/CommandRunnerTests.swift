import XCTest
@testable import WinegoldCore

final class CommandRunnerTests: XCTestCase {
    private let runner = CommandRunner()


    func testDisplayCommandQuotesUnsafeArguments() {
        let request = CommandExecutionRequest(
            executablePath: "/bin/echo",
            arguments: ["hello world", "$PATH", "plain-value"]
        )

        XCTAssertEqual(request.displayCommand, "/bin/echo 'hello world' '$PATH' plain-value")
    }

    func testDisplayCommandQuotesEmptyArguments() {
        let request = CommandExecutionRequest(
            executablePath: "/bin/echo",
            arguments: [""]
        )

        XCTAssertEqual(request.displayCommand, "/bin/echo ''")
    }

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

    func testMissingCommandInPipelineFailsEvenWhenLastCommandSucceeds() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "winegold-command-that-does-not-exist | /usr/bin/true"]
        )

        let result = await runner.run(request: request)

        XCTAssertEqual(result.status, .failed)
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("command not found"))
    }

    func testEarlierFailureIsNotHiddenBySuccessfulCleanup() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "/usr/bin/false\n/bin/rm -f /tmp/winegold-missing-file"]
        )

        let result = await runner.run(request: request)

        XCTAssertEqual(result.status, .failed)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testExplicitFailureHandlingRemainsSupported() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "/usr/bin/false || handled=true\ntest \"$handled\" = true"]
        )

        let result = await runner.run(request: request)

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testFailingMiddlePipelineStageFailsRun() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/zsh",
            arguments: ["-lc", "/bin/echo input | /usr/bin/false | /usr/bin/true"]
        )

        let result = await runner.run(request: request)

        XCTAssertEqual(result.status, .failed)
        XCTAssertNotEqual(result.exitCode, 0)
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


    func testStdinIsClosedForNonInteractiveRuns() async {
        let request = CommandExecutionRequest(
            executablePath: "/bin/cat",
            timeoutSeconds: 2
        )

        let result = await runner.run(request: request)
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "")
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
