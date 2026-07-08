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
            timeoutSeconds: 60
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
    }
}
