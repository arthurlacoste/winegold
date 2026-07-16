import XCTest
@testable import WinegoldCore

final class RecipeYAMLEditorTests: XCTestCase {
    func testValidationAcceptsMultiActionAndReportsCmdWarning() {
        let text = """
        id: winegold.node
        name: Node
        trigger: 'kind equals "directory"'
        cmd:
          exec: echo ignored
        actions:
          - id: test
            name: Test
            cmd:
              exec: npm test
        """
        let validation = RecipeYAMLEditor().validate(text)
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.warnings, ["Both cmd and actions are present. actions wins."])
    }

    func testInvalidYAMLDoesNotReplaceExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("demo.wg.yml")
        let original = "name: Demo\ntrigger: 'extension equals \"txt\"'\ncmd:\n  exec: echo ok\n"
        try Data(original.utf8).write(to: url)

        XCTAssertThrowsError(try RecipeYAMLEditor().save("name: Broken\n", to: url, inside: root))
        XCTAssertEqual(try String(contentsOf: url), original)
    }

    func testAtomicSavePreservesPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("demo.wg.yml")
        let original = "name: Demo\ntrigger: 'extension equals \"txt\"'\ncmd:\n  exec: echo old\n"
        try Data(original.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        let updated = original.replacingOccurrences(of: "echo old", with: "echo new")

        try RecipeYAMLEditor().save(updated, to: url, inside: root)

        XCTAssertTrue(try String(contentsOf: url).contains("echo new"))
        let permissions = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o640)
    }
}
