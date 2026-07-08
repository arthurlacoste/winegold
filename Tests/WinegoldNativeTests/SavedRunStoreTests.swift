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
}
