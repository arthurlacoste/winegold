import AppKit
import XCTest
@testable import WinegoldUI

@MainActor
final class TriggerEditorViewTests: XCTestCase {
    private var view: TriggerEditorView!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        view = TriggerEditorView(frame: NSRect(x: 0, y: 0, width: 580, height: 210))
    }

    func testRootAddConditionButtonCreatesAndGroup() throws {
        try click(identifier: "add-root-condition")

        XCTAssertEqual(view.stringValue, "extension in {\"*\"} and extension in {\"png\"}")
        XCTAssertEqual(buttons(titled: "AND").count, 1)
        XCTAssertEqual(popups(role: "field").count, 2)
    }

    func testNestedGroupsCanBeAddedAndChangedToOr() throws {
        try click(identifier: "add-root-condition")
        try click(identifier: "group:")

        XCTAssertEqual(button(identifier: "toggle:2")?.title, "AND")
        try click(identifier: "add:2")
        try click(identifier: "toggle:2")

        XCTAssertEqual(button(identifier: "toggle:2")?.title, "OR")
        XCTAssertEqual(
            view.stringValue,
            "extension in {\"*\"} and extension in {\"png\"} and (extension in {\"png\"} or extension in {\"png\"})"
        )
    }

    func testNestedOrCanBecomeNotWithoutLosingChildren() throws {
        try click(identifier: "add-root-condition")
        try click(identifier: "group:")
        try click(identifier: "add:2")
        try click(identifier: "toggle:2")
        try click(identifier: "toggle:2")

        XCTAssertTrue(view.stringValue.contains("not (extension in {\"png\"} or extension in {\"png\"})"))
        XCTAssertEqual(popups(role: "field").count, 4)
    }

    func testNestedConditionCanBeRemoved() throws {
        try click(identifier: "add-root-condition")
        try click(identifier: "group:")
        try click(identifier: "add:2")
        try click(identifier: "remove:2.1")

        XCTAssertEqual(view.stringValue, "extension in {\"*\"} and extension in {\"png\"} and extension in {\"png\"}")
        XCTAssertNil(button(identifier: "toggle:2"))
    }

    func testSelectingBooleanShortcutRemovesOperatorAndValueControls() throws {
        let field = try XCTUnwrap(popup(identifier: "field:"))
        field.selectItem(withTitle: "isFile")
        field.sendAction(field.action, to: field.target)

        XCTAssertEqual(view.stringValue, "isFile")
        XCTAssertNil(popup(identifier: "operator:"))
        XCTAssertNil(control(identifier: "value:"))
    }

    func testTypingTwoExtensionsUpdatesExpressionBeforeEndEditing() throws {
        let value = try XCTUnwrap(control(identifier: "value:") as? NSTextField)
        value.stringValue = "webp, txt"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: value))

        XCTAssertEqual(view.stringValue, "extension in {\"webp\" \"txt\"}")
        XCTAssertEqual(value.stringValue, "webp, txt")
    }

    func testDirectNestedExpressionRebuildsVisualGroups() throws {
        let mode = try XCTUnwrap(control(identifier: "trigger-mode") as? NSSegmentedControl)
        mode.selectedSegment = 1
        mode.sendAction(mode.action, to: mode.target)
        let field = try XCTUnwrap(control(identifier: "expression-field") as? NSTextField)
        field.stringValue = "isURL or (isText and text contains \"TODO\")"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        mode.selectedSegment = 0
        mode.sendAction(mode.action, to: mode.target)

        XCTAssertEqual(buttons(titled: "OR").count, 1)
        XCTAssertEqual(buttons(titled: "AND").count, 1)
        XCTAssertEqual(popups(role: "field").count, 3)
        XCTAssertEqual(view.stringValue, "isURL or isText and text contains \"TODO\"")
    }

    func testNestedBuilderRendersSnapshot() throws {
        view.stringValue = "isURL or (extension in {\"md\" \"txt\"} and (inside contains \"TODO\" or size lessThan 1048576))"
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: "/tmp/winegold-trigger-builder-test.png")
        try png.write(to: url)

        XCTAssertGreaterThan(png.count, 10_000)
        XCTAssertEqual(popups(role: "field").count, 4)
        XCTAssertEqual(buttons(titled: "OR").count, 2)
        XCTAssertEqual(buttons(titled: "AND").count, 1)
        XCTAssertFalse(subviews(in: view).contains { $0 is NSBox })
        let content = try XCTUnwrap(subviews(in: view).first { $0.identifier?.rawValue == "trigger-builder-content" })
        XCTAssertTrue(content.isFlipped)
        let outerGroup = try XCTUnwrap(directChild(of: content, containing: button(identifier: "toggle:")))
        let firstCondition = try XCTUnwrap(popup(identifier: "field:0"))
        let nestedGroup = try XCTUnwrap(directChild(of: content, containing: button(identifier: "toggle:1")))
        XCTAssertLessThan(outerGroup.frame.minY, firstCondition.frame.minY)
        XCTAssertLessThan(firstCondition.frame.minY, nestedGroup.frame.minY)
        let scroll = try XCTUnwrap(content.enclosingScrollView)
        let deepestField = try XCTUnwrap(popup(identifier: "field:1.1.1"))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, content.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertTrue(scroll.contentView.bounds.intersects(deepestField.frame))
    }

    private func click(identifier: String) throws {
        let item = try XCTUnwrap(button(identifier: identifier), "Missing button \(identifier)")
        item.performClick(nil)
    }

    private func control(identifier: String) -> NSControl? {
        controls(in: view).first { $0.identifier?.rawValue == identifier }
    }

    private func button(identifier: String) -> NSButton? { control(identifier: identifier) as? NSButton }
    private func popup(identifier: String) -> NSPopUpButton? { control(identifier: identifier) as? NSPopUpButton }
    private func buttons(titled title: String) -> [NSButton] { controls(in: view).compactMap { $0 as? NSButton }.filter { $0.title == title } }
    private func popups(role: String) -> [NSPopUpButton] { controls(in: view).compactMap { $0 as? NSPopUpButton }.filter { $0.identifier?.rawValue.hasPrefix("\(role):") == true } }
    private func controls(in root: NSView) -> [NSControl] { subviews(in: root).compactMap { $0 as? NSControl } }
    private func subviews(in root: NSView) -> [NSView] { root.subviews + root.subviews.flatMap(subviews) }
    private func directChild(of ancestor: NSView, containing descendant: NSView?) -> NSView? {
        var current = descendant
        while let view = current, view.superview !== ancestor { current = view.superview }
        return current
    }
}
