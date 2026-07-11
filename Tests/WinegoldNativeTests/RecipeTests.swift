import XCTest
@testable import WinegoldCore

final class RecipeTests: XCTestCase {
    func testParserRoundTripAndWorkingDirectory() throws {
        let root = temporaryDirectory()
        let url = root.appendingPathComponent("resize/resize.wg.yml")
        let store = RecipeFileStore(root: root)
        let record = try store.write(RecipeDocument(id: "winegold.resize", name: "Resize", description: "Resize image", enabled: true, trigger: "extension in {\"jpg\" \"png\"}", command: "python3 resize.py '{input}'"), to: url)

        XCTAssertEqual(record.document.name, "Resize")
        XCTAssertEqual(record.action.acceptedExtensions, ["jpg", "png"])
        XCTAssertEqual(record.action.workingDirectoryTemplate, url.deletingLastPathComponent().path)
        XCTAssertTrue(try String(contentsOf: url).contains("id: 'winegold.resize'"))
    }

    func testScannerFindsNestedRecipesAndSkipsHiddenDependenciesAndSymlinks() throws {
        let root = temporaryDirectory()
        try writeRecipe(root.appendingPathComponent("root.wg.yml"))
        try writeRecipe(root.appendingPathComponent("personal/nested.wg.yml"))
        try writeRecipe(root.appendingPathComponent(".hidden/nope.wg.yml"))
        try writeRecipe(root.appendingPathComponent("node_modules/nope.wg.yml"))
        let external = temporaryDirectory().appendingPathComponent("linked.wg.yml")
        try writeRecipe(external)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.wg.yml"), withDestinationURL: external)

        let names = try RecipeScanner().scan(root: root).map { $0.url.lastPathComponent }
        XCTAssertEqual(names, ["nested.wg.yml", "root.wg.yml"])
    }

    func testCoordinatorInvalidatesAndRestoresRecipeWithoutLosingOrder() throws {
        let root = temporaryDirectory()
        let db = try Database(path: root.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let url = root.appendingPathComponent("recipes/demo.wg.yml")
        try writeRecipe(url, id: "winegold.demo")
        let coordinator = RecipeCoordinator(root: root.appendingPathComponent("recipes"), db: db)
        try coordinator.reconcile()
        let store = ActionStore(db: db)
        var action = try XCTUnwrap(store.listActions().first)
        action.displayOrder = 42
        try store.updateAction(action)

        try Data("name: Broken\n".utf8).write(to: url)
        try coordinator.reconcile()
        XCTAssertTrue(try store.listActions().isEmpty)
        XCTAssertEqual(try RecipeIndexStore(db: db).entries().first?.status, "invalid")

        try writeRecipe(url, id: "winegold.demo", name: "Restored")
        try coordinator.reconcile()
        let restored = try XCTUnwrap(store.listActions().first)
        XCTAssertEqual(restored.name, "Restored")
        XCTAssertEqual(restored.displayOrder, 42)
    }

    func testRepairInvalidRecipeAddsMissingTriggerAndPreservesOtherFields() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        let url = root.appendingPathComponent("convert/convert.wg.yml")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let invalid = """
        # Keep this comment
        id: 'winegold.convert'
        name: 'Convert webp to jpg'
        enabled: true
        variables:
          QUALITY:
            default: '90'
        customField: keep-me
        cmd:
          exec: 'echo old'
        """ + "\n"
        try Data(invalid.utf8).write(to: url)

        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let coordinator = RecipeCoordinator(root: root, db: db)
        try coordinator.reconcile()
        XCTAssertEqual(try coordinator.entries().first?.status, "invalid")

        let draft = try coordinator.repairDraft(at: url)
        XCTAssertEqual(draft.name, "Convert webp to jpg")
        XCTAssertEqual(draft.trigger, "extension in {\"*\"}")
        XCTAssertEqual(draft.command, "echo old")

        let action = Action(
            name: draft.name,
            acceptedExtensions: ["png"],
            triggerExpression: "extension in {\"png\"}",
            executablePath: "/bin/zsh",
            argumentsTemplate: ["-lc", "echo repaired"]
        )
        try coordinator.repairInvalidRecipe(at: url, action: action)

        let repaired = try RecipeParser().parse(url: url)
        XCTAssertEqual(repaired.document.trigger, "extension in {\"png\"}")
        XCTAssertEqual(repaired.document.command, "echo repaired")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("# Keep this comment"))
        XCTAssertTrue(text.contains("customField: keep-me"))
        XCTAssertTrue(text.contains("variables:"))
        XCTAssertEqual(try coordinator.entries().first?.status, "valid")
        XCTAssertEqual(try ActionStore(db: db).listActions().first?.name, "Convert webp to jpg")
    }

    func testLegacyMigrationIsIdempotentAndPreservesActionID() throws {
        let temp = temporaryDirectory()
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let original = Action(name: "Old Action", acceptedExtensions: ["txt"], executablePath: "/bin/zsh", argumentsTemplate: ["-lc", "echo '{input}'"])
        try ActionStore(db: db).createAction(original)
        let root = temp.appendingPathComponent("recipes")
        let migrator = LegacyRecipeMigrator(db: db, root: root)
        try migrator.migrateIfNeeded()
        try migrator.migrateIfNeeded()
        XCTAssertEqual(try RecipeScanner().scan(root: root).count, 1)
        try RecipeCoordinator(root: root, db: db).reconcile()
        XCTAssertEqual(try ActionStore(db: db).listActions().first?.id, original.id)
    }

    func testStandaloneInstallerCopiesReferencedHelper() throws {
        let sourceRoot = temporaryDirectory()
        let recipe = sourceRoot.appendingPathComponent("resize.wg.yml")
        try writeRecipe(recipe, id: "winegold.resize", name: "Resize", command: "python3 resize.py {input}")
        try Data("print('ok')".utf8).write(to: sourceRoot.appendingPathComponent("resize.py"))
        let target = temporaryDirectory().appendingPathComponent("recipes")

        let summary = try RecipeInstaller(root: target).install(recipe)

        XCTAssertEqual(summary.recipeNames, ["Resize"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.destination.appendingPathComponent("resize.wg.yml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.destination.appendingPathComponent("resize.py").path))
    }

    func testStandaloneInstallerWarnsAboutMissingHelper() throws {
        let sourceRoot = temporaryDirectory()
        let recipe = sourceRoot.appendingPathComponent("resize.wg.yml")
        try writeRecipe(recipe, command: "python3 missing.py {input}")

        let summary = try RecipeInstaller(root: temporaryDirectory()).inspect(recipe)

        XCTAssertEqual(summary.warnings, ["Missing support file: missing.py", "Undeclared helper reference: missing.py"])
    }

    func testFolderInstallerCopiesBundleAndSkipsSymlinksAndDependencies() throws {
        let source = temporaryDirectory().appendingPathComponent("bundle")
        try writeRecipe(source.appendingPathComponent("main.wg.yml"), id: "winegold.bundle", name: "Bundle")
        try Data("helper".utf8).write(to: source.appendingPathComponent("helper.py"))
        try FileManager.default.createDirectory(at: source.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try Data("skip".utf8).write(to: source.appendingPathComponent("node_modules/skip.js"))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("linked.py"), withDestinationURL: source.appendingPathComponent("helper.py"))
        let target = temporaryDirectory().appendingPathComponent("recipes")

        let summary = try RecipeInstaller(root: target).install(source)

        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.destination.appendingPathComponent("main.wg.yml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.destination.appendingPathComponent("helper.py").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: summary.destination.appendingPathComponent("node_modules").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: summary.destination.appendingPathComponent("linked.py").path))
    }

    func testLegacyInstallerConvertsAddYAMLToWGRecipe() throws {
        let source = temporaryDirectory().appendingPathComponent("copy.add.yml")
        let yaml = "name: Copy\ntrigger:\n  fileExtension:\n    - txt\ncmd:\n  exec: 'echo {input}'\n"
        try Data(yaml.utf8).write(to: source)
        let target = temporaryDirectory().appendingPathComponent("recipes")

        let summary = try RecipeInstaller(root: target).install(source)
        let installed = try RecipeScanner().scan(root: target)

        XCTAssertEqual(installed.count, 1)
        XCTAssertTrue(installed[0].url.lastPathComponent.hasSuffix(".wg.yml"))
        XCTAssertEqual(summary.recipeNames, ["Copy"])
    }

    func testParserReadsDeclaredFilesAndRequirements() throws {
        let text = """
        name: Test
        trigger: 'extension equals "txt"'
        cmd:
          exec: 'python3 scripts/run.py {input}'
        files:
          - scripts/run.py
          - config/default.json
        requirements:
          - python3
          - pillow>=10
        """

        let document = try RecipeParser().parse(text: text)

        XCTAssertEqual(document.supportFiles, ["scripts/run.py", "config/default.json"])
        XCTAssertEqual(document.requirements, ["python3", "pillow>=10"])
    }

    func testSettingsStyleSavePreservesCommentsUnknownFieldsMetadataAndPermissions() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        let url = root.appendingPathComponent("tools/demo.wg.yml")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = """
        # Keep this comment
        id: winegold.demo
        name: Demo
        description: Original
        version: 2.4.0
        enabled: true
        customField:
          nested: keep-me
        trigger: 'extension equals "txt"'
        cmd:
          exec: 'echo {input}'
        files:
          - scripts/helper.py
        requirements:
          - python3
        """ + "\n"
        try Data(original.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let coordinator = RecipeCoordinator(root: root, db: db)
        try coordinator.reconcile()
        var action = try XCTUnwrap(ActionStore(db: db).listActions().first)
        action.name = "Edited"
        action.description = "Changed"
        action.argumentsTemplate = ["-lc", "printf '%s' '{input}'"]

        try coordinator.save(action: action)

        let updated = try String(contentsOf: url)
        XCTAssertTrue(updated.contains("# Keep this comment"))
        XCTAssertTrue(updated.contains("customField:\n  nested: keep-me"))
        XCTAssertTrue(updated.contains("version: '2.4.0'"))
        XCTAssertTrue(updated.contains("  - 'scripts/helper.py'"))
        XCTAssertTrue(updated.contains("  - 'python3'"))
        XCTAssertTrue(updated.contains("name: 'Edited'"))
        let permissions = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o640)
    }

    func testDeclaredNestedSupportFileIsCopiedWithoutUndeclaredWarning() throws {
        let sourceRoot = temporaryDirectory()
        let recipe = sourceRoot.appendingPathComponent("tool.wg.yml")
        try FileManager.default.createDirectory(at: sourceRoot.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("print('ok')".utf8).write(to: sourceRoot.appendingPathComponent("scripts/run.py"))
        let text = """
        id: winegold.tool
        name: Tool
        enabled: true
        trigger: 'extension equals "txt"'
        cmd:
          exec: 'python3 scripts/run.py {input}'
        files:
          - scripts/run.py
        """ + "\n"
        try Data(text.utf8).write(to: recipe)

        let summary = try RecipeInstaller(root: temporaryDirectory()).install(recipe)

        XCTAssertTrue(summary.warnings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.destination.appendingPathComponent("scripts/run.py").path))
    }

    func testUnsafeDeclaredSupportPathIsRejected() throws {
        let sourceRoot = temporaryDirectory()
        let recipe = sourceRoot.appendingPathComponent("unsafe.wg.yml")
        let text = """
        name: Unsafe
        trigger: 'extension equals "txt"'
        cmd:
          exec: 'echo {input}'
        files:
          - ../secret.txt
        """ + "\n"
        try Data(text.utf8).write(to: recipe)

        XCTAssertThrowsError(try RecipeInstaller(root: temporaryDirectory()).inspect(recipe))
    }

    func testHashChangeIsDetectedWhenMetadataAndSizeMatch() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        let url = root.appendingPathComponent("same.wg.yml")
        try writeRecipe(url, id: "winegold.same", name: "Test")
        let originalDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let coordinator = RecipeCoordinator(root: root, db: db)
        try coordinator.reconcile()

        try writeRecipe(url, id: "winegold.same", name: "Best")
        if let originalDate { try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: url.path) }
        try coordinator.reconcile()

        XCTAssertEqual(try ActionStore(db: db).listActions().first?.name, "Best")
    }

    func testMissingDerivedActionIsRebuiltFromUnchangedRecipe() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        let url = root.appendingPathComponent("rebuild.wg.yml")
        try writeRecipe(url, id: "winegold.rebuild", name: "Rebuild")
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let coordinator = RecipeCoordinator(root: root, db: db)
        try coordinator.reconcile()
        try db.execute("DELETE FROM actions")

        try coordinator.reconcile()

        XCTAssertEqual(try ActionStore(db: db).listActions().map(\.name), ["Rebuild"])
    }

    func testGeneratedIDWriteStabilizesWithoutRewriteLoop() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        let url = root.appendingPathComponent("local.wg.yml")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let text = "name: Local\ntrigger: 'extension equals \"txt\"'\ncmd:\n  exec: 'echo {input}'\n"
        try Data(text.utf8).write(to: url)
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let coordinator = RecipeCoordinator(root: root, db: db)

        try coordinator.reconcile()
        let firstData = try Data(contentsOf: url)
        let firstDate = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        Thread.sleep(forTimeInterval: 0.05)
        try coordinator.reconcile()

        XCTAssertEqual(try Data(contentsOf: url), firstData)
        XCTAssertEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, firstDate)
    }

    func testWatcherObservesExistingNestedDirectory() throws {
        let root = temporaryDirectory().appendingPathComponent("recipes")
        let nested = root.appendingPathComponent("deep/category")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let callback = expectation(description: "nested watcher callback")
        callback.assertForOverFulfill = false
        let watcher = RecipeWatcher(root: root) { callback.fulfill() }
        try watcher.start()
        defer { watcher.stop() }

        try Data("change".utf8).write(to: nested.appendingPathComponent("touch.txt"))

        wait(for: [callback], timeout: 2.0)
    }

    func testNestedFolderBecomesDerivedCategory() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        try writeRecipe(root.appendingPathComponent("personal/images/resize.wg.yml"), id: "winegold.category", name: "Resize")
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()

        try RecipeCoordinator(root: root, db: db).reconcile()

        XCTAssertEqual(try ActionStore(db: db).listActions().first?.category, "personal/images")
    }

    func testDuplicateNamesRemainDistinctByRecipeID() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        try writeRecipe(root.appendingPathComponent("one.wg.yml"), id: "winegold.one", name: "Duplicate")
        try writeRecipe(root.appendingPathComponent("two.wg.yml"), id: "winegold.two", name: "Duplicate")
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()

        try RecipeCoordinator(root: root, db: db).reconcile()

        let actions = try ActionStore(db: db).listActions()
        XCTAssertEqual(actions.count, 2)
        XCTAssertNotEqual(actions[0].id, actions[1].id)
    }

    func testExternalDeletionAndRestorationPreserveLocalOrder() throws {
        let temp = temporaryDirectory()
        let root = temp.appendingPathComponent("recipes")
        let url = root.appendingPathComponent("restore.wg.yml")
        try writeRecipe(url, id: "winegold.restore", name: "Restore")
        let original = try Data(contentsOf: url)
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let coordinator = RecipeCoordinator(root: root, db: db)
        try coordinator.reconcile()
        var action = try XCTUnwrap(ActionStore(db: db).listActions().first)
        action.displayOrder = 73
        try ActionStore(db: db).updateAction(action)

        try FileManager.default.removeItem(at: url)
        try coordinator.reconcile()
        XCTAssertTrue(try ActionStore(db: db).listActions().isEmpty)

        try original.write(to: url)
        try coordinator.reconcile()
        XCTAssertEqual(try ActionStore(db: db).listActions().first?.displayOrder, 73)
    }

    func testCoordinatorRecordsInstallationProvenance() throws {
        let temp = temporaryDirectory()
        let source = temp.appendingPathComponent("source.wg.yml")
        try writeRecipe(source, id: "winegold.provenance", name: "Provenance")
        let root = temp.appendingPathComponent("recipes")
        let db = try Database(path: temp.appendingPathComponent("test.db").path)
        try Migrations(db: db).run()
        let coordinator = RecipeCoordinator(root: root, db: db)

        _ = try coordinator.install(source)

        let entry = try XCTUnwrap(coordinator.entries().first)
        XCTAssertEqual(entry.installedFrom, source.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertNotNil(entry.installedAt)
    }

    func testWatcherObservesAtomicReplacementInNestedDirectory() throws {
        let root = temporaryDirectory().appendingPathComponent("recipes")
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let destination = nested.appendingPathComponent("recipe.wg.yml")
        try writeRecipe(destination)
        let callback = expectation(description: "atomic replacement callback")
        callback.assertForOverFulfill = false
        let watcher = RecipeWatcher(root: root) { callback.fulfill() }
        try watcher.start()
        defer { watcher.stop() }

        let replacement = nested.appendingPathComponent("replacement.tmp")
        try Data("replacement".utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: replacement)

        wait(for: [callback], timeout: 2.0)
    }

    func testStandaloneInstallerDetectsNestedUndeclaredHelper() throws {
        let sourceRoot = temporaryDirectory()
        let recipe = sourceRoot.appendingPathComponent("nested-helper.wg.yml")
        try FileManager.default.createDirectory(at: sourceRoot.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("print('ok')".utf8).write(to: sourceRoot.appendingPathComponent("scripts/run.py"))
        try writeRecipe(recipe, command: "python3 scripts/run.py {input}")

        let summary = try RecipeInstaller(root: temporaryDirectory()).inspect(recipe)

        XCTAssertTrue(summary.copiedFiles.contains("scripts/run.py"))
        XCTAssertEqual(summary.warnings, ["Undeclared helper reference: scripts/run.py"])
    }

    private func writeRecipe(_ url: URL, id: String = "winegold.test", name: String = "Test", command: String = "echo {input}") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "id: '\(id)'\nname: '\(name)'\nenabled: true\ntrigger: 'extension in {\"txt\"}'\ncmd:\n  exec: '\(command)'\n"
        try Data(text.utf8).write(to: url)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
