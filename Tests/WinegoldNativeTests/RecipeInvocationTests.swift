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
    func testCardinalityRejectsTooManyItems() {
        let action = Action(name: "Pair", triggerExpression: "extension equals \"png\"", minimumInputCount: 2, maximumInputCount: 2, executablePath: "/bin/zsh")
        let items = (0..<3).map { DraggedItem(executionURL: URL(fileURLWithPath: "/tmp/\($0).png")) }
        guard case let .incompatible(issues) = RecipeInvocationValidator().validate(action, items: items) else { return XCTFail("Expected incompatible") }
        XCTAssertEqual(issues.first?.message, "This recipe expects exactly 2 items.")
    }

    func testURLAndTextRequirementsAreDerived() {
        var url = Action(name: "URL", executablePath: "/bin/zsh")
        url.triggerExpression = "isURL and host equals \"example.com\""
        var text = Action(name: "Text", executablePath: "/bin/zsh")
        text.triggerExpression = "isText and text contains \"todo\""
        XCTAssertEqual(RecipeInputRequirementResolver().requirement(for: url), .url)
        XCTAssertEqual(RecipeInputRequirementResolver().requirement(for: text), .text)
    }

    func testNoInputPlaceholderIsRejected() {
        let action = Action(name: "Broken", minimumInputCount: 0, executablePath: "/bin/zsh", argumentsTemplate: ["-lc", "echo {input}"])
        XCTAssertEqual(RecipeTemplateInputValidator().missingInputPlaceholder(in: action), "{input}")
    }

    func testInputCardinalityParsesAndSerializes() throws {
        let source = "name: Pair\ninput:\n  min: 2\n  max: 2\ntrigger: 'extension equals \"png\"'\ncmd:\n  exec: echo ok\n"
        let document = try RecipeParser().parse(text: source)
        XCTAssertEqual(document.minimumInputCount, 2)
        XCTAssertEqual(document.maximumInputCount, 2)
        let serialized = RecipeSerializer().serialize(document)
        XCTAssertTrue(serialized.contains("input:"))
        XCTAssertTrue(serialized.contains("  min: 2"))
        XCTAssertTrue(serialized.contains("  max: 2"))
    }

}
