import AppKit

public enum WinegoldTheme {
    public static func layerColor(_ color: NSColor, alpha: CGFloat? = nil, in view: NSView?) -> CGColor {
        let appearance = view?.effectiveAppearance ?? NSApp.effectiveAppearance
        var resolved = color.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = (alpha.map { color.withAlphaComponent($0) } ?? color).cgColor
        }
        return resolved
    }

    public static func isDark(in view: NSView?) -> Bool {
        let appearance = view?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    public static func panelBackground(in view: NSView?) -> NSColor {
        .windowBackgroundColor
    }

    public static func cardBackground(in view: NSView?, emphasized: Bool = false, disabled: Bool = false) -> NSColor {
        if emphasized {
            return NSColor.selectedContentBackgroundColor.withAlphaComponent(isDark(in: view) ? 0.22 : 0.10)
        }
        if disabled { return NSColor.controlBackgroundColor.withAlphaComponent(0.5) }
        return .controlBackgroundColor
    }

    public static func rowBackground(in view: NSView?, emphasized: Bool = false) -> NSColor {
        emphasized ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12) : .controlBackgroundColor
    }

    public static func border(in view: NSView?, emphasized: Bool = false) -> NSColor {
        if emphasized { return .controlAccentColor.withAlphaComponent(0.55) }
        return .separatorColor
    }

    public static func separator(in view: NSView?) -> NSColor {
        .separatorColor
    }

    public static func statusBackground(in view: NSView?) -> NSColor {
        .controlBackgroundColor
    }
}
