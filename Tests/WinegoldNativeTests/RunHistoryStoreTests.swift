import XCTest
@testable import WinegoldCore

final class RunHistoryStoreTests: XCTestCase {
    private var db: Database!
    private var store: RunHistoryStore!

    override func setUp() {
        super.setUp()
        db = try! Database(path: ":memory:")
        try! Migrations(db: db).run()
        store = RunHistoryStore(db: db)
    }

    func testAddAndList() throws {
        let result = CommandResult(
            actionId: UUID(),
            actionName: "Test",
            inputFiles: ["/tmp/file.txt"],
            status: .success,
            exitCode: 0,
            stdout: "ok",
            stderr: "",
            startedAt: Date(),
            endedAt: Date()
        )
        try store.addRun(result)
        let items = try store.recentRuns(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.actionName, "Test")
        XCTAssertEqual(items.first?.status, .success)
    }

    func testClearHistory() throws {
        try store.addRun(CommandResult(actionId: UUID(), actionName: "A"))
        try store.addRun(CommandResult(actionId: UUID(), actionName: "B"))
        try store.clearHistory()
        let items = try store.recentRuns()
        XCTAssertTrue(items.isEmpty)
    }

    func testLimit() throws {
        for i in 0..<10 {
            try store.addRun(CommandResult(actionId: UUID(), actionName: "\(i)"))
        }
        let items = try store.recentRuns(limit: 3)
        XCTAssertEqual(items.count, 3)
    }

    func testOrderedByDateDesc() throws {
        let earlier = CommandResult(actionId: UUID(), actionName: "first", startedAt: Date().addingTimeInterval(-100))
        let later = CommandResult(actionId: UUID(), actionName: "second", startedAt: Date())

        try store.addRun(earlier)
        try store.addRun(later)

        let items = try store.recentRuns(limit: 10)
        XCTAssertEqual(items[0].actionName, "second")
        XCTAssertEqual(items[1].actionName, "first")
    }

    func testChildActionMetadataRoundTrip() throws {
        let actionID = UUID()
        let result = CommandResult(
            actionId: actionID,
            actionName: "Run tests - Node project",
            parentRecipeID: "winegold.node-project",
            childActionID: "test",
            parentRecipeName: "Node project",
            childActionName: "Run tests",
            inputFiles: ["/tmp/project"],
            status: .failed,
            exitCode: 1
        )

        try store.addRun(result)

        let item = try XCTUnwrap(store.recentRuns().first)
        XCTAssertEqual(item.actionId, actionID)
        XCTAssertEqual(item.actionName, "Run tests - Node project")
        XCTAssertEqual(item.parentRecipeID, "winegold.node-project")
        XCTAssertEqual(item.childActionID, "test")
        XCTAssertEqual(item.parentRecipeName, "Node project")
        XCTAssertEqual(item.childActionName, "Run tests")
    }

    func testLegacyHistoryRowKeepsWorkingWithNullChildMetadata() throws {
        let id = UUID()
        let actionID = UUID()
        let stmt = try db.prepare("""
            INSERT INTO run_history (id, action_id, action_name, input_files, output_files, status,
            exit_code, stdout, stderr, started_at, ended_at)
            VALUES (?, ?, 'Legacy action', '', '', 'success', 0, '', '', '2026-01-01T00:00:00+0000', NULL)
        """)
        stmt.bindText(id.uuidString, at: 1)
        stmt.bindText(actionID.uuidString, at: 2)
        _ = stmt.step()

        let item = try XCTUnwrap(store.recentRuns().first)
        XCTAssertEqual(item.actionName, "Legacy action")
        XCTAssertNil(item.parentRecipeID)
        XCTAssertNil(item.childActionID)
    }

}
