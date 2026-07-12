import XCTest
@testable import WinegoldCore

final class RecipeSetupRequirementsTests: XCTestCase {
    func testSingleMissingCommandUsesInstallLabel() {
        let requirements = RecipeSetupRequirements(missingCommands: ["pandoc"])

        XCTAssertFalse(requirements.isReady)
        XCTAssertEqual(requirements.actionLabel, "Install pandoc")
        XCTAssertEqual(requirements.summary, "Missing: pandoc")
    }

    func testMissingSecretUsesConfigureSecretLabel() {
        let secret = RecipeVariable(name: "API_TOKEN", secret: true, required: true)
        let requirements = RecipeSetupRequirements(missingVariables: [secret])

        XCTAssertEqual(requirements.actionLabel, "Configure secret")
        XCTAssertEqual(requirements.summary, "Configure: API_TOKEN")
    }

    func testSeveralBlockersUseCompactSetupLabelAndSummary() {
        let variables = [
            RecipeVariable(name: "TOKEN", secret: true, required: true),
            RecipeVariable(name: "ENDPOINT", required: true)
        ]
        let requirements = RecipeSetupRequirements(
            missingCommands: ["pandoc"],
            missingVariables: variables
        )

        XCTAssertEqual(requirements.actionLabel, "Set up")
        XCTAssertEqual(requirements.summary, "Missing: pandoc · Configure: TOKEN, ENDPOINT")
    }

    func testNoBlockersIsReady() {
        XCTAssertTrue(RecipeSetupRequirements().isReady)
    }
}
