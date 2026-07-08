import Cocoa

class ScreenEdgeService {
    private var edgeWindows: [EdgeCatcherWindow] = []
    private var dragMonitor: Any?
    private var lastFallbackOpenAt = Date.distantPast
    private let onDragEnter: ([URL], NSScreen) -> Void

    init(onDragEnter: @escaping ([URL], NSScreen) -> Void) {
        self.onDragEnter = onDragEnter
        setupWindows()
        setupFallbackDragMonitor()
        setupScreenChangeObserver()
    }

    deinit {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupWindows() {
        edgeWindows.forEach { $0.close() }
        edgeWindows.removeAll()

        logMsg("[ScreenEdgeService] screens \(ScreenResolver.describeScreens())")

        for screen in NSScreen.screens {
            let window = EdgeCatcherWindow(screen: screen)
            window.onDragEnter = { [weak self, weak screen] files in
                guard let self, let screen else { return }
                self.onDragEnter(files, screen)
            }
            window.orderFrontRegardless()
            edgeWindows.append(window)
            logMsg("[ScreenEdgeService] edge frame=\(NSStringFromRect(window.frame))")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshWindowFrames()
        }
    }

    private func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensDidChange() {
        setupWindows()
    }

    private func refreshWindowFrames() {
        for window in edgeWindows {
            guard let screen = window.screen ?? ScreenResolver.currentInteractionScreen() else { continue }
            window.setFrame(EdgeCatcherWindow.edgeFrame(for: screen), display: true)
            window.orderFrontRegardless()
            logMsg("[ScreenEdgeService] refreshed edge frame=\(NSStringFromRect(window.frame))")
        }
    }

    private func setupFallbackDragMonitor() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.openPanelWhenDraggingNearRightEdge(event)
        }
    }

    private func openPanelWhenDraggingNearRightEdge(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        guard let screen = ScreenResolver.screen(containing: point) else { return }
        let frame = screen.visibleFrame
        guard frame.contains(point) else { return }
        guard point.x >= frame.maxX - 24 else { return }
        guard Date().timeIntervalSince(lastFallbackOpenAt) > 0.6 else { return }

        lastFallbackOpenAt = Date()
        logMsg("[ScreenEdgeService] fallback drag edge hit point=\(NSStringFromPoint(point)) screen=\(NSStringFromRect(screen.visibleFrame))")
        DispatchQueue.main.async { [onDragEnter] in
            onDragEnter([], screen)
        }
    }
}
