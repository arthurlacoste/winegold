import XCTest
@testable import WinegoldCore

final class ScriptingGuideTests: XCTestCase {
    func testLoadsRepositoryDocumentation() {
        let text = ScriptingGuide.text

        XCTAssertTrue(text.contains("# Writing Winegold scripts"))
        XCTAssertTrue(text.contains("{input}"))
        XCTAssertTrue(text.contains("{basename}"))
    }

    func testDocumentationDoesNotExposeLegacyPlaceholders() {
        let text = ScriptingGuide.text

        XCTAssertFalse(text.contains("{{"))
        XCTAssertFalse(text.contains("}}"))
    }
}
