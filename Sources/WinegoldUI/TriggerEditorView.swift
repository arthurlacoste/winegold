import Cocoa
import WinegoldCore

public final class TriggerEditorView: NSView, NSTextFieldDelegate {
    private var expression: TriggerExpression = .condition(field: "extension", operator: .in, value: .collection(["*"]))
    private let mode = NSSegmentedControl(labels: ["Builder", "Expression"], trackingMode: .selectOne, target: nil, action: nil)
    private let addRootConditionButton = NSButton()
    private let content = TriggerContentView()
    private let expressionField = NSTextField()
    private let preview = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")

    public var stringValue: String {
        get { mode.selectedSegment == 1 ? expressionField.stringValue : TriggerSerializer().serialize(expression) }
        set {
            do { expression = try TriggerParser().parse(newValue); updateIssues() }
            catch { errorLabel.stringValue = error.localizedDescription }
            refresh()
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.identifier = .init("trigger-mode")
        mode.selectedSegment = 0
        mode.frame = NSRect(x: 0, y: bounds.height - 27, width: 190, height: 26)
        addSubview(mode)

        addRootConditionButton.title = "+ Condition"
        addRootConditionButton.target = self
        addRootConditionButton.action = #selector(addRootCondition)
        addRootConditionButton.identifier = .init("add-root-condition")
        addRootConditionButton.bezelStyle = .rounded
        addRootConditionButton.frame = NSRect(x: bounds.width - 108, y: bounds.height - 27, width: 108, height: 26)
        addSubview(addRootConditionButton)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 48, width: bounds.width, height: bounds.height - 80))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = content
        content.identifier = .init("trigger-builder-content")
        addSubview(scroll)

        expressionField.frame = scroll.frame
        expressionField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        expressionField.identifier = .init("expression-field")
        expressionField.delegate = self
        expressionField.isHidden = true
        addSubview(expressionField)

        preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        preview.textColor = .secondaryLabelColor
        preview.lineBreakMode = .byTruncatingMiddle
        preview.frame = NSRect(x: 0, y: 24, width: bounds.width, height: 18)
        addSubview(preview)

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 0, y: 2, width: bounds.width, height: 18)
        addSubview(errorLabel)
        refresh()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:)") }

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if mode.selectedSegment == 1, field === expressionField {
            do {
                expression = try TriggerParser().parse(expressionField.stringValue)
                updateIssues()
                preview.stringValue = TriggerSerializer().serialize(expression)
            } catch { errorLabel.stringValue = error.localizedDescription }
            return
        }
        guard field.identifier?.rawValue.hasPrefix("value:") == true else { return }
        let p = path(field)
        guard case let .condition(name, op, _) = node(at: p) else { return }
        replace(at: p, with: .condition(field: name, operator: op, value: parseLiteral(field.stringValue, op: op)))
        preview.stringValue = TriggerSerializer().serialize(expression)
        updateIssues()
    }

    @objc private func modeChanged() {
        let direct = mode.selectedSegment == 1
        addRootConditionButton.isHidden = direct
        expressionField.isHidden = !direct
        content.superview?.superview?.isHidden = direct
        if direct { expressionField.stringValue = stringValue }
        else if let parsed = try? TriggerParser().parse(expressionField.stringValue) { expression = parsed; refresh() }
    }

    private func refresh() {
        expressionField.stringValue = stringValue
        preview.stringValue = stringValue
        updateIssues()
        content.subviews.forEach { $0.removeFromSuperview() }
        let height = build(expression, path: [], x: 8, y: 8, width: bounds.width - 32)
        content.frame = NSRect(x: 0, y: 0, width: bounds.width - 16, height: max(height + 8, bounds.height - 82))
    }

    private func updateIssues() { errorLabel.stringValue = TriggerValidator().issues(in: expression).first ?? "" }

    @discardableResult
    private func build(_ node: TriggerExpression, path: [Int], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        switch node {
        case let .condition(field, op, literal):
            let fields = ["input", "parent", "parentName", "filename", "basename", "extension", "dotExtension", "inside", "kind", "mimeType", "uti", "size", "finderTags", "url", "scheme", "host", "urlPath", "query", "fragment", "text", "isFile", "isDirectory", "isURL", "isText"]
            let fieldPopup = popup(fields, selected: field, frame: NSRect(x: x, y: y, width: 125, height: 25))
            fieldPopup.target = self; fieldPopup.action = #selector(conditionChanged(_:)); fieldPopup.identifier = id("field", path)
            content.addSubview(fieldPopup)
            if isBooleanField(field) {
                let remove = NSButton(title: "−", target: self, action: #selector(removeNode(_:)))
                remove.bezelStyle = .inline; remove.frame = NSRect(x: x + width - 32, y: y, width: 30, height: 24); remove.identifier = id("remove", path)
                content.addSubview(remove)
                return y + 31
            }
            let ops = TriggerOperator.allCases.map(\.rawValue)
            let opPopup = popup(ops, selected: op.rawValue, frame: NSRect(x: x + 130, y: y, width: 150, height: 25))
            opPopup.target = self; opPopup.action = #selector(conditionChanged(_:)); opPopup.identifier = id("operator", path)
            content.addSubview(opPopup)
            let value = NSTextField(frame: NSRect(x: x + 285, y: y, width: max(80, width - 370), height: 24))
            value.stringValue = literalText(literal); value.placeholderString = op == .in || op == .notIn ? "png, jpg" : "Value"
            value.delegate = self
            value.target = self; value.action = #selector(conditionChanged(_:)); value.identifier = id("value", path)
            content.addSubview(value)
            let remove = NSButton(title: "−", target: self, action: #selector(removeNode(_:)))
            remove.bezelStyle = .inline; remove.frame = NSRect(x: x + width - 32, y: y, width: 30, height: 24); remove.identifier = id("remove", path)
            content.addSubview(remove)
            return y + 31
        case let .not(child):
            let label = groupLabel("NOT", x: x, y: y, width: width, path: path)
            content.addSubview(label)
            return build(child, path: path + [0], x: x + 20, y: y + 30, width: width - 20)
        case let .and(children), let .or(children):
            let isAnd: Bool = { if case .and = node { return true }; return false }()
            let label = groupLabel(isAnd ? "AND" : "OR", x: x, y: y, width: width, path: path)
            content.addSubview(label)
            var nextY = y + 30
            for (index, child) in children.enumerated() { nextY = build(child, path: path + [index], x: x + 20, y: nextY, width: width - 20) }
            let add = NSButton(title: "+ Condition", target: self, action: #selector(addCondition(_:)))
            add.bezelStyle = .inline; add.frame = NSRect(x: x + 20, y: nextY, width: 90, height: 24); add.identifier = id("add", path); content.addSubview(add)
            let group = NSButton(title: "+ Group", target: self, action: #selector(addGroup(_:)))
            group.bezelStyle = .inline; group.frame = NSRect(x: x + 112, y: nextY, width: 75, height: 24); group.identifier = id("group", path); content.addSubview(group)
            return nextY + 28
        }
    }

    private func groupLabel(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, path: [Int]) -> NSView {
        let container = NSView(frame: NSRect(x: x, y: y, width: width, height: 26))
        let button = NSButton(title: title, target: self, action: #selector(toggleGroup(_:)))
        button.bezelStyle = .inline; button.frame = NSRect(x: 0, y: 1, width: 54, height: 22); button.identifier = id("toggle", path); container.addSubview(button)
        if !path.isEmpty { let remove = NSButton(title: "−", target: self, action: #selector(removeNode(_:))); remove.bezelStyle = .inline; remove.frame = NSRect(x: width - 30, y: 1, width: 26, height: 22); remove.identifier = id("remove", path); container.addSubview(remove) }
        return container
    }

    private func popup(_ values: [String], selected: String, frame: NSRect) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame); popup.addItems(withTitles: values); if popup.itemTitles.contains(selected) { popup.selectItem(withTitle: selected) }; return popup
    }

    private func id(_ role: String, _ path: [Int]) -> NSUserInterfaceItemIdentifier { .init(role + ":" + path.map(String.init).joined(separator: ".")) }
    private func path(_ sender: NSControl) -> [Int] { sender.identifier?.rawValue.split(separator: ":").last?.split(separator: ".").compactMap { Int($0) } ?? [] }

    @objc private func conditionChanged(_ sender: NSControl) {
        let p = path(sender); guard case let .condition(field, op, literal) = node(at: p) else { return }
        let role = sender.identifier?.rawValue.split(separator: ":").first.map(String.init) ?? ""
        var nextField = field, nextOp = op, nextLiteral = literal
        if role == "field", let popup = sender as? NSPopUpButton {
            nextField = popup.titleOfSelectedItem ?? field
            if isBooleanField(nextField) {
                nextOp = .equals
                nextLiteral = nil
            } else if isBooleanField(field) {
                nextOp = .equals
                nextLiteral = .string("")
            }
        }
        if role == "operator", let popup = sender as? NSPopUpButton, let value = popup.titleOfSelectedItem.flatMap(TriggerOperator.init(rawValue:)) { nextOp = value; if value == .exists { nextLiteral = nil } }
        if role == "value", let field = sender as? NSTextField { nextLiteral = parseLiteral(field.stringValue, op: nextOp) }
        replace(at: p, with: .condition(field: nextField, operator: nextOp, value: nextLiteral)); refresh()
    }

    @objc private func removeNode(_ sender: NSControl) { remove(at: path(sender)); refresh() }
    @objc private func toggleGroup(_ sender: NSControl) { let p = path(sender); let node = node(at: p); if case let .and(c) = node { replace(at: p, with: .or(c)) } else if case .or = node { replace(at: p, with: .not(node)) } else if case let .not(c) = node { replace(at: p, with: .and([c])) }; refresh() }
    @objc private func addCondition(_ sender: NSControl) { append(defaultCondition, at: path(sender)); refresh() }
    @objc private func addRootCondition() { append(defaultCondition, at: []); refresh() }
    @objc private func addGroup(_ sender: NSControl) { append(.and([defaultCondition]), at: path(sender)); refresh() }
    private var defaultCondition: TriggerExpression { .condition(field: "extension", operator: .in, value: .collection(["png"])) }
    private func isBooleanField(_ field: String) -> Bool { ["isFile", "isDirectory", "isURL", "isText"].contains(field) }

    private func node(at path: [Int]) -> TriggerExpression { path.reduce(expression) { current, index in switch current { case let .and(c), let .or(c): return c.indices.contains(index) ? c[index] : current; case let .not(c): return index == 0 ? c : current; default: return current } } }
    private func replace(at path: [Int], with replacement: TriggerExpression) { expression = transformed(expression, path: path) { _ in replacement } }
    private func append(_ child: TriggerExpression, at path: [Int]) { expression = transformed(expression, path: path) { node in switch node { case var .and(c): c.append(child); return .and(c); case var .or(c): c.append(child); return .or(c); default: return .and([node, child]) } } }
    private func remove(at path: [Int]) { guard let index = path.last else { return }; let parent = Array(path.dropLast()); expression = transformed(expression, path: parent) { node in switch node { case var .and(c): if c.indices.contains(index) { c.remove(at: index) }; return c.count == 1 ? c[0] : .and(c); case var .or(c): if c.indices.contains(index) { c.remove(at: index) }; return c.count == 1 ? c[0] : .or(c); case .not: return self.defaultCondition; default: return node } } }
    private func transformed(_ node: TriggerExpression, path: [Int], transform: (TriggerExpression) -> TriggerExpression) -> TriggerExpression { guard let first = path.first else { return transform(node) }; let rest = Array(path.dropFirst()); switch node { case var .and(c): if c.indices.contains(first) { c[first] = transformed(c[first], path: rest, transform: transform) }; return .and(c); case var .or(c): if c.indices.contains(first) { c[first] = transformed(c[first], path: rest, transform: transform) }; return .or(c); case let .not(c): return first == 0 ? .not(transformed(c, path: rest, transform: transform)) : node; default: return node } }

    private func literalText(_ literal: TriggerLiteral?) -> String { guard let literal else { return "" }; switch literal { case let .string(v): return v; case let .number(v): return String(v); case let .collection(v): return v.joined(separator: ", "); case let .regex(v, f): return "/\(v)/\(f)" } }
    private func parseLiteral(_ text: String, op: TriggerOperator) -> TriggerLiteral { if [.greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual].contains(op), let number = Double(text) { return .number(number) }; if op == .in || op == .notIn { return .collection(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }; if op == .matches, text.hasPrefix("/"), let last = text.dropFirst().lastIndex(of: "/") { return .regex(String(text[text.index(after: text.startIndex)..<last]), String(text[text.index(after: last)...])) }; return .string(text) }
}

private final class TriggerContentView: NSView {
    override var isFlipped: Bool { true }
}
