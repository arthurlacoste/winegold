import XCTest
@testable import WinegoldCore

final class KeyboardActionSelectionTests: XCTestCase {
    func testDownWrapsAndUpWraps() {
        var selection = KeyboardActionSelection()
        selection.moveDown(count: 3)
        XCTAssertEqual(selection.index, 1)
        selection.moveDown(count: 3)
        selection.moveDown(count: 3)
        XCTAssertEqual(selection.index, 0)
        selection.moveUp(count: 3)
        XCTAssertEqual(selection.index, 2)
    }

    func testResetAndClampKeepFirstVisibleActionSelected() {
        var selection = KeyboardActionSelection(index: 8)
        selection.clamp(count: 3)
        XCTAssertEqual(selection.index, 2)
        selection.reset()
        XCTAssertEqual(selection.index, 0)
        selection.clamp(count: 0)
        XCTAssertEqual(selection.index, 0)
    }
}
