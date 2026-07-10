import Foundation
import XCTest
@testable import WinegoldCore

final class ContentAddressedFileStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("winegold-content-store-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testIdenticalContentReturnsSameFileWithoutRewriting() throws {
        let store = ContentAddressedFileStore(directory: directory)
        let first = try store.store(contents: "https://example.com", prefix: "dragged-url", fileExtension: "url")
        let firstAttributes = try FileManager.default.attributesOfItem(atPath: first.path)

        Thread.sleep(forTimeInterval: 0.02)
        let second = try store.store(contents: "https://example.com", prefix: "dragged-url", fileExtension: "url")
        let secondAttributes = try FileManager.default.attributesOfItem(atPath: second.path)

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstAttributes[.modificationDate] as? Date, secondAttributes[.modificationDate] as? Date)
        XCTAssertEqual(try String(contentsOf: second), "https://example.com")
    }

    func testDifferentContentCreatesDistinctFiles() throws {
        let store = ContentAddressedFileStore(directory: directory)
        let first = try store.store(contents: "https://example.com/a", prefix: "dragged-url", fileExtension: "url")
        let second = try store.store(contents: "https://example.com/b", prefix: "dragged-url", fileExtension: "url")

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testHashIsIncludedInFilename() throws {
        let store = ContentAddressedFileStore(directory: directory)
        let contents = "<p>Hello</p>"
        let url = try store.store(contents: contents, prefix: "dragged-html", fileExtension: "html")
        let hash = ContentAddressedFileStore.contentHash(for: Data(contents.utf8))

        XCTAssertEqual(url.lastPathComponent, "dragged-html-\(hash).html")
    }
}
