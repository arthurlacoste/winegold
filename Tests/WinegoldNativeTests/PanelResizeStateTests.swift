import XCTest
@testable import WinegoldCore

final class PanelResizeStateTests: XCTestCase {
    func testKeepsOnlyLatestPendingHeight() {
        var state = PanelResizeState()
        XCTAssertTrue(state.request(height: 500))
        XCTAssertTrue(state.request(height: 700))
        XCTAssertEqual(state.consumePendingHeight(), 700)
        XCTAssertNil(state.consumePendingHeight())
    }

    func testIgnoresEquivalentResizeRequests() {
        var state = PanelResizeState()
        XCTAssertTrue(state.request(height: 500))
        _ = state.consumePendingHeight()
        XCTAssertFalse(state.request(height: 500.4))
    }

    func testPersistsIdenticalSizeOnlyOnce() {
        var state = PanelResizeState()
        XCTAssertTrue(state.shouldPersist(width: 455, height: 700))
        XCTAssertFalse(state.shouldPersist(width: 455, height: 700))
        XCTAssertTrue(state.shouldPersist(width: 455, height: 701))
    }
}
