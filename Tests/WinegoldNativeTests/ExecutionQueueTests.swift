import XCTest
@testable import WinegoldCore

final class ExecutionQueueTests: XCTestCase {
    private let files = [
        URL(fileURLWithPath: "/tmp/first.mov"),
        URL(fileURLWithPath: "/tmp/second.mov"),
        URL(fileURLWithPath: "/tmp/third.mov")
    ]

    func testQueuePreservesDropOrderAndStartsOnlyOneExecution() {
        var queue = ExecutionQueue(files: files)

        XCTAssertEqual(queue.executions.map(\.file), files)
        XCTAssertEqual(queue.startNext()?.file, files[0])
        XCTAssertNil(queue.startNext())
        XCTAssertEqual(queue.executions.map(\.state), [.running, .waiting, .waiting])
        XCTAssertEqual(queue.progressText, "1 of 3")
    }

    func testCompletionAdvancesWithoutLosingPerFileResults() {
        var queue = ExecutionQueue(files: files)

        queue.startNext()
        queue.completeActive(with: .success)
        XCTAssertEqual(queue.startNext()?.file, files[1])
        queue.completeActive(with: .failed)
        XCTAssertEqual(queue.startNext()?.file, files[2])

        XCTAssertEqual(queue.executions.map(\.state), [.succeeded, .failed, .running])
        XCTAssertEqual(queue.completedCount, 2)
        XCTAssertEqual(queue.progressText, "3 of 3")
    }

    func testEmptyQueueHasStableProgress() {
        var queue = ExecutionQueue(files: [])

        XCTAssertNil(queue.startNext())
        XCTAssertNil(queue.completeActive(with: .success))
        XCTAssertEqual(queue.progressText, "0 of 0")
    }
}
