import XCTest
@testable import WinegoldCore

final class ActionStoreTests: XCTestCase {
    private var db: Database!
    private var store: ActionStore!

    override func setUp() {
        super.setUp()
        db = try! Database(path: ":memory:")
        try! Migrations(db: db).run()
        store = ActionStore(db: db)
    }

    func testCreateAction() throws {
        let action = Action(name: "Test", executablePath: "/bin/echo")
        try store.createAction(action)
        let count = try store.count()
        XCTAssertEqual(count, 1)
    }

    func testListActions() throws {
        try store.createAction(Action(name: "A", executablePath: "/bin/echo"))
        try store.createAction(Action(name: "B", executablePath: "/bin/echo"))
        let actions = try store.listActions()
        XCTAssertEqual(actions.count, 2)
    }

    func testUpdateAction() throws {
        var action = Action(name: "Original", executablePath: "/bin/echo")
        try store.createAction(action)

        action.name = "Updated"
        try store.updateAction(action)

        let actions = try store.listActions()
        XCTAssertEqual(actions.first?.name, "Updated")
    }

    func testDeleteAction() throws {
        let action = Action(name: "Delete me", executablePath: "/bin/echo")
        try store.createAction(action)
        try store.deleteAction(id: action.id)
        let count = try store.count()
        XCTAssertEqual(count, 0)
    }

    func testEnabledFilter() throws {
        try store.createAction(Action(name: "Enabled", enabled: true, executablePath: "/bin/echo"))
        try store.createAction(Action(name: "Disabled", enabled: false, executablePath: "/bin/echo"))

        let all = try store.listActions()
        let enabled = try store.listEnabledActions()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled.first?.name, "Enabled")
    }

    func testRoundTripPreservesFields() throws {
        let original = Action(
            name: "Convert",
            description: "Test action",
            iconName: "gearshape",
            enabled: true,
            acceptedExtensions: ["jpg", "png"],
            acceptedUTIs: ["public.image"],
            executablePath: "/opt/homebrew/bin/magick",
            argumentsTemplate: ["{input}", "-quality", "85", "{basename}.webp"],
            workingDirectoryTemplate: "{parent}",
            outputPathTemplate: "{parent}/{basename}.webp",
            requiresConfirmation: false,
            timeoutSeconds: 60,
            isFavorite: true,
            displayOrder: 7
        )
        try store.createAction(original)

        let loaded = try store.listActions().first!
        XCTAssertEqual(loaded.name, original.name)
        XCTAssertEqual(loaded.description, original.description)
        XCTAssertEqual(loaded.iconName, original.iconName)
        XCTAssertEqual(loaded.acceptedExtensions, original.acceptedExtensions)
        XCTAssertEqual(loaded.acceptedUTIs, original.acceptedUTIs)
        XCTAssertEqual(loaded.executablePath, original.executablePath)
        XCTAssertEqual(loaded.argumentsTemplate, original.argumentsTemplate)
        XCTAssertEqual(loaded.workingDirectoryTemplate, original.workingDirectoryTemplate)
        XCTAssertEqual(loaded.outputPathTemplate, original.outputPathTemplate)
        XCTAssertEqual(loaded.timeoutSeconds, original.timeoutSeconds)
        XCTAssertEqual(loaded.isFavorite, original.isFavorite)
        XCTAssertEqual(loaded.displayOrder, original.displayOrder)
    }


    func testRoundTripPreservesMultilineShellCommand() throws {
        let command = """
        TMP_WEBP="/tmp/{basename}-{timestamp}.webp"
        LOG="{desktop}/uploadfile-full.log"
        echo "{input}"
        """
        let original = Action(
            name: "Upload",
            executablePath: "/bin/zsh",
            argumentsTemplate: ["-lc", command]
        )

        try store.createAction(original)

        let loaded = try XCTUnwrap(store.listActions().first)
        XCTAssertEqual(loaded.argumentsTemplate, original.argumentsTemplate)
        XCTAssertEqual(loaded.argumentsTemplate[1], command)
    }

    func testDecodesLegacyMultilineZshCommandAsSingleArgument() throws {
        let id = UUID()
        let command = """
        first line
        second line
        third line
        """
        let stmt = try db.prepare("""
            INSERT INTO actions (id, name, description, icon_name, enabled, accepted_extensions,
            accepted_utis, executable_path, arguments_template, working_directory_template,
            output_path_template, requires_confirmation, timeout_seconds, is_favorite, display_order, created_at, updated_at)
            VALUES (?, 'Legacy multiline', '', NULL, 1, 'txt', '', '/bin/zsh', ?, NULL, NULL, 0, 120, 0, 0, '2026-01-01T00:00:00+0000', '2026-01-01T00:00:00+0000')
        """)
        stmt.bindText(id.uuidString, at: 1)
        stmt.bindText("-lc\n" + command, at: 2)
        _ = stmt.step()

        let loaded = try XCTUnwrap(store.listActions().first)
        XCTAssertEqual(loaded.argumentsTemplate, ["-lc", command])
    }

    func testFavoriteActionsSortFirst() throws {
        let normal = Action(name: "A", executablePath: "/bin/echo", displayOrder: 0)
        let favorite = Action(name: "B", executablePath: "/bin/echo", isFavorite: true, displayOrder: 1)
        try store.createAction(normal)
        try store.createAction(favorite)
        XCTAssertEqual(try store.listActions().first?.name, "B")
    }

    func testMoveActionUpdatesDisplayOrder() throws {
        let first = Action(name: "A", executablePath: "/bin/echo", displayOrder: 0)
        let second = Action(name: "B", executablePath: "/bin/echo", displayOrder: 1)
        try store.createAction(first)
        try store.createAction(second)
        try store.moveAction(sourceID: second.id, before: first.id)
        XCTAssertEqual(try store.listActions().map { $0.name }, ["B", "A"])
    }
}
