import Cocoa

enum WinegoldTheme {
    static func isDark(in view: NSView?) -> Bool {
        let appearance = view?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func panelBackground(in view: NSView?) -> NSColor {
        isDark(in: view) ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor(calibratedWhite: 0.955, alpha: 1)
    }

    static func cardBackground(in view: NSView?, emphasized: Bool = false, disabled: Bool = false) -> NSColor {
        if isDark(in: view) {
            if emphasized { return NSColor.controlAccentColor.withAlphaComponent(0.18) }
            if disabled { return NSColor(calibratedWhite: 0.16, alpha: 0.75) }
            return NSColor(calibratedWhite: 0.13, alpha: 1)
        }
        if emphasized { return NSColor.controlAccentColor.withAlphaComponent(0.09) }
        if disabled { return NSColor.controlBackgroundColor.withAlphaComponent(0.5) }
        return NSColor(calibratedWhite: 0.992, alpha: 1)
    }

    static func rowBackground(in view: NSView?, emphasized: Bool = false) -> NSColor {
        if isDark(in: view) {
            return emphasized ? NSColor(calibratedWhite: 0.22, alpha: 1) : NSColor(calibratedWhite: 0.15, alpha: 1)
        }
        return emphasized ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.clear
    }

    static func border(in view: NSView?, emphasized: Bool = false) -> NSColor {
        if emphasized { return .controlAccentColor.withAlphaComponent(0.55) }
        return isDark(in: view)
            ? NSColor(calibratedWhite: 0.34, alpha: 0.42)
            : NSColor(calibratedWhite: 0.62, alpha: 0.32)
    }

    static func separator(in view: NSView?) -> NSColor {
        isDark(in: view)
            ? NSColor(calibratedWhite: 0.36, alpha: 0.34)
            : NSColor(calibratedWhite: 0.72, alpha: 0.34)
    }

    static func statusBackground(in view: NSView?) -> NSColor {
        isDark(in: view) ? NSColor(calibratedWhite: 0.14, alpha: 1) : .controlBackgroundColor
    }
}
