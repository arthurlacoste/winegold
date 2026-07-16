import XCTest
@testable import WinegoldCore

final class PanelWorkGenerationTests: XCTestCase {
    func testNewPanelSessionInvalidatesPreviousWork() {
        var generations = PanelWorkGeneration()
        let first = generations.begin()
        let second = generations.begin()

        XCTAssertFalse(generations.accepts(first))
        XCTAssertTrue(generations.accepts(second))
    }

    func testClosingPanelInvalidatesPendingPublication() {
        var generations = PanelWorkGeneration()
        let pending = generations.begin()

        generations.invalidate()

        XCTAssertFalse(generations.accepts(pending))
    }

    func testWraparoundStillProducesCurrentGeneration() {
        var generations = PanelWorkGeneration()
        for _ in 0..<3 { generations.invalidate() }
        let current = generations.begin()

        XCTAssertTrue(generations.accepts(current))
    }
}
