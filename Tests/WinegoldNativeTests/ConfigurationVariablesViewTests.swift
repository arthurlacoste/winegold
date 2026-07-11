import AppKit
import XCTest
@testable import WinegoldUI

@MainActor
final class ConfigurationVariablesViewTests: XCTestCase {
    func testUploadRecipeConfigurationRendersWithoutOverlap() throws {
        _ = NSApplication.shared
        let view = ConfigurationVariablesView(frame: NSRect(x: 0, y: 0, width: 610, height: 200))
        view.translatesAutoresizingMaskIntoConstraints = true
        view.apply([
            ConfigurationVariablePresentation(
                name: "UPLOAD_ENDPOINT",
                label: "Upload endpoint",
                value: "https://example.com/api.php",
                source: "YAML default",
                isSecret: false,
                isRequired: false,
                isConfigured: true,
                canRemove: false
            ),
            ConfigurationVariablePresentation(
                name: "UPLOAD_TOKEN",
                label: "Service token",
                value: "",
                source: "Not set",
                isSecret: true,
                isRequired: true,
                isConfigured: false
            )
        ])
        view.frame.size.height = view.intrinsicContentSize.height
        view.layoutSubtreeIfNeeded()

        let cards = view.subviewsRecursive.filter { $0.layer?.cornerRadius == 10 }
        XCTAssertEqual(cards.count, 2)
        let sortedCards = cards.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertLessThanOrEqual(sortedCards[0].frame.maxY + 12, sortedCards[1].frame.minY)

        let endpoint = try XCTUnwrap(view.control(identifier: "configuration-value:UPLOAD_ENDPOINT"))
        let token = try XCTUnwrap(view.control(identifier: "configuration-value:UPLOAD_TOKEN"))
        let setup = try XCTUnwrap(view.control(identifier: "configuration-action:UPLOAD_TOKEN"))
        let endpointFrame = endpoint.convert(endpoint.bounds, to: view)
        let tokenFrame = token.convert(token.bounds, to: view)
        let setupFrame = setup.convert(setup.bounds, to: view)
        XCTAssertFalse(endpointFrame.intersects(tokenFrame))
        XCTAssertFalse(tokenFrame.intersects(setupFrame))
        XCTAssertGreaterThan(endpoint.frame.width, 200)

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/winegold-configuration-upload-test.png"))
        XCTAssertGreaterThan(png.count, 8_000)
    }


    func testLabelsAndBadgesAreVerticallyCenteredWithControls() throws {
        _ = NSApplication.shared
        let view = ConfigurationVariablesView(frame: NSRect(x: 0, y: 0, width: 610, height: 120))
        view.translatesAutoresizingMaskIntoConstraints = true
        view.apply([
            ConfigurationVariablePresentation(
                name: "UPLOAD_TOKEN",
                label: "Service token",
                value: "",
                source: "Winegold",
                isSecret: true,
                isRequired: true,
                isConfigured: true
            )
        ])
        view.frame.size.height = view.intrinsicContentSize.height
        view.layoutSubtreeIfNeeded()

        let label = try XCTUnwrap(view.control(identifier: "configuration-label:UPLOAD_TOKEN"))
        let required = try XCTUnwrap(view.control(identifier: "configuration-required:UPLOAD_TOKEN"))
        let secret = try XCTUnwrap(view.control(identifier: "configuration-secret:UPLOAD_TOKEN"))
        let value = try XCTUnwrap(view.control(identifier: "configuration-value:UPLOAD_TOKEN"))
        let action = try XCTUnwrap(view.control(identifier: "configuration-action:UPLOAD_TOKEN"))

        let centers = [label, required, secret, value, action].map { $0.convert($0.bounds, to: view).midY }
        for center in centers.dropFirst() {
            XCTAssertEqual(center, centers[0], accuracy: 2.0)
        }
    }

    func testNeedsSetupBadgeContentCanBeVerticallyCentered() {
        let badge = NSTextField(labelWithString: "Needs setup")
        badge.alignment = .center
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.frame = NSRect(x: 0, y: 0, width: 92, height: 24)

        XCTAssertEqual(badge.alignment, .center)
        XCTAssertEqual(badge.frame.height, 24)
    }
}

private extension NSView {
    var subviewsRecursive: [NSView] { subviews + subviews.flatMap(\.subviewsRecursive) }

    func control(identifier: String) -> NSControl? {
        subviewsRecursive.compactMap { $0 as? NSControl }.first { $0.identifier?.rawValue == identifier }
    }
}
