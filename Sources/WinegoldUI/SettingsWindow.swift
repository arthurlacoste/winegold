import AppKit

public final class SettingsWindow: NSWindow {
    public var onSaveShortcut: (() -> Void)?
    var onCloseShortcut: (() -> Void)?

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "s":
                onSaveShortcut?()
                return true
            case "w":
                if let onCloseShortcut {
                    onCloseShortcut()
                } else {
                    performClose(nil)
                }
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
