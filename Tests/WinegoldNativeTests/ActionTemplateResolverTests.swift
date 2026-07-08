import XCTest
@testable import WinegoldCore

final class ActionTemplateResolverTests: XCTestCase {
    private let resolver = ActionTemplateResolver()

    func testResolveInput() {
        let url = URL(fileURLWithPath: "/Users/art/Desktop/image.png")
        let result = resolver.resolve(argumentsTemplate: ["{input}"], for: url)
        XCTAssertEqual(result, ["/Users/art/Desktop/image.png"])
    }

    func testResolveBasename() {
        let url = URL(fileURLWithPath: "/Users/art/Desktop/image.png")
        let result = resolver.resolve(argumentsTemplate: ["{basename}"], for: url)
        XCTAssertEqual(result, ["image"])
    }

    func testResolveExtension() {
        let url = URL(fileURLWithPath: "/Users/art/Desktop/image.png")
        let result = resolver.resolve(argumentsTemplate: ["{extension}"], for: url)
        XCTAssertEqual(result, ["png"])
    }

    func testResolveParent() {
        let url = URL(fileURLWithPath: "/Users/art/Desktop/image.png")
        let result = resolver.resolve(argumentsTemplate: ["{parent}"], for: url)
        XCTAssertEqual(result, ["/Users/art/Desktop"])
    }

    func testResolveFilename() {
        let url = URL(fileURLWithPath: "/Users/art/Desktop/image.png")
        let result = resolver.resolve(argumentsTemplate: ["{filename}"], for: url)
        XCTAssertEqual(result, ["image.png"])
    }

    func testFileWithSpaces() {
        let url = URL(fileURLWithPath: "/Users/art/Desktop/my image.png")
        let result = resolver.resolve(argumentsTemplate: ["{input}"], for: url)
        XCTAssertEqual(result, ["/Users/art/Desktop/my image.png"])
    }

    func testOutputPath() {
        let url = URL(fileURLWithPath: "/Users/art/Desktop/image.png")
        let result = resolver.resolve(argumentsTemplate: ["{parent}/{basename}.webp"], for: url)
        XCTAssertEqual(result, ["/Users/art/Desktop/image.webp"])
    }

    func testMultipleArgs() {
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        let result = resolver.resolve(argumentsTemplate: ["{input}", "-o", "{basename}.out"], for: url)
        XCTAssertEqual(result, ["/tmp/file.txt", "-o", "file.out"])
    }

    func testInputPathAlias() {
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        let result = resolver.resolve(argumentsTemplate: ["{inputPath}"], for: url)
        XCTAssertEqual(result, ["/tmp/file.txt"])
    }

    func testTimestampResolves() {
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        let result = resolver.resolve(argumentsTemplate: ["{timestamp}"], for: url)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].count >= 15)
    }

    func testDesktopPlaceholder() {
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        let result = resolver.resolve(argumentsTemplate: ["{desktop}"], for: url)
        XCTAssertTrue(result[0].hasSuffix("/Desktop"))
    }
}
