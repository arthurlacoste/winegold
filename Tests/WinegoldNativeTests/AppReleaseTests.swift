import XCTest
@testable import WinegoldCore

final class AppReleaseTests: XCTestCase {
    func testParsesTaggedReleaseAndMatchingChecksum() throws {
        let data = Data("""
        {
          "tag_name": "v1.2.3",
          "html_url": "https://github.com/arthurlacoste/winegold/releases/tag/v1.2.3",
          "body": "Changes",
          "draft": false,
          "prerelease": false,
          "assets": [
            {"name":"Winegold-1.2.3-macOS.zip","browser_download_url":"https://example.com/app.zip"},
            {"name":"Winegold-1.2.3-macOS.zip.sha256","browser_download_url":"https://example.com/app.zip.sha256"}
          ]
        }
        """.utf8)

        let release = try AppReleaseParser.parseLatestRelease(data: data)
        XCTAssertEqual(release.version, "1.2.3")
        XCTAssertEqual(release.archiveURL.absoluteString, "https://example.com/app.zip")
        XCTAssertEqual(release.notes, "Changes")
    }

    func testRejectsReleaseWithoutChecksum() {
        let data = Data("""
        {"tag_name":"v1.2.3","html_url":"https://example.com","body":"","draft":false,"prerelease":false,"assets":[{"name":"Winegold-1.2.3-macOS.zip","browser_download_url":"https://example.com/app.zip"}]}
        """.utf8)
        XCTAssertThrowsError(try AppReleaseParser.parseLatestRelease(data: data)) { error in
            XCTAssertEqual(error as? AppReleaseError, .missingChecksum)
        }
    }

    func testVersionComparison() {
        XCTAssertTrue(VersionComparator.isNewer("1.2.0", than: "1.1.9"))
        XCTAssertTrue(VersionComparator.isNewer("2.0.0", than: "1.99.99"))
        XCTAssertFalse(VersionComparator.isNewer("1.2.0", than: "1.2.0"))
        XCTAssertFalse(VersionComparator.isNewer("1.1.9", than: "1.2.0"))
        XCTAssertFalse(VersionComparator.isNewer("nonsense", than: "1.2.0"))
    }
}
