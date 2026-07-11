import AppKit

public enum HistoryActionButtonStyle {
    public static let size = NSSize(width: 34, height: 30)
    public static let spacing: CGFloat = 8
    public static let eyeTintColor = NSColor.systemIndigo
    public static let eyeBackgroundColor = NSColor.systemIndigo.withAlphaComponent(0.12)

    public static func configureCard(_ card: NSView, backgroundColor: NSColor?) {
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = (backgroundColor ?? .clear).cgColor
        card.layer?.borderWidth = 0
        card.layer?.borderColor = NSColor.clear.cgColor
    }

    public static func configureIcon(
        _ icon: NSImageView,
        symbolName: String,
        accessibilityDescription: String,
        tintColor: NSColor
    ) {
        icon.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        icon.imageAlignment = .alignCenter
        icon.imageScaling = .scaleNone
        icon.contentTintColor = tintColor
    }
}
