import XCTest
@testable import WinegoldCore

final class TriggerExpressionTests: XCTestCase {
    private let parser = TriggerParser()
    private let serializer = TriggerSerializer()
    private let evaluator = TriggerEvaluator()

    func testNestedRoundTripPreservesMeaning() throws {
        let source = "isURL or (extension in {\"md\" \"txt\"} and inside contains \"TODO\")"
        let parsed = try parser.parse(source)
        XCTAssertEqual(try parser.parse(serializer.serialize(parsed)), parsed)
    }

    func testBooleanShortcutAndGroupedNegation() throws {
        let values: [String: TriggerValue] = ["isURL": .bool(false), "extension": .string("png"), "size": .number(2_000_000)]
        XCTAssertTrue(evaluator.evaluate(try parser.parse("not isURL"), values: values))
        XCTAssertFalse(evaluator.evaluate(try parser.parse("not (extension equals \"png\" or size greaterThan 1000000)"), values: values))
    }

    func testOperators() throws {
        let values: [String: TriggerValue] = ["filename": .string("TODO-42.md"), "size": .number(42), "extension": .string("MD")]
        XCTAssertTrue(evaluator.evaluate(try parser.parse("filename matches /todo-[0-9]+/i and size greaterThanOrEqual 42 and extension in {\"md\" \"txt\"}"), values: values))
        XCTAssertFalse(evaluator.evaluate(try parser.parse("filename startsWithCase \"todo\""), values: values))
    }

    func testMissingPropertyIsFalseEvenWhenNegatedComparison() throws {
        XCTAssertFalse(evaluator.evaluate(try parser.parse("host notIn {\"example.com\"}"), values: [:]))
    }

    func testInvalidExpressionThrows() {
        XCTAssertThrowsError(try parser.parse("extension equals"))
        XCTAssertThrowsError(try parser.parse("(isFile"))
    }

    func testValidatorDetectsFieldTypeInconsistency() throws {
        XCTAssertEqual(TriggerValidator().issues(in: try parser.parse("host greaterThan 2")).first, "greaterThan requires the numeric size field")
        XCTAssertTrue(TriggerValidator().issues(in: try parser.parse("size lessThan 20")).isEmpty)
    }
}
