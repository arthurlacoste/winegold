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
            triggerExpression: "extension in {\"jpg\" \"png\"}",
            executablePath: "/opt/homebrew/bin/magick",
            argumentsTemplate: ["{input}", "-quality", "85", "{basename}.webp"],
            workingDirectoryTemplate: "{parent}",
            outputPathTemplate: "{parent}/{basename}.webp",
            successMessage: "Created {basename}.webp",
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
        XCTAssertEqual(loaded.triggerExpression, original.triggerExpression)
        XCTAssertEqual(loaded.executablePath, original.executablePath)
        XCTAssertEqual(loaded.argumentsTemplate, original.argumentsTemplate)
        XCTAssertEqual(loaded.workingDirectoryTemplate, original.workingDirectoryTemplate)
        XCTAssertEqual(loaded.outputPathTemplate, original.outputPathTemplate)
        XCTAssertEqual(loaded.successMessage, original.successMessage)
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

    func testRecipeMetadataAndUsageRoundTrip() throws {
        let action = Action(name: "Run tests", executablePath: "/bin/zsh", argumentsTemplate: ["-lc", "npm test"])
        try store.upsertDerivedRecipe(
            action,
            externalID: "winegold.node/test",
            parentExternalID: "winegold.node",
            childActionID: "test",
            parentName: "Node project",
            path: "/tmp/node.wg.yml",
            hash: "abc",
            category: "development"
        )
        let usedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try store.incrementUsage(actionID: action.id, at: usedAt)
        try store.incrementUsage(actionID: action.id, at: usedAt)

        let metadata = try XCTUnwrap(store.metadata(for: action.id))
        XCTAssertEqual(metadata.externalID, "winegold.node/test")
        XCTAssertEqual(metadata.parentExternalID, "winegold.node")
        XCTAssertEqual(metadata.childActionID, "test")
        XCTAssertEqual(metadata.parentName, "Node project")
        XCTAssertEqual(metadata.usageCount, 2)
        XCTAssertEqual(try XCTUnwrap(metadata.lastUsedAt).timeIntervalSince1970, usedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testLocalEnabledOverrideIsTriStateAndSurvivesUpsert() throws {
        let action = Action(name: "Build", enabled: true, executablePath: "/bin/zsh")
        try store.upsertDerivedRecipe(
            action,
            externalID: "winegold.node/build",
            parentExternalID: "winegold.node",
            childActionID: "build",
            parentName: "Node",
            path: "/tmp/node.wg.yml",
            hash: "one",
            category: nil
        )
        try store.setLocalEnabledOverride(actionID: action.id, value: false)

        var yamlChanged = action
        yamlChanged.enabled = true
        try store.upsertDerivedRecipe(
            yamlChanged,
            externalID: "winegold.node/build",
            parentExternalID: "winegold.node",
            childActionID: "build",
            parentName: "Node",
            path: "/tmp/node.wg.yml",
            hash: "two",
            category: nil
        )

        var metadata = try XCTUnwrap(store.metadata(for: action.id))
        XCTAssertEqual(metadata.localEnabledOverride, false)
        XCTAssertFalse(metadata.action.enabled)

        try store.clearLocalEnabledOverride(actionID: action.id)
        try store.upsertDerivedRecipe(
            yamlChanged,
            externalID: "winegold.node/build",
            parentExternalID: "winegold.node",
            childActionID: "build",
            parentName: "Node",
            path: "/tmp/node.wg.yml",
            hash: "three",
            category: nil
        )
        metadata = try XCTUnwrap(store.metadata(for: action.id))
        XCTAssertNil(metadata.localEnabledOverride)
        XCTAssertTrue(metadata.action.enabled)
    }

    func testLocalOrderCanBeSetAndClearedPerParent() throws {
        let first = Action(name: "Dev", executablePath: "/bin/zsh", displayOrder: 0)
        let second = Action(name: "Test", executablePath: "/bin/zsh", displayOrder: 1)
        for (action, childID) in [(first, "dev"), (second, "test")] {
            try store.upsertDerivedRecipe(
                action,
                externalID: "winegold.node/\(childID)",
                parentExternalID: "winegold.node",
                childActionID: childID,
                parentName: "Node",
                path: "/tmp/node.wg.yml",
                hash: "abc",
                category: nil
            )
        }

        try store.setLocalOrder(parentID: "winegold.node", orderedActionIDs: [second.id, first.id])
        var ordered = try store.listActions(forParentID: "winegold.node")
        XCTAssertEqual(ordered.map(\.action.name), ["Test", "Dev"])
        XCTAssertEqual(ordered.map(\.localOrderOverride), [0, 1])

        try store.clearLocalOrder(parentID: "winegold.node")
        ordered = try store.listActions(forParentID: "winegold.node")
        XCTAssertTrue(ordered.allSatisfy { $0.localOrderOverride == nil })
    }

}
