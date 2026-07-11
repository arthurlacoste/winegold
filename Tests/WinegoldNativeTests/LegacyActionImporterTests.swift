import XCTest
import WinegoldCore

final class LegacyActionImporterTests: XCTestCase {
    func testImportsExpressionTrigger() throws {
        let yaml = """
        name: URL notes
        trigger: >
          isURL or (extension in {"md" "txt"} and inside contains "TODO")
        cmd:
          exec: echo "{input}"
        """
        let action = try LegacyActionImporter().importLegacyYAML(yaml)
        XCTAssertEqual(action.triggerExpression, "isURL or extension in {\"md\" \"txt\"} and inside contains \"TODO\"")
        XCTAssertTrue(action.acceptedExtensions.isEmpty)
    }

    func testLegacyTriggerIsNormalizedToExpression() throws {
        let yaml = """
        name: Image
        trigger:
          fileExtension:
            - jpg
            - png
        cmd:
          exec: echo ok
        """
        let action = try LegacyActionImporter().importLegacyYAML(yaml)
        XCTAssertEqual(action.triggerExpression, "extension in {\"jpg\" \"png\"}")
    }

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


    func testImportsBlockScalarCommand() throws {
        let yaml = """
        name: Upload compressed WebP and copy Markdown
        trigger:
          fileExtension:
            - jpg
            - jpeg
            - png
            - webp
        cmd:
          exec: |
            TMP_WEBP="/tmp/{basename}-{timestamp}.webp"
            LOG="{desktop}/uploadfile-full.log"

            sips -Z 1200 "{input}" --out "$TMP_WEBP" >/dev/null
            curl -sSL -F "file=@$TMP_WEBP;type=image/webp;filename={basename}.webp" "https://app.irz.fr/img/api.php?format=markdown"
        """

        let action = try LegacyActionImporter().importLegacyYAML(yaml, sourceName: "upload.add.yml")
        let command = try XCTUnwrap(action.argumentsTemplate.dropFirst().first)

        XCTAssertEqual(action.name, "Upload compressed WebP and copy Markdown")
        XCTAssertEqual(action.acceptedExtensions, ["jpg", "jpeg", "png", "webp"])
        XCTAssertTrue(command.contains("TMP_WEBP=\"/tmp/{basename}-{timestamp}.webp\""))
        XCTAssertTrue(command.contains("LOG=\"{desktop}/uploadfile-full.log\""))
        XCTAssertTrue(command.contains("\nsips -Z 1200 \"{input}\""))
        XCTAssertTrue(command.contains("https://app.irz.fr/img/api.php?format=markdown"))
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
    func testImportsNameAndSuccessMessagePlaceholders() throws {
        let yaml = """
        name: Convert {{name}}
        trigger:
          fileExtension:
            - txt
        cmd:
          exec: 'echo "{{file}}"'
        successMessage: 'Created {{namebase}}.done'
        """
        let action = try LegacyActionImporter().importLegacyYAML(yaml)
        XCTAssertEqual(action.name, "Convert {filename}")
        XCTAssertEqual(action.successMessage, "Created {basename}.done")
    }

    func testEmptySuccessMessageIsIgnored() throws {
        let yaml = """
        name: Test
        trigger:
          fileExtension:
            - txt
        cmd:
          exec: 'echo ok'
        successMessage: '   '
        """
        XCTAssertNil(try LegacyActionImporter().importLegacyYAML(yaml).successMessage)
    }
}
