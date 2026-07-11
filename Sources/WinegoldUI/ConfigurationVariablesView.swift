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

        let leftColumn = NSStackView()
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 4
        leftColumn.translatesAutoresizingMaskIntoConstraints = false
        leftColumn.addArrangedSubview(label)
        if item.isRequired {
            leftColumn.addArrangedSubview(makeBadge("Required", color: .systemOrange, identifier: "configuration-required:\(item.name)"))
        }

        let source = NSTextField(labelWithString: item.source)
        source.font = .systemFont(ofSize: 11)
        source.textColor = .tertiaryLabelColor
        source.lineBreakMode = .byTruncatingTail
        source.alignment = .left
        source.identifier = NSUserInterfaceItemIdentifier("configuration-source:\(item.name)")
        source.translatesAutoresizingMaskIntoConstraints = false

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
        action.translatesAutoresizingMaskIntoConstraints = false

        let rightColumn = NSView()
        rightColumn.translatesAutoresizingMaskIntoConstraints = false

        if item.isSecret {
            let secureField = NSSecureTextField(string: item.isConfigured ? "configured" : "")
            secureField.font = .systemFont(ofSize: 12)
            secureField.placeholderString = "Not set"
            secureField.isEditable = false
            secureField.isSelectable = false
            secureField.isBezeled = true
            secureField.drawsBackground = true
            secureField.identifier = NSUserInterfaceItemIdentifier("configuration-value:\(item.name)")
            secureField.translatesAutoresizingMaskIntoConstraints = false

            let secretBadge = makeBadge("Secret", color: .secondaryLabelColor, identifier: "configuration-secret:\(item.name)")
            secretBadge.translatesAutoresizingMaskIntoConstraints = false

            rightColumn.addSubview(secureField)
            rightColumn.addSubview(secretBadge)
            rightColumn.addSubview(source)
            rightColumn.addSubview(action)
            NSLayoutConstraint.activate([
                secretBadge.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
                secretBadge.centerYAnchor.constraint(equalTo: secureField.centerYAnchor),
                secureField.leadingAnchor.constraint(equalTo: secretBadge.trailingAnchor, constant: 8),
                secureField.topAnchor.constraint(equalTo: rightColumn.topAnchor),
                secureField.heightAnchor.constraint(equalToConstant: 26),
                source.leadingAnchor.constraint(equalTo: secureField.trailingAnchor, constant: 10),
                source.centerYAnchor.constraint(equalTo: secureField.centerYAnchor),
                source.widthAnchor.constraint(equalToConstant: 86),
                action.leadingAnchor.constraint(equalTo: source.trailingAnchor, constant: 10),
                action.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
                action.centerYAnchor.constraint(equalTo: secureField.centerYAnchor),
                action.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
                secureField.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor)
            ])
        } else {
            let field = NSTextField(string: item.value)
            field.font = .systemFont(ofSize: 12)
            field.placeholderString = "Value"
            field.identifier = NSUserInterfaceItemIdentifier("configuration-value:\(item.name)")
            field.target = self
            field.action = #selector(valueChanged(_:))
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.translatesAutoresizingMaskIntoConstraints = false

            rightColumn.addSubview(field)
            rightColumn.addSubview(source)
            rightColumn.addSubview(action)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
                field.topAnchor.constraint(equalTo: rightColumn.topAnchor),
                field.heightAnchor.constraint(equalToConstant: 26),
                action.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 10),
                action.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
                action.centerYAnchor.constraint(equalTo: field.centerYAnchor),
                action.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
                source.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 2),
                source.trailingAnchor.constraint(lessThanOrEqualTo: field.trailingAnchor),
                source.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 3),
                source.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor)
            ])
        }

        row.addSubview(leftColumn)
        row.addSubview(rightColumn)
        NSLayoutConstraint.activate([
            leftColumn.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            leftColumn.topAnchor.constraint(equalTo: row.topAnchor, constant: 3),
            leftColumn.widthAnchor.constraint(equalToConstant: 100),
            rightColumn.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 110),
            rightColumn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            rightColumn.topAnchor.constraint(equalTo: row.topAnchor),
            rightColumn.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: item.isSecret || item.isRequired ? 46 : 44)
        ])
        return row
    }

    private func makeBadge(_ text: String, color: NSColor, identifier: String) -> NSView {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.identifier = NSUserInterfaceItemIdentifier(identifier)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = color
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 20),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: text == "Required" ? 62 : 48)
        ])
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
