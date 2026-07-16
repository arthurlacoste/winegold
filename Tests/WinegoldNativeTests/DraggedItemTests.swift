import XCTest
@testable import WinegoldCore

final class DraggedItemTests: XCTestCase {
    func testURLComponentsAndRawInput() {
        let item = DraggedItem(executionURL: URL(fileURLWithPath: "/tmp/payload"), kind: .url, rawURL: "https://example.com/a?q=1#top")
        XCTAssertEqual(item.values["host"], .string("example.com"))
        XCTAssertEqual(item.values["urlPath"], .string("/a"))
        XCTAssertEqual(item.input, "https://example.com/a?q=1#top")
    }

    func testPlainTextIsNotFileContent() {
        let item = DraggedItem(executionURL: URL(fileURLWithPath: "/tmp/payload"), kind: .text, rawText: "hello")
        XCTAssertEqual(item.values["isText"], .bool(true))
        XCTAssertEqual(item.values["text"], .string("hello"))
        XCTAssertNil(item.values["inside"])
    }

    func testDirectoryKind() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(DraggedItem(executionURL: directory).kind, .directory)
    }

    func testBinaryImageDoesNotExposeInside() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let values = DraggedItem(executionURL: url).values

        XCTAssertNil(values["inside"])
    }


    func testInsideIsOnlyLoadedWhenExplicitlyRequested() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let item = DraggedItem(executionURL: url)
        XCTAssertNil(item.values(includeInside: false)["inside"])
        XCTAssertEqual(item.values(includeInside: true)["inside"], .string("hello"))
        XCTAssertEqual(item.values(includeInside: false)["mimeType"], .string("text/plain"))
    }

}
