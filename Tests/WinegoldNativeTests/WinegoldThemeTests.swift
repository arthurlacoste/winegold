import AppKit
import XCTest
@testable import WinegoldUI

final class WinegoldThemeTests: XCTestCase {
    func testSemanticPanelAndCardColorsKeepReadableLabelContrast() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let view = NSView()
            view.appearance = appearance

            XCTAssertGreaterThanOrEqual(
                contrastRatio(.labelColor, WinegoldTheme.panelBackground(in: view), appearance: appearance),
                4.5
            )
            XCTAssertGreaterThanOrEqual(
                contrastRatio(.labelColor, WinegoldTheme.cardBackground(in: view), appearance: appearance),
                4.5
            )
        }
    }

    func testThemeDetectsBothSystemAppearances() throws {
        let view = NSView()
        view.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        XCTAssertFalse(WinegoldTheme.isDark(in: view))

        view.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        XCTAssertTrue(WinegoldTheme.isDark(in: view))
    }

    func testLayerColorResolvesUsingViewEffectiveAppearance() throws {
        let lightView = NSView()
        lightView.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkView = NSView()
        darkView.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        let light = WinegoldTheme.layerColor(.windowBackgroundColor, in: lightView)
        let dark = WinegoldTheme.layerColor(.windowBackgroundColor, in: darkView)

        XCTAssertNotEqual(light, dark)
        XCTAssertEqual(light, resolvedCGColor(.windowBackgroundColor, appearance: lightView.effectiveAppearance))
        XCTAssertEqual(dark, resolvedCGColor(.windowBackgroundColor, appearance: darkView.effectiveAppearance))
    }

    func testLayerColorAppliesAlphaInsideViewAppearance() throws {
        let lightView = NSView()
        lightView.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkView = NSView()
        darkView.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        let light = WinegoldTheme.layerColor(.windowBackgroundColor, alpha: 0.96, in: lightView)
        let dark = WinegoldTheme.layerColor(.windowBackgroundColor, alpha: 0.96, in: darkView)

        XCTAssertNotEqual(light, dark)
        XCTAssertEqual(light.alpha, 0.96, accuracy: 0.001)
        XCTAssertEqual(dark.alpha, 0.96, accuracy: 0.001)
    }

    private func contrastRatio(_ foreground: NSColor, _ background: NSColor, appearance: NSAppearance) -> CGFloat {
        let foregroundLuminance = luminance(foreground, appearance: appearance)
        let backgroundLuminance = luminance(background, appearance: appearance)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    private func luminance(_ color: NSColor, appearance: NSAppearance) -> CGFloat {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(resolved.redComponent)
            + 0.7152 * channel(resolved.greenComponent)
            + 0.0722 * channel(resolved.blueComponent)
    }

    private func resolvedCGColor(_ color: NSColor, appearance: NSAppearance) -> CGColor {
        var resolved = color.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }
}
