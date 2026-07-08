import Cocoa

enum ScreenResolver {
    static func screen(containing point: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.contains(point) || screen.visibleFrame.contains(point)
        }
    }

    static func currentInteractionScreen() -> NSScreen? {
        screen(containing: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func describeScreens() -> String {
        NSScreen.screens.enumerated().map { index, screen in
            "#\(index) frame=\(NSStringFromRect(screen.frame)) visible=\(NSStringFromRect(screen.visibleFrame))"
        }.joined(separator: " | ")
    }
}
