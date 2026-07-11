import AppKit
import XCTest
@testable import WinegoldUI

@MainActor
final class HistoryActionButtonStyleTests: XCTestCase {
    func testEyeAndReplayCardsMatchPlayShapeWithoutBorders() {
        for color in [HistoryActionButtonStyle.eyeBackgroundColor, NSColor.controlAccentColor] {
            let card = NSView()
            HistoryActionButtonStyle.configureCard(card, backgroundColor: color.withAlphaComponent(0.10))

            XCTAssertEqual(HistoryActionButtonStyle.size, NSSize(width: 34, height: 30))
            XCTAssertEqual(card.layer?.cornerRadius, 10)
            XCTAssertEqual(card.layer?.borderWidth, 0)
        }
    }

    func testEyeUsesPastelIndigoPalette() {
        XCTAssertEqual(HistoryActionButtonStyle.eyeTintColor, .systemIndigo)
        XCTAssertEqual(
            HistoryActionButtonStyle.eyeBackgroundColor.cgColor,
            NSColor.systemIndigo.withAlphaComponent(0.12).cgColor
        )
    }

    func testBookmarkHasNoBackgroundOrBorder() {
        let card = NSView()
        HistoryActionButtonStyle.configureCard(card, backgroundColor: nil)

        XCTAssertEqual(card.layer?.backgroundColor, NSColor.clear.cgColor)
        XCTAssertEqual(card.layer?.borderWidth, 0)
    }

    func testIconsUseCenteredFixedSymbolRendering() {
        for symbol in ["eye", "arrow.clockwise", "bookmark"] {
            let icon = NSImageView()
            HistoryActionButtonStyle.configureIcon(
                icon,
                symbolName: symbol,
                accessibilityDescription: symbol,
                tintColor: .controlAccentColor
            )

            XCTAssertNotNil(icon.image)
            XCTAssertEqual(icon.imageAlignment, .alignCenter)
            XCTAssertEqual(icon.imageScaling, .scaleNone)
        }
    }

    func testButtonStylesRenderSnapshot() throws {
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 142, height: 50))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let definitions: [(String, NSColor, NSColor?)] = [
            ("bookmark", .systemYellow, nil),
            ("eye", HistoryActionButtonStyle.eyeTintColor, HistoryActionButtonStyle.eyeBackgroundColor),
            ("arrow.clockwise", .controlAccentColor, NSColor.controlAccentColor.withAlphaComponent(0.12))
        ]

        for (index, definition) in definitions.enumerated() {
            let x = CGFloat(8 + index * 42)
            let card = NSView(frame: NSRect(origin: NSPoint(x: x, y: 10), size: HistoryActionButtonStyle.size))
            HistoryActionButtonStyle.configureCard(card, backgroundColor: definition.2)
            canvas.addSubview(card)
            let icon = NSImageView(frame: card.frame)
            HistoryActionButtonStyle.configureIcon(
                icon,
                symbolName: definition.0,
                accessibilityDescription: definition.0,
                tintColor: definition.1
            )
            canvas.addSubview(icon)
        }

        let representation = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/winegold-history-buttons-test.png"))
        XCTAssertGreaterThan(png.count, 2_000)
    }
}
