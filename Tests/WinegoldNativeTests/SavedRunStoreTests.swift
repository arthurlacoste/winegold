import XCTest
import WinegoldCore

final class SavedRunStoreTests: XCTestCase {
    func testSaveAndUnsaveRun() {
        let suite = "SavedRunStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedRunStore(defaults: defaults)
        let item = RunHistoryItem(actionId: UUID(), actionName: "Print", inputFiles: ["/tmp/a.txt"])

        XCTAssertFalse(store.isSaved(item))
        store.save(item)
        XCTAssertTrue(store.isSaved(item))
        XCTAssertEqual(store.savedRuns().first?.actionName, "Print")
        store.unsave(item)
        XCTAssertFalse(store.isSaved(item))
    }

    func testResolverUsesExactActionIDWithoutNameFallback() {
        let originalID = UUID()
        let item = RunHistoryItem(
            actionId: originalID,
            actionName: "Run tests - Node project",
            parentRecipeID: "winegold.node-project",
            childActionID: "test",
            parentRecipeName: "Node project",
            childActionName: "Run tests"
        )
        let renamedReplacement = Action(name: "Run tests - Node project", executablePath: "/bin/zsh")

        XCTAssertEqual(
            SavedRunResolver().resolve(item, actions: [renamedReplacement]),
            .unavailable("This action no longer exists in its recipe.")
        )
    }

    func testResolverFindsRenamedChildByStableID() {
        let id = UUID()
        let item = RunHistoryItem(actionId: id, actionName: "Old name")
        let renamed = Action(id: id, name: "New name", executablePath: "/bin/zsh")

        XCTAssertEqual(SavedRunResolver().resolve(item, actions: [renamed]), .available(renamed))
    }

}
