import Cocoa
import WinegoldCore

class EdgeCatcherWindow: NSPanel {
    static let edgeWidth: CGFloat = 12

    init(screen: NSScreen, side: PanelSide) {
        let frame = EdgeCatcherWindow.edgeFrame(for: screen, side: side)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        self.alphaValue = 0.01
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        let view = EdgeCatcherView(frame: NSRect(origin: .zero, size: frame.size))
        view.onDragEnter = { [weak self] in
            self?.onDragEnter?($0)
        }
        self.contentView = view
    }

    var onDragEnter: (([URL]) -> Void)?

    static func edgeFrame(for screen: NSScreen, side: PanelSide) -> CGRect {
        let visibleFrame = screen.visibleFrame
        return NSRect(
            x: side == .left ? visibleFrame.minX : visibleFrame.maxX - edgeWidth,
            y: visibleFrame.minY,
            width: edgeWidth,
            height: visibleFrame.height
        )
    }
}

class EdgeCatcherView: NSView {
    var onDragEnter: (([URL]) -> Void)?
    private var hasTriggeredCurrentDrag = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        registerForDraggedTypes(DragFileReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        logMsg("[EdgeCatcher] draggingEntered")
        triggerPanelIfPossible(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        triggerPanelIfPossible(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        logMsg("[EdgeCatcher] draggingExited")
        hasTriggeredCurrentDrag = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        logMsg("[EdgeCatcher] performDragOperation")
        hasTriggeredCurrentDrag = false
        return true
    }

    private func triggerPanelIfPossible(_ sender: NSDraggingInfo) {
        guard !hasTriggeredCurrentDrag else { return }

        let files = draggedFiles(from: sender)
        logMsg("[EdgeCatcher] files: \(files.count)")
        guard !files.isEmpty else { return }

        hasTriggeredCurrentDrag = true
        logMsg("[EdgeCatcher] first file: \(files.first?.lastPathComponent ?? "")")
        onDragEnter?(files)
    }

    private func draggedFiles(from sender: NSDraggingInfo) -> [URL] {
        let urls = DragFileReader.urls(from: sender)
        let itemCount = sender.draggingPasteboard.pasteboardItems?.count ?? 0
        logMsg("[EdgeCatcher] pasteboard items: \(itemCount), urls: \(urls.count)")
        return urls
    }
}
