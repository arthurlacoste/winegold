import Cocoa

class ScreenEdgeService {
    private var edgeWindows: [EdgeCatcherWindow] = []
    private let onDragEnter: ([URL], NSScreen) -> Void

    init(onDragEnter: @escaping ([URL], NSScreen) -> Void) {
        self.onDragEnter = onDragEnter
        setupWindows()
        setupScreenChangeObserver()
    }

    deinit {
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

}
