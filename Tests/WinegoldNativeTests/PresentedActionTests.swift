import XCTest
@testable import WinegoldCore

final class PresentedActionTests: XCTestCase {
    func testAutomaticOrderUsesFavoriteThenUsageThenYAMLOrder() {
        let items = [
            item("Build", usage: 2, order: 2),
            item("Test", usage: 8, order: 1),
            item("Dev", favorite: true, usage: 0, order: 0)
        ]
        XCTAssertEqual(ActionPresentationPolicy().sort(items).map(\.action.name), ["Dev", "Test", "Build"])
    }

    func testManualParentOrderStopsUsageReordering() {
        let items = [
            item("Dev", parent: "node", usage: 100, order: 0, localOrder: 1),
            item("Test", parent: "node", usage: 1, order: 1, localOrder: 0)
        ]
        XCTAssertEqual(ActionPresentationPolicy().sort(items).map(\.action.name), ["Test", "Dev"])
    }

    func testDefaultPresentationLimitsToTenButSearchIncludesLaterMatches() {
        let items = (0..<17).map { item("Action \($0)", parentName: $0 == 16 ? "Node project" : nil, usage: 17 - $0, order: $0) }
        XCTAssertEqual(ActionPresentationPolicy().present(items).count, 10)
        XCTAssertEqual(ActionPresentationPolicy().present(items, query: "Node project").map(\.action.name), ["Action 16"])
    }

    func testSearchMatchesChildDescriptionAndIDs() {
        let action = Action(name: "Run tests", description: "Run the full suite", executablePath: "/bin/zsh")
        let item = PresentedAction(action: action, parentName: "Node project", parentExternalID: "winegold.node", childActionID: "test")
        let policy = ActionPresentationPolicy()
        XCTAssertEqual(policy.present([item], query: "suite").count, 1)
        XCTAssertEqual(policy.present([item], query: "winegold.node").count, 1)
        XCTAssertEqual(policy.present([item], query: "test").count, 1)
    }

    private func item(
        _ name: String,
        parent: String? = nil,
        parentName: String? = nil,
        favorite: Bool = false,
        usage: Int = 0,
        order: Int = 0,
        localOrder: Int? = nil
    ) -> PresentedAction {
        PresentedAction(
            action: Action(name: name, executablePath: "/bin/zsh", isFavorite: favorite, displayOrder: order),
            parentName: parentName,
            parentExternalID: parent,
            childActionID: name.lowercased(),
            usageCount: usage,
            localOrderOverride: localOrder
        )
    }
}
