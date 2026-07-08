import XCTest
@testable import WinegoldCore

final class ActionMatcherTests: XCTestCase {
    private let matcher = ActionMatcher()

    private func makeAction(extensions: [String] = ["*"], enabled: Bool = true) -> Action {
        Action(
            name: "Test",
            enabled: enabled,
            acceptedExtensions: extensions,
            executablePath: "/bin/echo"
        )
    }

    func testJpgAccepted() {
        let action = makeAction(extensions: ["jpg"])
        let files = [URL(fileURLWithPath: "/tmp/photo.jpg")]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertEqual(result.count, 1)
    }

    func testJpgUpperCase() {
        let action = makeAction(extensions: ["jpg"])
        let files = [URL(fileURLWithPath: "/tmp/photo.JPG")]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertEqual(result.count, 1)
    }

    func testAcceptedExtensionNormalization() {
        let action = makeAction(extensions: [" JPG ", "PNG"])
        let files = [
            URL(fileURLWithPath: "/tmp/photo.jpg"),
            URL(fileURLWithPath: "/tmp/image.PNG")
        ]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertEqual(result.count, 1)
    }

    func testPdfRejected() {
        let action = makeAction(extensions: ["jpg"])
        let files = [URL(fileURLWithPath: "/tmp/doc.pdf")]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertTrue(result.isEmpty)
    }

    func testDisabledActionIgnored() {
        let action = makeAction(extensions: ["jpg"], enabled: false)
        let files = [URL(fileURLWithPath: "/tmp/photo.jpg")]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertTrue(result.isEmpty)
    }

    func testMultiFilesAllAccepted() {
        let action = makeAction(extensions: ["jpg", "png"])
        let files = [
            URL(fileURLWithPath: "/tmp/photo.jpg"),
            URL(fileURLWithPath: "/tmp/img.png")
        ]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertEqual(result.count, 1)
    }

    func testMultiFilesOneRejected() {
        let action = makeAction(extensions: ["jpg"])
        let files = [
            URL(fileURLWithPath: "/tmp/photo.jpg"),
            URL(fileURLWithPath: "/tmp/doc.pdf")
        ]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertTrue(result.isEmpty)
    }

    func testWildcardAccepted() {
        let action = makeAction(extensions: ["*"])
        let files = [
            URL(fileURLWithPath: "/tmp/file.xyz"),
            URL(fileURLWithPath: "/tmp/file.pdf")
        ]
        let result = matcher.matchingActions(for: files, actions: [action])
        XCTAssertEqual(result.count, 1)
    }

    func testEmptyFilesReturnsEmpty() {
        let action = makeAction(extensions: ["*"])
        let result = matcher.matchingActions(for: [], actions: [action])
        XCTAssertTrue(result.isEmpty)
    }
}
