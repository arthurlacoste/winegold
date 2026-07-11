import XCTest
@testable import WinegoldCore

final class PanelDismissalPolicyTests: XCTestCase {
    func testModalFileSelectionBlocksAutomaticDismissal() {
        XCTAssertFalse(
            PanelDismissalPolicy.allowsAutomaticDismissal(
                staysOpen: false,
                isModalInteractionActive: true,
                isVisible: true,
                isAnimatingOut: false,
                hasActiveFileDrag: false
            )
        )
    }

    func testIdleVisiblePanelAllowsAutomaticDismissal() {
        XCTAssertTrue(
            PanelDismissalPolicy.allowsAutomaticDismissal(
                staysOpen: false,
                isModalInteractionActive: false,
                isVisible: true,
                isAnimatingOut: false,
                hasActiveFileDrag: false
            )
        )
    }
}
