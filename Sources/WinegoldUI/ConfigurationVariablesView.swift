import AppKit

public struct ConfigurationVariablePresentation: Equatable {
    public let name: String
    public let label: String
    public let value: String
    public let source: String
    public let isSecret: Bool
    public let isRequired: Bool
    public let isConfigured: Bool
    public let canRemove: Bool
    public let warning: String?

    public init(
        name: String,
        label: String,
        value: String,
        source: String,
        isSecret: Bool,
        isRequired: Bool,
        isConfigured: Bool,
        canRemove: Bool = false,
        warning: String? = nil
    ) {
        self.name = name
        self.label = label
        self.value = value
        self.source = source
        self.isSecret = isSecret
        self.isRequired = isRequired
        self.isConfigured = isConfigured
        self.canRemove = canRemove
        self.warning = warning
    }
}

public final class ConfigurationVariablesView: NSView {
    public var onValueChanged: ((String, String) -> Void)?
    public var onSetupSecret: ((String) -> Void)?
    public var onRemoveValue: ((String) -> Void)?

    private let stack = NSStackView()
    private var presentations: [ConfigurationVariablePresentation] = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:)") }

    public override var intrinsicContentSize: NSSize {
        let size = stack.fittingSize
        return NSSize(width: NSView.noIntrinsicMetric, height: max(22, size.height))
    }

    public func apply(_ values: [ConfigurationVariablePresentation]) {
        presentations = values
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if values.isEmpty {
            let empty = NSTextField(labelWithString: "No variables.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(empty)
            return
        }

        for value in values {
            stack.addArrangedSubview(makeRow(value))
        }
        invalidateIntrinsicContentSize()
    }

    private func makeRow(_ item: ConfigurationVariablePresentation) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.identifier = NSUserInterfaceItemIdentifier("configuration-row:\(item.name)")

        let label = NSTextField(labelWithString: item.label)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.identifier = NSUserInterfaceItemIdentifier("configuration-label:\(item.name)")
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let badges = NSStackView()
        badges.orientation = .horizontal
        badges.spacing = 6
        badges.alignment = .centerY
        badges.setContentHuggingPriority(.required, for: .horizontal)
        if item.isRequired {
            let badge = makeBadge("Required", color: .systemOrange)
            badge.identifier = NSUserInterfaceItemIdentifier("configuration-required:\(item.name)")
            badges.addArrangedSubview(badge)
        }
        if item.isSecret {
            let badge = makeBadge("Secret", color: .secondaryLabelColor)
            badge.identifier = NSUserInterfaceItemIdentifier("configuration-secret:\(item.name)")
            badges.addArrangedSubview(badge)
        }

        let source = NSTextField(labelWithString: item.source)
        source.font = .systemFont(ofSize: 11)
        source.textColor = .tertiaryLabelColor
        source.lineBreakMode = .byTruncatingTail
        source.alignment = .left
        source.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        source.widthAnchor.constraint(equalToConstant: 86).isActive = true

        let valueControl: NSView
        if item.isSecret {
            let masked = NSTextField(labelWithString: item.isConfigured ? "••••••••" : "Not set")
            masked.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            masked.textColor = item.isConfigured ? .labelColor : .tertiaryLabelColor
            masked.identifier = NSUserInterfaceItemIdentifier("configuration-value:\(item.name)")
            valueControl = masked
        } else {
            let field = NSTextField(string: item.value)
            field.font = .systemFont(ofSize: 12)
            field.placeholderString = "Value"
            field.identifier = NSUserInterfaceItemIdentifier("configuration-value:\(item.name)")
            field.target = self
            field.action = #selector(valueChanged(_:))
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            valueControl = field
        }
        valueControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        let action = NSButton(
            title: item.isSecret ? (item.isConfigured ? "Replace secret" : "Set up") : "Remove",
            target: self,
            action: item.isSecret ? #selector(setupSecret(_:)) : #selector(removeValue(_:))
        )
        action.bezelStyle = .rounded
        action.controlSize = .small
        action.identifier = NSUserInterfaceItemIdentifier("configuration-action:\(item.name)")
        action.isHidden = !item.isSecret && !item.canRemove
        action.setContentHuggingPriority(.required, for: .horizontal)
        action.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true

        let controls = NSStackView(views: [badges, valueControl, source, action])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        controls.distribution = .fill
        controls.translatesAutoresizingMaskIntoConstraints = false

        let mainRow = NSStackView(views: [label, controls])
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 10
        mainRow.distribution = .fill
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(mainRow)

        var constraints = [
            mainRow.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            mainRow.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            mainRow.topAnchor.constraint(equalTo: row.topAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: item.warning == nil ? 28 : 52)
        ]

        if let warning = item.warning, !warning.isEmpty {
            let warningLabel = NSTextField(wrappingLabelWithString: warning)
            warningLabel.font = .systemFont(ofSize: 11)
            warningLabel.textColor = .systemOrange
            warningLabel.identifier = NSUserInterfaceItemIdentifier("configuration-warning:\(item.name)")
            warningLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(warningLabel)
            constraints += [
                warningLabel.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
                warningLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                warningLabel.topAnchor.constraint(equalTo: mainRow.bottomAnchor, constant: 4),
                warningLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor)
            ]
        } else {
            constraints.append(mainRow.bottomAnchor.constraint(equalTo: row.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return row
    }

    private func makeBadge(_ text: String, color: NSColor) -> NSTextField {
        let badge = NSTextField(labelWithString: text)
        badge.font = .systemFont(ofSize: 10, weight: .medium)
        badge.textColor = color
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.heightAnchor.constraint(equalToConstant: 20).isActive = true
        badge.widthAnchor.constraint(greaterThanOrEqualToConstant: text == "Required" ? 62 : 48).isActive = true
        return badge
    }

    private func itemName(from sender: NSView, prefix: String) -> String? {
        guard let raw = sender.identifier?.rawValue, raw.hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }

    @objc private func valueChanged(_ sender: NSTextField) {
        guard let name = itemName(from: sender, prefix: "configuration-value:") else { return }
        onValueChanged?(name, sender.stringValue)
    }

    @objc private func setupSecret(_ sender: NSButton) {
        guard let name = itemName(from: sender, prefix: "configuration-action:") else { return }
        onSetupSecret?(name)
    }

    @objc private func removeValue(_ sender: NSButton) {
        guard let name = itemName(from: sender, prefix: "configuration-action:") else { return }
        onRemoveValue?(name)
    }
}
