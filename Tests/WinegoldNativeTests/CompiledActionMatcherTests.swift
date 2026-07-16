import XCTest
@testable import WinegoldCore

final class CompiledActionMatcherTests: XCTestCase {
    private func action(_ name: String, trigger: String) -> Action {
        var value = Action(name: name, acceptedExtensions: [], executablePath: "/bin/echo")
        value.triggerExpression = trigger
        return value
    }

    func testClassifiesAndPublishesCheapBeforeMetadata() {
        let cheap = action("Markdown", trigger: "extension equals \"md\"")
        let metadata = action("Images", trigger: "mimeType startsWith \"image/\"")
        let compiled = CompiledActionSet(actions: [metadata, cheap])

        XCTAssertEqual(compiled.triggers.map(\.cost).sorted(), [.cheap, .metadata])

        let item = DraggedItem(executionURL: URL(fileURLWithPath: "/tmp/readme.md"), kind: .file)
        let batches = ProgressiveActionMatcher().batches(forItems: [item], compiled: compiled)
        XCTAssertEqual(batches.first?.cost, .cheap)
        XCTAssertEqual(batches.first?.actions.map(\.name), ["Markdown"])
    }

    func testInvalidTriggerIsIsolated() {
        let invalid = action("Broken", trigger: "extension equals")
        let valid = action("Text", trigger: "extension equals \"txt\"")
        let compiled = CompiledActionSet(actions: [invalid, valid])
        let item = DraggedItem(executionURL: URL(fileURLWithPath: "/tmp/a.txt"), kind: .file)

        let final = ProgressiveActionMatcher().batches(forItems: [item], compiled: compiled).last
        XCTAssertEqual(final?.actions.map(\.name), ["Text"])
    }

    func testContentTriggerIsLastTier() {
        let content = action("Todo", trigger: "inside contains \"TODO\"")
        let cheap = action("Text", trigger: "extension equals \"txt\"")
        let compiled = CompiledActionSet(actions: [content, cheap])

        XCTAssertEqual(compiled.triggers.first(where: { $0.action.name == "Todo" })?.cost, .content)
    }
    func testCompilationCacheReusesUnchangedActions() {
        let cache = CompiledActionCache()
        let actions = [action("Text", trigger: "extension equals \"txt\"")]

        _ = cache.compiled(actions: actions)
        _ = cache.compiled(actions: actions)

        XCTAssertEqual(cache.compilationCount, 1)
    }

    func testCompilationCacheInvalidatesChangedTrigger() {
        let cache = CompiledActionCache()
        var value = action("Text", trigger: "extension equals \"txt\"")
        _ = cache.compiled(actions: [value])
        value.triggerExpression = "extension equals \"md\""
        _ = cache.compiled(actions: [value])

        XCTAssertEqual(cache.compilationCount, 2)
    }

}
