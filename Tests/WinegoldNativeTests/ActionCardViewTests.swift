import AppKit
import XCTest
@testable import WinegoldUI

final class ActionCardViewTests: XCTestCase {
    func testSetupLabelIsVerticallyCenteredInRunCard() throws {
        let container = NSRect(x: 184, y: 16, width: 116, height: 30)
        let label = verticallyCenteredTextFrame(in: container, textHeight: 16)

        XCTAssertEqual(label.midY, container.midY, accuracy: 0.5)
        XCTAssertLessThan(label.height, container.height)
    }

    func testPillBadgeLabelIsVerticallyCentered() {
        let badge = PillBadgeView(title: "Needs setup", color: .systemOrange)
        badge.frame = NSRect(x: 0, y: 0, width: 92, height: 24)

        badge.layoutSubtreeIfNeeded()

        XCTAssertEqual(badge.label.frame.midY, badge.bounds.midY, accuracy: 0.5)
        XCTAssertLessThan(badge.label.frame.height, badge.bounds.height)
    }
}
