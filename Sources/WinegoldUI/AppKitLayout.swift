import AppKit

public func verticallyCenteredTextFrame(
    in containerFrame: NSRect,
    textHeight: CGFloat
) -> NSRect {
    NSRect(
        x: containerFrame.minX,
        y: containerFrame.midY - textHeight / 2,
        width: containerFrame.width,
        height: textHeight
    )
}

public final class PillBadgeView: NSView {
    public let label: NSTextField

    public init(title: String, color: NSColor) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 6

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }
}
