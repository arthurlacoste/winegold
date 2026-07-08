import Cocoa
import WinegoldCore

class ActionPanelWindow: NSPanel, NSWindowDelegate {
    private let panelVC: ActionPanelViewController
    private let panelState: PanelState
    private var targetScreen: NSScreen
    private var settingsStore: SettingsStore
    private var isProgrammaticFrameChange = false
    private var canPersistUserResize = false
    private var actionTriggeredSinceShow = false
    private var autoHideTimer: Timer?
    private var pendingAutoHideWorkItem: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private var hideAfterSuccessWorkItem: DispatchWorkItem?
    private var successHoverTimer: Timer?
    private var isAnimatingOut = false
    private let compactFrameHeight: CGFloat = 132

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
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Winegold"
        self.isOpaque = true
        self.alphaValue = 1
        self.backgroundColor = WinegoldTheme.panelBackground(in: nil)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hasShadow = true
        self.hidesOnDeactivate = false
        self.minSize = NSSize(width: 320, height: compactFrameHeight)
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
        panelState.isCompact = false
        actionTriggeredSinceShow = false
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()
        panelVC.refresh()
    }

    func markActionTriggered() {
        actionTriggeredSinceShow = true
        cancelPendingAutoHide()
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()
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
        isAnimatingOut = false
        actionTriggeredSinceShow = false
        panelState.isCompact = false
        cancelPendingAutoHide()
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()
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
            self?.startAutoHideMonitor()
            self?.startOutsideClickMonitor()
        }
    }

    func hide() {
        animateOutToRight()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" {
            animateOutToRight()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        animateOutToRight()
        return false
    }



    private var hasRunningAction: Bool {
        panelState.runningActionName != nil || !panelState.runningFiles.isEmpty
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleGlobalMouseDown()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func handleGlobalMouseDown() {
        guard isVisible, !isAnimatingOut else { return }
        let point = NSEvent.mouseLocation
        guard !frame.insetBy(dx: -2, dy: -2).contains(point) else { return }

        if hasRunningAction, !panelState.isCompact {
            collapseToCompactStatus()
        } else if !hasRunningAction {
            animateOutToRight()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, !isAnimatingOut else { return }
        if hasRunningAction, !panelState.isCompact {
            collapseToCompactStatus()
        } else if !hasRunningAction {
            animateOutToRight()
        }
    }

    private func collapseToCompactStatus() {
        guard isVisible, !isAnimatingOut else { return }
        logMsg("[ActionPanelWindow] compact running status")
        panelState.isCompact = true
        panelVC.refresh()
        animateHeight(to: compactFrameHeight)
    }

    private func expandFromCompactForError() {
        guard isVisible else { return }
        panelState.isCompact = false
        panelVC.refresh()
        let visibleFrame = currentVisibleFrame()
        let targetHeight = CGFloat(settingsStore.panelHeight == 0 ? Int(visibleFrame.height - 40) : settingsStore.panelHeight)
        let size = ActionPanelWindow.clampedPanelSize(width: frame.width, height: targetHeight, visibleFrame: visibleFrame)
        animateHeight(to: size.height)
    }

    private func animateHeight(to targetHeight: CGFloat, completion: (() -> Void)? = nil) {
        let visibleFrame = currentVisibleFrame()
        var newFrame = frame
        let topY = frame.maxY
        newFrame.size.height = targetHeight
        newFrame.origin.y = topY - targetHeight
        newFrame.origin.y = max(visibleFrame.minY + 20, min(newFrame.origin.y, visibleFrame.maxY - targetHeight - 20))
        isProgrammaticFrameChange = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(newFrame, display: true)
        } completionHandler: { [weak self] in
            self?.isProgrammaticFrameChange = false
            completion?()
        }
    }

    private func scheduleHideAfterSuccess() {
        cancelHideAfterSuccess()
        startSuccessHoverMonitor()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideAfterSuccessWorkItem = nil
            self.stopSuccessHoverMonitor()
            self.animateOutToRight()
        }
        hideAfterSuccessWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: workItem)
    }

    private func cancelHideAfterSuccess() {
        hideAfterSuccessWorkItem?.cancel()
        hideAfterSuccessWorkItem = nil
    }

    private func startSuccessHoverMonitor() {
        stopSuccessHoverMonitor()
        successHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.checkSuccessHover()
        }
    }

    private func stopSuccessHoverMonitor() {
        successHoverTimer?.invalidate()
        successHoverTimer = nil
    }

    private func checkSuccessHover() {
        guard isVisible,
              !isAnimatingOut,
              panelState.isCompact,
              panelState.lastResult?.status == .success else { return }

        if frame.insetBy(dx: -20, dy: -20).contains(NSEvent.mouseLocation) {
            reopenAfterSuccessHover()
        }
    }

    private func reopenAfterSuccessHover() {
        logMsg("[ActionPanelWindow] reopen after success hover")
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()
        panelState.isCompact = false
        actionTriggeredSinceShow = false
        panelVC.refresh()

        let visibleFrame = currentVisibleFrame()
        let targetHeight = CGFloat(settingsStore.panelHeight == 0 ? Int(visibleFrame.height - 40) : settingsStore.panelHeight)
        let size = ActionPanelWindow.clampedPanelSize(width: frame.width, height: targetHeight, visibleFrame: visibleFrame)
        animateHeight(to: size.height)
    }

    private func startAutoHideMonitor() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.checkAutoHideMousePosition()
        }
    }

    private func stopAutoHideMonitor() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        cancelPendingAutoHide()
    }

    private func checkAutoHideMousePosition() {
        guard isVisible, !isAnimatingOut, !actionTriggeredSinceShow else {
            cancelPendingAutoHide()
            return
        }

        let expandedFrame = frame.insetBy(dx: -20, dy: -20)
        if expandedFrame.contains(NSEvent.mouseLocation) {
            cancelPendingAutoHide()
        } else {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        guard pendingAutoHideWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingAutoHideWorkItem = nil
            guard self.isVisible, !self.actionTriggeredSinceShow else { return }
            let expandedFrame = self.frame.insetBy(dx: -20, dy: -20)
            guard !expandedFrame.contains(NSEvent.mouseLocation) else { return }
            self.animateOutToRight()
        }
        pendingAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func cancelPendingAutoHide() {
        pendingAutoHideWorkItem?.cancel()
        pendingAutoHideWorkItem = nil
    }


    private func currentVisibleFrame() -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen.visibleFrame
        }

        let overlapping = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).width * lhs.frame.intersection(frame).height <
            rhs.frame.intersection(frame).width * rhs.frame.intersection(frame).height
        }
        return overlapping?.visibleFrame ?? targetScreen.visibleFrame
    }

    private func animateOutToRight() {
        guard isVisible, !isAnimatingOut else { return }
        isAnimatingOut = true
        stopAutoHideMonitor()
        stopOutsideClickMonitor()
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()

        let visibleFrame = currentVisibleFrame()
        var finalFrame = frame
        finalFrame.origin.x = max(frame.origin.x, visibleFrame.maxX + 8)
        // Horizontal slide-out only: preserve y, width and height exactly.
        isProgrammaticFrameChange = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            self.isProgrammaticFrameChange = false
            self.isAnimatingOut = false
        }
    }

    func showRunResult(result: CommandResult) {
        let wasCompact = panelState.isCompact
        panelState.runningActionName = nil
        panelState.runningFiles = []
        panelState.lastResult = result

        switch result.status {
        case .success:
            if wasCompact {
                panelState.isCompact = true
                panelVC.refresh()
                animateHeight(to: compactFrameHeight) { [weak self] in
                    self?.scheduleHideAfterSuccess()
                }
            } else {
                panelVC.refresh()
            }
        case .failed, .timeout, .cancelled:
            cancelHideAfterSuccess()
            stopSuccessHoverMonitor()
            if wasCompact {
                expandFromCompactForError()
            } else {
                panelVC.refresh()
            }
        default:
            panelVC.refresh()
        }
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
