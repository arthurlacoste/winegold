import Cocoa
import WinegoldCore

class ActionCardView: NSView {
    override var isFlipped: Bool { true }

    private let action: Action
    private let status: ActionValidationStatus
    private let isActive: Bool
    private let onDrop: ([URL]) -> Void

    private var isPressed = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private let leadingIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let runCard = NSView()
    private let runIcon = NSImageView()

    init(action: Action, status: ActionValidationStatus, isActive: Bool, onDrop: @escaping ([URL]) -> Void) {
        self.action = action
        self.status = status
        self.isActive = isActive
        self.onDrop = onDrop
        super.init(frame: NSRect(x: 0, y: 0, width: 312, height: 64))
        wantsLayer = true
        layer?.cornerRadius = 8
        registerForDraggedTypes(DragFileReader.supportedTypes)
        setup()
        applyVisualState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setup() {
        switch status {
        case .available:
            layer?.backgroundColor = WinegoldTheme.cardBackground(in: self).cgColor
            configureIcon(systemName: iconName, tint: .controlTextColor)
            configureTitle(action.name, weight: .bold, color: .controlTextColor)
            let exts = action.acceptedExtensions.contains("*") ? "all files" : action.acceptedExtensions.joined(separator: ", ")
            configureSubtitle(exts)
            configureRunCard()
        case .missingDependency(let reason), .configError(let reason):
            layer?.backgroundColor = WinegoldTheme.cardBackground(in: self, disabled: true).cgColor
            let icon = status.isMissing ? "exclamationmark.triangle" : "xmark.octagon"
            configureIcon(systemName: icon, tint: .secondaryLabelColor)
            configureTitle(action.name, weight: .regular, color: .secondaryLabelColor)
            configureSubtitle(reason)
            runCard.isHidden = true
            runIcon.isHidden = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard caseAvailable else { return }
        isHovered = true
        applyVisualState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        applyVisualState(animated: true)
    }

    override func layout() {
        super.layout()
        let rightInset: CGFloat = 12
        let leftTextX: CGFloat = 48
        let buttonSize = NSSize(width: 36, height: 32)
        let buttonX = max(leftTextX + 120, bounds.width - rightInset - buttonSize.width)
        let textRightPadding: CGFloat = caseAvailable ? 58 : 12
        let textWidth = max(80, bounds.width - leftTextX - textRightPadding)

        leadingIcon.frame = NSRect(x: 12, y: 20, width: 24, height: 24)
        titleLabel.frame = NSRect(x: leftTextX, y: 14, width: textWidth, height: 20)
        subtitleLabel.frame = NSRect(x: leftTextX, y: 36, width: textWidth, height: 16)
        runCard.frame = NSRect(x: buttonX, y: 16, width: buttonSize.width, height: buttonSize.height)
        runIcon.frame = NSRect(x: buttonX + 12, y: 24, width: 14, height: 16)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if caseAvailable {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard caseAvailable else { return }
        isPressed = true
        applyVisualState(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard caseAvailable else { return }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else {
            isPressed = false
            applyVisualState(animated: true)
            return
        }
        logMsg("[ActionCardView] clicked action: \(action.name)")
        // Keep pressed visual state until the panel refreshes into loading/result.
        onDrop([])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        logMsg("[ActionCardView] draggingEntered for: \(action.name)")
        guard caseAvailable else { return [] }
        isHovered = true
        applyVisualState(animated: true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard caseAvailable else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        logMsg("[ActionCardView] draggingExited for: \(action.name)")
        isHovered = false
        isPressed = false
        applyVisualState(animated: true)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isPressed = true
        applyVisualState(animated: true)
        logMsg("[ActionCardView] performDragOperation for: \(action.name)")
        let files = DragFileReader.urls(from: sender)
        logMsg("[ActionCardView] files from pasteboard: \(files.count)")
        onDrop(files)
        return true
    }


    private func applyVisualState(animated: Bool) {
        let isEmphasized = isActive || isPressed || isHovered
        let borderWidth: CGFloat = isEmphasized ? 2 : 1
        let borderColor: NSColor
        let backgroundColor: NSColor

        if isEmphasized && caseAvailable {
            borderColor = .controlAccentColor
            backgroundColor = WinegoldTheme.cardBackground(in: self, emphasized: true)
        } else {
            borderColor = WinegoldTheme.border(in: self)
            backgroundColor = caseAvailable ? WinegoldTheme.cardBackground(in: self) : WinegoldTheme.cardBackground(in: self, disabled: true)
        }

        let changes = {
            self.layer?.borderWidth = borderWidth
            self.layer?.borderColor = borderColor.cgColor
            self.layer?.backgroundColor = backgroundColor.cgColor
            if self.caseAvailable {
                self.runCard.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.18 : 0.12).cgColor
                self.runCard.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.45 : 0.25).cgColor
            }
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            self.layer?.removeAllAnimations()
            self.runCard.layer?.removeAllAnimations()
            changes()
        }
    }

    private func configureIcon(systemName: String, tint: NSColor) {
        leadingIcon.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        leadingIcon.contentTintColor = tint
        addSubview(leadingIcon)
    }

    private func configureTitle(_ text: String, weight: NSFont.Weight, color: NSColor) {
        titleLabel.stringValue = text
        titleLabel.font = .systemFont(ofSize: 13, weight: weight)
        titleLabel.textColor = color
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
    }

    private func configureSubtitle(_ text: String) {
        subtitleLabel.stringValue = text
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)
    }

    private func configureRunCard() {
        runCard.wantsLayer = true
        runCard.layer?.cornerRadius = 10
        runCard.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        runCard.layer?.borderWidth = 1
        runCard.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        addSubview(runCard)

        runIcon.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run")
        runIcon.contentTintColor = .controlAccentColor
        addSubview(runIcon)
    }

    private var caseAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    private var iconName: String {
        if let custom = action.iconName { return custom }
        if action.executablePath == "/bin/echo" { return "text.bubble" }
        if action.executablePath == "/usr/bin/open" { return "folder" }
        return "gearshape"
    }
}

extension ActionValidationStatus {
    var isMissing: Bool {
        if case .missingDependency = self { return true }
        return false
    }
}
