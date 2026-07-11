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

    private func writeRecipe(_ url: URL, id: String = "winegold.test", name: String = "Test") throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "id: '\(id)'\nname: '\(name)'\nenabled: true\ntrigger: 'extension in {\"txt\"}'\ncmd:\n  exec: 'echo {input}'\n"
        try Data(text.utf8).write(to: url)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
