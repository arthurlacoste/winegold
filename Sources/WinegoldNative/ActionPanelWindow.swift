import Cocoa
import WinegoldCore

class ActionPanelWindow: NSPanel, NSWindowDelegate {
    private let panelVC: ActionPanelViewController
    private let panelState: PanelState
    private var targetScreen: NSScreen
    private var settingsStore: SettingsStore
    private var isProgrammaticFrameChange = false
    private var canPersistUserResize = false

    init(
        screen: NSScreen,
        files: [URL],
        actions: [Action],
        allActions: [Action],
        history: [RunHistoryItem],
        savedHistory: [RunHistoryItem],
        savedHistoryIds: Set<UUID>,
        settingsStore: SettingsStore,
        onRunAction: @escaping (Action, [URL]) -> Void,
        onToggleSavedRun: @escaping (RunHistoryItem) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        let state = PanelState()
        state.files = files
        state.actions = actions
        state.allActions = allActions
        state.history = history
        state.savedHistory = savedHistory
        state.savedHistoryIds = savedHistoryIds
        self.panelState = state
        self.targetScreen = screen
        self.settingsStore = settingsStore

        let vc = ActionPanelViewController(
            state: state,
            onRunAction: onRunAction,
            onToggleSavedRun: onToggleSavedRun,
            onOpenSettings: onOpenSettings
        )
        self.panelVC = vc

        let visibleFrame = screen.visibleFrame
        let savedWidth = CGFloat(settingsStore.panelWidth)
        let defaultHeight = Int(visibleFrame.height - 40)
        let savedHeight = settingsStore.panelHeight == 0 ? defaultHeight : settingsStore.panelHeight
        let panelSize = ActionPanelWindow.clampedPanelSize(
            width: savedWidth,
            height: CGFloat(savedHeight),
            visibleFrame: visibleFrame
        )
        let frame = NSRect(
            x: visibleFrame.maxX,
            y: visibleFrame.minY + 20,
            width: panelSize.width,
            height: panelSize.height
        )

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "Winegold"
        self.isOpaque = true
        self.backgroundColor = WinegoldTheme.panelBackground(in: nil)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.minSize = NSSize(width: 320, height: 420)
        self.delegate = self

        self.contentViewController = panelVC
        panelVC.view.frame = NSRect(origin: .zero, size: frame.size)
        panelVC.view.autoresizingMask = [.width, .height]
    }

    func update(
        screen: NSScreen,
        files: [URL],
        actions: [Action],
        allActions: [Action],
        history: [RunHistoryItem],
        savedHistory: [RunHistoryItem],
        savedHistoryIds: Set<UUID>
    ) {
        targetScreen = screen
        panelState.files = files
        panelState.actions = actions
        panelState.allActions = allActions
        panelState.history = history
        panelState.savedHistory = savedHistory
        panelState.savedHistoryIds = savedHistoryIds
        panelState.lastResult = nil
        panelState.activeActionId = nil
        panelState.runningActionName = nil
        panelState.runningFiles = []
        panelVC.refresh()
    }

    func updateSavedHistory(_ savedHistory: [RunHistoryItem], savedIds: Set<UUID>) {
        panelState.savedHistory = savedHistory
        panelState.savedHistoryIds = savedIds
        panelVC.refresh()
    }

    private func applyTheme() {
        backgroundColor = WinegoldTheme.panelBackground(in: contentView)
        contentView?.layer?.backgroundColor = WinegoldTheme.panelBackground(in: contentView).cgColor
    }

    func show() {
        canPersistUserResize = false
        applyTheme()
        let visibleFrame = targetScreen.visibleFrame
        let panelSize = ActionPanelWindow.clampedPanelSize(
            width: CGFloat(settingsStore.panelWidth),
            height: CGFloat(settingsStore.panelHeight == 0 ? Int(visibleFrame.height - 40) : settingsStore.panelHeight),
            visibleFrame: visibleFrame
        )
        let targetX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width - 20)
        var frame = self.frame
        frame.origin.x = targetX
        frame.origin.y = max(visibleFrame.minY + 20, visibleFrame.maxY - panelSize.height - 20)
        frame.size = panelSize
        logMsg("[ActionPanelWindow] show visibleFrame=\(NSStringFromRect(visibleFrame)) frame=\(NSStringFromRect(frame))")
        let finalFrame = frame
        var startFrame = finalFrame
        startFrame.origin.x = visibleFrame.maxX + 8
        let shouldSlideIn = !isVisible || self.frame.origin.x >= visibleFrame.maxX - 2

        isProgrammaticFrameChange = true
        self.setFrame(shouldSlideIn ? startFrame : finalFrame, display: true)
        self.makeKeyAndOrderFront(nil)
        self.orderFrontRegardless()
        if shouldSlideIn {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(finalFrame, display: true)
            } completionHandler: { [weak self] in
                self?.isProgrammaticFrameChange = false
            }
        } else {
            isProgrammaticFrameChange = false
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.applyTheme()
            self?.canPersistUserResize = true
        }
    }

    func hide() {
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func showRunResult(result: CommandResult) {
        panelState.runningActionName = nil
        panelState.runningFiles = []
        panelState.lastResult = result
        panelVC.refresh()
    }

    func windowDidResize(_ notification: Notification) {
        guard canPersistUserResize, !isProgrammaticFrameChange else { return }
        let size = frame.size
        settingsStore.panelWidth = Int(size.width.rounded())
        settingsStore.panelHeight = Int(size.height.rounded())
        logMsg("[ActionPanelWindow] saved size width=\(settingsStore.panelWidth) height=\(settingsStore.panelHeight)")
    }

    private static func clampedPanelSize(width: CGFloat, height: CGFloat, visibleFrame: NSRect) -> NSSize {
        let maxWidth = max(320, min(900, visibleFrame.width - 40))
        let maxHeight = max(420, min(1400, visibleFrame.height - 40))
        return NSSize(
            width: max(320, min(maxWidth, width)),
            height: max(420, min(maxHeight, height))
        )
    }
}
