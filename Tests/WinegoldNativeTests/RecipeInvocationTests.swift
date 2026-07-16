import XCTest
@testable import WinegoldCore

final class RecipeInvocationTests: XCTestCase {
    func testTriggerlessRecipeParsesAndSerializesWithoutTrigger() throws {
        let document = try RecipeParser().parse(text: "name: Clear cache\ncmd:\n  exec: 'echo ok'\n")
        XCTAssertEqual(document.trigger, "")
        XCTAssertFalse(RecipeSerializer().serialize(document).contains("trigger:"))
    }

    func testTriggerlessActionIsValidWithoutInput() {
        let action = Action(name: "Clear cache", executablePath: "/bin/zsh")
        XCTAssertEqual(RecipeInvocationValidator().validate(action, items: []), .valid)
    }

    func testFileRecipeReportsMissingInput() {
        var action = Action(name: "Convert", executablePath: "/bin/zsh")
        action.triggerExpression = "extension in {\"jpg\" \"jpeg\"}"
        XCTAssertEqual(
            RecipeInvocationValidator().validate(action, items: []),
            .missingInput(.files(allowedExtensions: ["jpeg", "jpg"]))
        )
    }

    func testDirectoryRequirementIsDerived() {
        var action = Action(name: "Test project", executablePath: "/bin/zsh")
        action.triggerExpression = "kind equals \"directory\""
        XCTAssertEqual(RecipeInputRequirementResolver().requirement(for: action), .directories)
    }

    func testCompatibleAndIncompatibleFilesAreDistinguished() {
        var action = Action(name: "Convert", executablePath: "/bin/zsh")
        action.triggerExpression = "extension equals \"png\""
        let png = DraggedItem(executionURL: URL(fileURLWithPath: "/tmp/a.png"))
        let jpg = DraggedItem(executionURL: URL(fileURLWithPath: "/tmp/a.jpg"))
        XCTAssertEqual(RecipeInvocationValidator().validate(action, items: [png]), .valid)
        guard case let .incompatible(issues) = RecipeInvocationValidator().validate(action, items: [jpg]) else {
            return XCTFail("Expected incompatible")
        }
        XCTAssertEqual(issues.first?.message, "This recipe expects: .png")
    }

    func testAmbiguousOrDoesNotOverConstrainPicker() {
        var action = Action(name: "Open", executablePath: "/bin/zsh")
        action.triggerExpression = "isFile or isDirectory"
        XCTAssertEqual(RecipeInputRequirementResolver().requirement(for: action), .unresolved)
    }
}
