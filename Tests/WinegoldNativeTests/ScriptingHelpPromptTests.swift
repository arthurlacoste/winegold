import XCTest
@testable import WinegoldCore

final class ScriptingHelpPromptTests: XCTestCase {
    func testPromptUsesDocumentationAndCurrentPlaceholders() {
        let prompt = ScriptingHelpPrompt.make(
            scriptName: "Summarize Ollama",
            extensions: ["txt", "js", "php"],
            command: "cd /opt/homebrew/opt/ && ollama run gemma4:e2b \"Summarize this file: {inside}\"",
            documentation: ScriptingGuide.text
        )

        XCTAssertTrue(prompt.contains("Use this documentation as the single source of truth."))
        XCTAssertTrue(prompt.contains("# Writing Winegold scripts"))
        XCTAssertTrue(prompt.contains("{input}"))
        XCTAssertTrue(prompt.contains("{inside}"))
        XCTAssertTrue(prompt.contains("Script name: Summarize Ollama"))
        XCTAssertTrue(prompt.contains("Extensions: txt, js, php"))
    }

    func testPromptDoesNotContainOldHardcodedHelp() {
        let prompt = ScriptingHelpPrompt.make(
            scriptName: "Test",
            extensions: ["txt"],
            command: "echo \"{input}\"",
            documentation: ScriptingGuide.text
        )

        XCTAssertFalse(prompt.contains("Current supported YAML format"))
        XCTAssertFalse(prompt.contains("Supported placeholders:"))
        XCTAssertFalse(prompt.contains("{{file}}"))
        XCTAssertFalse(prompt.contains("{{"))
        XCTAssertFalse(prompt.contains("}}"))
    }
}
