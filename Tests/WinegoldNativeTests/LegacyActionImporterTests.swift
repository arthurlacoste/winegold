import XCTest
import WinegoldCore

final class LegacyActionImporterTests: XCTestCase {
    func testImportsLegacyAddYAML() throws {
        let yaml = """
        name: Bords blanc
        trigger:
          fileExtension:
           - jpg
           - png
           - webp
        cmd:
          exec: 'cd {{dir}} && mkdir -p bords && python3 /Users/art/scripts/bords-blancs.py "{{namebase}}{{ext}}" "bords/{{namebase}}{{ext}}"'
        after:
          eval: require('electron').shell.openExternal(`Tout va bien frérot !`);
        autolaunch: true
        """

        let action = try LegacyActionImporter().importLegacyYAML(yaml, sourceName: "bords-blancs2.add.yml")
        XCTAssertEqual(action.name, "Bords blanc")
        XCTAssertEqual(action.acceptedExtensions, ["jpg", "png", "webp"])
        XCTAssertEqual(action.executablePath, "/bin/zsh")
        XCTAssertEqual(action.argumentsTemplate.first, "-lc")
        XCTAssertTrue(action.argumentsTemplate[1].contains("{parent}"))
        XCTAssertTrue(action.argumentsTemplate[1].contains("{basename}{dotExtension}"))
    }

    func testImportsUnquotedCommand() throws {
        let yaml = """
        name: Resize image to 1000px
        trigger:
          fileExtension:
           - PNG
           - JPG
           - png
           - jpg
        cmd:
          exec: cd '{{dir}}' && mkdir -p resized && sips -Z 1000 {{file}} --out resized/
        autolaunch: false
        """

        let action = try LegacyActionImporter().importLegacyYAML(yaml, sourceName: "resize-png.yml")
        XCTAssertEqual(action.name, "Resize image to 1000px")
        XCTAssertEqual(action.acceptedExtensions, ["png", "jpg", "png", "jpg"])
        XCTAssertTrue(action.argumentsTemplate[1].contains("cd '{parent}'"))
        XCTAssertTrue(action.argumentsTemplate[1].contains("{input}"))
    }

    func testResolverSupportsDotExtensionAndInside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("hello.txt")
        try "bonjour".write(to: file, atomically: true, encoding: .utf8)

        let resolved = ActionTemplateResolver().resolve(
            argumentsTemplate: ["{basename}{dotExtension}", "{inside}"],
            for: file
        )

        XCTAssertEqual(resolved[0], "hello.txt")
        XCTAssertEqual(resolved[1], "bonjour")
    }
}
