import Cocoa
import WinegoldCore

class ActionCardView: NSView {
    override var isFlipped: Bool { true }

    private let action: Action
    private let status: ActionValidationStatus
    private let isActive: Bool
    private let onDrop: ([URL]) -> Void
    private let onToggleFavorite: (Action) -> Void
    private let onMoveBefore: (Action, Action) -> Void

    private var isPressed = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private let leadingIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let favoriteButton = NSButton()
    private let runCard = NSView()
    private let runIcon = NSImageView()

    private static let actionDragType = NSPasteboard.PasteboardType("com.winegold.action-id")

    init(
        action: Action,
        status: ActionValidationStatus,
        isActive: Bool,
        onDrop: @escaping ([URL]) -> Void,
        onToggleFavorite: @escaping (Action) -> Void,
        onMoveBefore: @escaping (Action, Action) -> Void
    ) {
        self.action = action
        self.status = status
        self.isActive = isActive
        self.onDrop = onDrop
        self.onToggleFavorite = onToggleFavorite
        self.onMoveBefore = onMoveBefore
        super.init(frame: NSRect(x: 0, y: 0, width: 312, height: 64))
        wantsLayer = true
        layer?.cornerRadius = 8
        registerForDraggedTypes(DragFileReader.supportedTypes + [Self.actionDragType])
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
            configureFavoriteButton()
            configureRunCard()
        case .missingDependency(let reason), .configError(let reason):
            layer?.backgroundColor = WinegoldTheme.cardBackground(in: self, disabled: true).cgColor
            let icon = status.isMissing ? "exclamationmark.triangle" : "xmark.octagon"
            configureIcon(systemName: icon, tint: .secondaryLabelColor)
            configureTitle(action.name, weight: .regular, color: .secondaryLabelColor)
            configureSubtitle(reason)
            favoriteButton.isHidden = true
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
        let textRightPadding: CGFloat = caseAvailable ? 88 : 12
        let textWidth = max(80, bounds.width - leftTextX - textRightPadding)

        leadingIcon.frame = NSRect(x: 12, y: 20, width: 24, height: 24)
        titleLabel.frame = NSRect(x: leftTextX, y: 14, width: textWidth, height: 20)
        subtitleLabel.frame = NSRect(x: leftTextX, y: 36, width: textWidth, height: 16)
        favoriteButton.frame = NSRect(x: buttonX - 30, y: 18, width: 24, height: 24)
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

    override func mouseDragged(with event: NSEvent) {
        guard caseAvailable else { return }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(action.id.uuidString, forType: Self.actionDragType)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            image.addRepresentation(rep)
        }
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
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
        if sender.draggingPasteboard.string(forType: Self.actionDragType) != nil { return .move }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard caseAvailable else { return [] }
        if sender.draggingPasteboard.string(forType: Self.actionDragType) != nil { return .move }
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
        if let sourceID = sender.draggingPasteboard.string(forType: Self.actionDragType),
           let uuid = UUID(uuidString: sourceID), uuid != action.id {
            onMoveBefore(Action(id: uuid, name: "", executablePath: "/bin/echo"), action)
            return true
        }
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

    private func configureFavoriteButton() {
        favoriteButton.image = NSImage(systemSymbolName: action.isFavorite ? "star.fill" : "star", accessibilityDescription: "Favorite")
        favoriteButton.contentTintColor = action.isFavorite ? .systemYellow : .tertiaryLabelColor
        favoriteButton.isBordered = false
        favoriteButton.target = self
        favoriteButton.action = #selector(favoriteClicked)
        addSubview(favoriteButton)
    }

    @objc private func favoriteClicked() {
        onToggleFavorite(action)
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

extension ActionCardView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}

extension ActionValidationStatus {
    var isMissing: Bool {
        if case .missingDependency = self { return true }
        return false
    }
}
