import XCTest
@testable import WinegoldCore

final class PanelFileSelectionTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/example.png")

    func testBrowseSelectionIsAcceptedAfterPanelWasReset() {
        let signature = PanelFileSelection.signature(for: [file])

        XCTAssertFalse(PanelFileSelection.shouldIgnore(
            files: [file],
            currentFiles: [],
            lastSignature: signature,
            hasResult: false,
            isRunning: false
        ))
    }

    func testDuplicateEventForCurrentlyDisplayedFileIsIgnored() {
        let signature = PanelFileSelection.signature(for: [file])

        XCTAssertTrue(PanelFileSelection.shouldIgnore(
            files: [file],
            currentFiles: [file],
            lastSignature: signature,
            hasResult: false,
            isRunning: false
        ))
    }

    func testSelectionIsAcceptedWhenReplacingResult() {
        let signature = PanelFileSelection.signature(for: [file])

        XCTAssertFalse(PanelFileSelection.shouldIgnore(
            files: [file],
            currentFiles: [file],
            lastSignature: signature,
            hasResult: true,
            isRunning: false
        ))
    }
}
