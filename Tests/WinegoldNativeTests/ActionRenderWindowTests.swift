import XCTest
@testable import WinegoldCore

final class ActionRenderWindowTests: XCTestCase {
    func testRendersOnlyInitialBatch() {
        let window = ActionRenderWindow(batchSize: 20)
        XCTAssertEqual(window.visibleCount(total: 100), 20)
        XCTAssertTrue(window.hasMore(total: 100))
    }

    func testLoadsNextBatchWithoutExceedingTotal() {
        var window = ActionRenderWindow(batchSize: 20)
        XCTAssertTrue(window.loadNext(total: 35))
        XCTAssertEqual(window.visibleCount(total: 35), 35)
        XCTAssertFalse(window.loadNext(total: 35))
    }

    func testResetReturnsToSmallRenderSet() {
        var window = ActionRenderWindow(batchSize: 10)
        _ = window.loadNext(total: 100)
        window.reset()
        XCTAssertEqual(window.visibleCount(total: 100), 10)
    }
}
