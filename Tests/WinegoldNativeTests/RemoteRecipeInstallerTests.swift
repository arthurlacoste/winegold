import XCTest
@testable import WinegoldCore

private struct StubRecipeFetcher: RemoteRecipeFetching {
    let responses: [String: RemoteRecipeResponse]
    func fetch(_ url: URL) async throws -> RemoteRecipeResponse {
        let response = responses[url.absoluteString] ?? RemoteRecipeResponse(data: Data(), statusCode: 404, finalURL: url)
        if response.finalURL.host == "invalid.local" {
            return RemoteRecipeResponse(data: response.data, statusCode: response.statusCode, finalURL: url)
        }
        return response
    }
}

final class RemoteRecipeInstallerTests: XCTestCase {
    private var temp: URL!
    private var db: Database!
    private let recipeURL = URL(string: "https://recipes.example/images/resize/resize.wg.yml")!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
        db = nil
    }

    func testInstallsDeclaredFilesAndStoresProvenance() async throws {
        let installer = makeInstaller(recipe: recipe(version: "1.0.0"), helper: Data("print('ok')".utf8), readmeStatus: 404)
        let destination = try await installer.install(url: recipeURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("resize.py").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.md").path))
        let provenance = try RecipeProvenanceStore(db: db).load(recipeID: "winegold.resize-image")
        XCTAssertEqual(provenance?.installedVersion, "1.0.0")
        XCTAssertNotNil(provenance?.fileHashes["resize.py"])
    }

    func testMissingDeclaredFileLeavesNoPartialInstallation() async throws {
        let installer = makeInstaller(recipe: recipe(version: "1.0.0"), helper: nil)
        do {
            _ = try await installer.install(url: recipeURL)
            XCTFail("Expected missing support file")
        } catch {
            XCTAssertEqual(error as? RemoteRecipeError, .missingSupportFile("resize.py"))
        }
        let root = temp.appendingPathComponent("recipes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("winegold-resize-image").path))
    }

    func testRejectsTraversalBeforeDownloadingHelper() async throws {
        let unsafe = recipe(version: "1.0.0").replacingOccurrences(of: "resize.py", with: "../resize.py")
        let installer = makeInstaller(recipe: unsafe, helper: Data())
        do {
            _ = try await installer.inspect(url: recipeURL)
            XCTFail("Expected traversal rejection")
        } catch {
            XCTAssertEqual(error as? RemoteRecipeError, .unsafeSupportPath("../resize.py"))
        }
    }

    func testRejectsNonHTTPSURL() async throws {
        let installer = makeInstaller(recipe: recipe(version: "1.0.0"), helper: Data())
        do {
            _ = try await installer.inspect(url: URL(string: "http://recipes.example/test.wg.yml")!)
            XCTFail("Expected HTTPS rejection")
        } catch {
            XCTAssertEqual(error as? RemoteRecipeError, .httpsRequired)
        }
    }

    func testInspectionReportsMissingCommand() async throws {
        let text = recipe(version: "1.0.0").replacingOccurrences(of: "python3", with: "winegold-command-that-does-not-exist")
        let installer = makeInstaller(recipe: text, helper: Data())
        let inspection = try await installer.inspect(url: recipeURL)
        XCTAssertEqual(inspection.missingCommands, ["winegold-command-that-does-not-exist"])
    }

    func testModifiedRecipeRequiresExplicitConflictChoice() async throws {
        let installer = makeInstaller(recipe: recipe(version: "1.0.0"), helper: Data("v1".utf8))
        let destination = try await installer.install(url: recipeURL)
        try Data("local edit".utf8).write(to: destination.appendingPathComponent("resize.py"))

        let result = try await installer.update(recipeID: "winegold.resize-image")
        XCTAssertFalse(result.updated)
        XCTAssertTrue(result.conflict)
        XCTAssertTrue(result.diff?.contains("--- local/resize.py") == true)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("resize.py")), "local edit")
    }

    func testUpdatePreservesEnabledState() async throws {
        let installerV1 = makeInstaller(recipe: recipe(version: "1.0.0", enabled: false), helper: Data("v1".utf8))
        let destination = try await installerV1.install(url: recipeURL)
        let installerV2 = makeInstaller(recipe: recipe(version: "2.0.0", enabled: true), helper: Data("v2".utf8))

        let result = try await installerV2.update(recipeID: "winegold.resize-image", choice: .replace)
        XCTAssertTrue(result.updated)
        let installedRecipe = destination.appendingPathComponent("resize.wg.yml")
        XCTAssertFalse(try RecipeParser().parse(url: installedRecipe).document.enabled)
        XCTAssertEqual(try RecipeProvenanceStore(db: db).load(recipeID: "winegold.resize-image")?.installedVersion, "2.0.0")
    }


    func testRejectsCrossOriginRedirect() async throws {
        let redirected = RemoteRecipeResponse(data: Data(recipe(version: "1.0.0").utf8), statusCode: 200, finalURL: URL(string: "https://evil.example/resize.wg.yml")!)
        let installer = RemoteRecipeInstaller(root: temp.appendingPathComponent("recipes"), db: db, fetcher: StubRecipeFetcher(responses: [recipeURL.absoluteString: redirected]))
        do {
            _ = try await installer.inspect(url: recipeURL)
            XCTFail("Expected cross-origin rejection")
        } catch {
            XCTAssertEqual(error as? RemoteRecipeError, .crossOrigin("resize.wg.yml"))
        }
    }

    func testReadmeFailureDoesNotBlockInstall() async throws {
        let installer = makeInstaller(recipe: recipe(version: "1.0.0"), helper: Data("ok".utf8), readmeStatus: 500)
        let destination = try await installer.install(url: recipeURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("resize.py").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.md").path))
    }

    func testUpdateCheckStoresLatestVersion() async throws {
        let v1 = makeInstaller(recipe: recipe(version: "1.0.0"), helper: Data("v1".utf8))
        _ = try await v1.install(url: recipeURL)
        let v2 = makeInstaller(recipe: recipe(version: "2.0.0"), helper: Data("v2".utf8))
        let status = try await v2.checkForUpdate(recipeID: "winegold.resize-image")
        XCTAssertEqual(status.state, .updateAvailable)
        XCTAssertEqual(status.latestVersion, "2.0.0")
        let provenance = try RecipeProvenanceStore(db: db).load(recipeID: "winegold.resize-image")
        XCTAssertNotNil(provenance?.lastUpdateCheck)
        XCTAssertEqual(provenance?.latestKnownVersion, "2.0.0")
    }

    func testDuplicateCurrentRewritesLocalIDAndPreservesLinkedID() async throws {
        let v1 = makeInstaller(recipe: recipe(version: "1.0.0"), helper: Data("v1".utf8))
        let destination = try await v1.install(url: recipeURL)
        try Data("local edit".utf8).write(to: destination.appendingPathComponent("resize.py"))
        let v2 = makeInstaller(recipe: recipe(version: "2.0.0"), helper: Data("v2".utf8))
        _ = try await v2.update(recipeID: "winegold.resize-image", choice: .duplicateCurrent)
        let duplicate = temp.appendingPathComponent("recipes/winegold-resize-image-local/resize.wg.yml")
        let duplicateDocument = try RecipeParser().parse(url: duplicate).document
        XCTAssertTrue(duplicateDocument.id?.hasPrefix("local.") == true)
        XCTAssertNil(duplicateDocument.version)
        XCTAssertEqual(try RecipeParser().parse(url: destination.appendingPathComponent("resize.wg.yml")).document.id, "winegold.resize-image")
    }

    func testUpdatePreservesVariableConfigurationByStableID() async throws {
        let variableStore = RecipeVariableStore(db: db)
        variableStore.writeOverride(externalID: "winegold.resize-image", variableName: "QUALITY", value: "90")
        let v1 = makeInstaller(recipe: recipe(version: "1.0.0"), helper: Data("v1".utf8))
        _ = try await v1.install(url: recipeURL)
        let v2 = makeInstaller(recipe: recipe(version: "2.0.0"), helper: Data("v2".utf8))
        _ = try await v2.update(recipeID: "winegold.resize-image", choice: .replace)
        XCTAssertEqual(variableStore.readOverride(externalID: "winegold.resize-image", variableName: "QUALITY"), "90")
    }

    func testParsesCatalogueMetadata() throws {
        let text = recipe(version: "1.0.0") + "\nauthor: Arthur\ncategory: images\nhomepage: https://example.com/resize\n"
        let document = try RecipeParser().parse(text: text)
        XCTAssertEqual(document.author, "Arthur")
        XCTAssertEqual(document.category, "images")
        XCTAssertEqual(document.homepage, "https://example.com/resize")
    }

    func testSimpleDiffContainsChangedLines() {
        let diff = RemoteRecipeInstaller.simpleDiff(path: "tool.py", old: "one\ntwo", new: "one\nthree")
        XCTAssertTrue(diff.contains("-two"))
        XCTAssertTrue(diff.contains("+three"))
    }

    private func makeInstaller(recipe: String, helper: Data?, readmeStatus: Int = 404) -> RemoteRecipeInstaller {
        var responses = [
            recipeURL.absoluteString: RemoteRecipeResponse(data: Data(recipe.utf8), statusCode: 200),
            "https://recipes.example/images/resize/README.md": RemoteRecipeResponse(data: Data(), statusCode: readmeStatus)
        ]
        if let helper {
            responses["https://recipes.example/images/resize/resize.py"] = RemoteRecipeResponse(data: helper, statusCode: 200)
        }
        return RemoteRecipeInstaller(root: temp.appendingPathComponent("recipes"), db: db, fetcher: StubRecipeFetcher(responses: responses))
    }

    private func recipe(version: String, enabled: Bool = true) -> String {
        """
        id: winegold.resize-image
        name: Resize image
        description: Resize an image.
        version: \(version)
        enabled: \(enabled)
        trigger: extension in {"jpg" "png"}
        files:
          - resize.py
        requires:
          commands:
            - python3
        cmd:
          exec: 'python3 resize.py "{input}"'
        """
    }
}
