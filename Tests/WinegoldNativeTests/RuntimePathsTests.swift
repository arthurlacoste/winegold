import Foundation
import XCTest
@testable import WinegoldCore

final class RuntimePathsTests: XCTestCase {
    func testApplicationSupportOverrideIsUsed() {
        let result = RuntimePaths.applicationSupportDirectory(
            environment: [RuntimePaths.appSupportEnvironmentKey: "/tmp/winegold-test-support"],
            defaultBase: URL(fileURLWithPath: "/default")
        )
        XCTAssertEqual(result.path, "/tmp/winegold-test-support")
    }

    func testRecipeRootOverrideIsUsed() {
        let result = RuntimePaths.recipeRoot(
            environment: [RuntimePaths.recipeRootEnvironmentKey: "/tmp/winegold-test-recipes"],
            homeDirectory: URL(fileURLWithPath: "/home/test")
        )
        XCTAssertEqual(result.path, "/tmp/winegold-test-recipes")
    }

    func testDefaultPathsRemainUnchanged() {
        XCTAssertEqual(
            RuntimePaths.applicationSupportDirectory(environment: [:], defaultBase: URL(fileURLWithPath: "/support")).path,
            "/support/WinegoldNative"
        )
        XCTAssertEqual(
            RuntimePaths.recipeRoot(environment: [:], homeDirectory: URL(fileURLWithPath: "/home/test")).path,
            "/home/test/.winegold/recipes"
        )
    }
}
