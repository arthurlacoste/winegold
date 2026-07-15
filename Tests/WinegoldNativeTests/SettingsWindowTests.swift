import AppKit
import XCTest
@testable import WinegoldUI

final class SettingsWindowTests: XCTestCase {
    func testCommandWInvokesCloseAction() throws {
        _ = NSApplication.shared
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        var didClose = false
        window.onCloseShortcut = { didClose = true }

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertTrue(didClose)
    }
}
