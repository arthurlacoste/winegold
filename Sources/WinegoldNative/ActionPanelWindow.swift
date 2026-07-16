import Cocoa
import WinegoldCore
import WinegoldUI

class ActionPanelWindow: NSPanel, NSWindowDelegate {
    private let panelVC: ActionPanelViewController
    private let panelState: PanelState
    private var targetScreen: NSScreen
    private var settingsStore: SettingsStore
    private var isProgrammaticFrameChange = false
    private var resizeState = PanelResizeState()
    private var resizeWorkItem: DispatchWorkItem?
    private var persistResizeWorkItem: DispatchWorkItem?
    private var canPersistUserResize = false
    private var actionTriggeredSinceShow = false
    private var autoHideTimer: Timer?
    private var pendingAutoHideWorkItem: DispatchWorkItem?
    private var outsideClickMonitor: Any?
    private var hideAfterSuccessWorkItem: DispatchWorkItem?
    private var successHoverTimer: Timer?
    private var isAnimatingOut = false
    private let compactFrameHeight: CGFloat = 132
    private let idleDropFrameHeight: CGFloat = 220
    private var staysOpenUntilExplicitClose = false
    private var isModalInteractionActive = false

    init(
        screen: NSScreen,
        files: [URL],
        actions: [Action],
        allActions: [Action],
        history: [RunHistoryItem],
        savedHistory: [RunHistoryItem],
        savedHistoryIds: Set<UUID>,
        setupRequirements: [UUID: RecipeSetupRequirements],
        isMatchingActions: Bool = false,
        settingsStore: SettingsStore,
        onRunAction: @escaping (Action, [URL]) -> Void,
        onSetupAction: @escaping (Action, [URL]) -> Void,
        onToggleSavedRun: @escaping (RunHistoryItem) -> Void,
        onOpenSettings: @escaping () -> Void,
        onToggleFavorite: @escaping (Action) -> Void,
        onMoveAction: @escaping (Action, Action) -> Void
    ) {
        let state = PanelState()
        state.files = files
        state.actions = actions
        state.allActions = allActions
        state.history = history
        state.savedHistory = savedHistory
        state.savedHistoryIds = savedHistoryIds
        state.setupRequirements = setupRequirements
        state.isMatchingActions = isMatchingActions
        self.panelState = state
        self.targetScreen = screen
        self.settingsStore = settingsStore

        let vc = ActionPanelViewController(
            state: state,
            onRunAction: onRunAction,
            onSetupAction: onSetupAction,
            onToggleSavedRun: onToggleSavedRun,
            onOpenSettings: onOpenSettings,
            onToggleFavorite: onToggleFavorite,
            onMoveAction: onMoveAction
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

        self.title = ""
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isOpaque = false
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
        savedHistoryIds: Set<UUID>,
        setupRequirements: [UUID: RecipeSetupRequirements],
        isMatchingActions: Bool = false
    ) {
        targetScreen = screen
        panelState.files = files
        panelState.actions = actions
        panelState.allActions = allActions
        panelState.history = history
        panelState.savedHistory = savedHistory
        panelState.savedHistoryIds = savedHistoryIds
        panelState.setupRequirements = setupRequirements
        panelState.isMatchingActions = isMatchingActions
        panelState.lastResult = nil
        panelState.batchResults = []
        panelState.activeActionId = nil
        panelState.clearRunningDetails()
        panelState.isCompact = false
        actionTriggeredSinceShow = false
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()
        panelVC.refresh()
        resizeForCurrentContent(animated: true)
    }

    func markActionTriggered() {
        actionTriggeredSinceShow = true
        cancelPendingAutoHide()
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()
    }

    var currentFiles: [URL] { panelState.files }

    func replaceActions(
        allActions: [Action],
        actions: [Action],
        setupRequirements: [UUID: RecipeSetupRequirements],
        isMatchingActions: Bool = false
    ) {
        panelState.allActions = allActions
        panelState.actions = actions
        panelState.setupRequirements = setupRequirements
        panelState.isMatchingActions = isMatchingActions
        panelVC.refresh()
        resizeForCurrentContent(animated: true)
    }

    func updateAuxiliaryData(
        history: [RunHistoryItem],
        savedHistory: [RunHistoryItem],
        savedHistoryIds: Set<UUID>
    ) {
        panelState.history = history
        panelState.savedHistory = savedHistory
        panelState.savedHistoryIds = savedHistoryIds
    }

    func updateSavedHistory(_ savedHistory: [RunHistoryItem], savedIds: Set<UUID>) {
        panelState.savedHistory = savedHistory
        panelState.savedHistoryIds = savedIds
        panelVC.refresh()
    }

    private func applyTheme() {
        backgroundColor = WinegoldTheme.panelBackground(in: contentView)
        contentView?.layer?.backgroundColor = WinegoldTheme.layerColor(
            WinegoldTheme.panelBackground(in: contentView),
            in: contentView
        )
    }

    func show(staysOpen: Bool = false) {
        staysOpenUntilExplicitClose = staysOpen
        canPersistUserResize = false
        isAnimatingOut = false
        actionTriggeredSinceShow = false
        panelState.isCompact = false
        cancelPendingAutoHide()
        cancelHideAfterSuccess()
        stopSuccessHoverMonitor()
        applyTheme()
        let visibleFrame = targetScreen.visibleFrame
        let savedPanelSize = ActionPanelWindow.clampedPanelSize(
            width: CGFloat(settingsStore.panelWidth),
            height: CGFloat(settingsStore.panelHeight == 0 ? Int(visibleFrame.height - 40) : settingsStore.panelHeight),
            visibleFrame: visibleFrame
        )
        let panelWidth = savedPanelSize.width
        let panelHeight: CGFloat
        if panelVC.shouldShowActions {
            panelHeight = savedPanelSize.height
        } else {
            let contentRect = NSRect(x: 0, y: 0, width: panelWidth, height: idleDropFrameHeight)
            let naturalHeight = frameRect(forContentRect: contentRect).height
            panelHeight = max(compactFrameHeight, min(naturalHeight, visibleFrame.height - 40))
        }
        let targetX = settingsStore.panelSide == .left ? visibleFrame.minX + 20 : max(visibleFrame.minX, visibleFrame.maxX - panelWidth - 20)
        var frame = self.frame
        frame.origin.x = targetX
        frame.origin.y = max(visibleFrame.minY + 20, visibleFrame.maxY - panelHeight - 20)
        frame.size = NSSize(width: panelWidth, height: panelHeight)
        logMsg("[ActionPanelWindow] show visibleFrame=\(NSStringFromRect(visibleFrame)) frame=\(NSStringFromRect(frame))")
        let finalFrame = frame
        var startFrame = finalFrame
        startFrame.origin.x = settingsStore.panelSide == .left ? visibleFrame.minX - panelWidth - 8 : visibleFrame.maxX + 8
        let shouldSlideIn = !isVisible || self.frame.origin.x >= visibleFrame.maxX - 2

        isProgrammaticFrameChange = true
        self.setFrame(shouldSlideIn ? startFrame : finalFrame, display: true)
        self.makeKeyAndOrderFront(nil)
        self.orderFrontRegardless()
        logMsg("[Perf] panel_first_frame uptime=\(ProcessInfo.processInfo.systemUptime)")
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
            self?.resizeForCurrentContent(animated: false)
            self?.canPersistUserResize = true
            if self?.staysOpenUntilExplicitClose == false {
                self?.startAutoHideMonitor()
                self?.startOutsideClickMonitor()
            }
        }
    }


    func move(to side: PanelSide, animated: Bool) {
        settingsStore.panelSide = side
        guard isVisible else { return }
        let visibleFrame = currentVisibleFrame()
        var newFrame = frame
        newFrame.origin.x = side == .left ? visibleFrame.minX + 20 : visibleFrame.maxX - newFrame.width - 20
        isProgrammaticFrameChange = true
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(newFrame, display: true)
            } completionHandler: { [weak self] in self?.isProgrammaticFrameChange = false }
        } else {
            setFrame(newFrame, display: true)
            isProgrammaticFrameChange = false
        }
    }

    func hide() {
        logMsg("[Perf] panel_close_requested uptime=\(ProcessInfo.processInfo.systemUptime)")
        animateOutToRight()
    }

    func beginModalInteraction() {
        isModalInteractionActive = true
        cancelPendingAutoHide()
        stopAutoHideMonitor()
        stopOutsideClickMonitor()
    }

    func endModalInteraction() {
        isModalInteractionActive = false
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        guard !staysOpenUntilExplicitClose else { return }
        startAutoHideMonitor()
        startOutsideClickMonitor()
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

    private var hasActiveFileDrag: Bool {
        panelVC.hasActiveFileDrag
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
        guard allowsAutomaticDismissal else { return }
        let point = NSEvent.mouseLocation
        guard !frame.insetBy(dx: -2, dy: -2).contains(point) else { return }

        if hasRunningAction, !panelState.isCompact {
            collapseToCompactStatus()
        } else if !hasRunningAction {
            animateOutToRight()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard allowsAutomaticDismissal else { return }
        if hasRunningAction, !panelState.isCompact {
            collapseToCompactStatus()
        } else if !hasRunningAction {
            animateOutToRight()
        }
    }

    private var allowsAutomaticDismissal: Bool {
        PanelDismissalPolicy.allowsAutomaticDismissal(
            staysOpen: staysOpenUntilExplicitClose,
            isModalInteractionActive: isModalInteractionActive,
            isVisible: isVisible,
            isAnimatingOut: isAnimatingOut,
            hasActiveFileDrag: hasActiveFileDrag
        )
    }

    private func collapseToCompactStatus() {
        guard isVisible, !isAnimatingOut else { return }
        logMsg("[ActionPanelWindow] compact running status")
        panelState.isCompact = true
        panelVC.refresh()
        animateHeight(to: compactStatusFrameHeight())
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

    private func compactStatusFrameHeight() -> CGFloat {
        let visibleFrame = currentVisibleFrame()
        let contentHeight = max(panelVC.currentContentHeight, compactFrameHeight)
        let contentRect = NSRect(x: 0, y: 0, width: frame.width, height: contentHeight)
        let frameHeight = frameRect(forContentRect: contentRect).height
        let maxHeight = max(compactFrameHeight, visibleFrame.height - 40)
        return max(compactFrameHeight, min(frameHeight, maxHeight))
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
        guard !staysOpenUntilExplicitClose else { return }
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
        guard !staysOpenUntilExplicitClose else { return }
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
        guard allowsAutomaticDismissal, !actionTriggeredSinceShow else {
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
            guard self.allowsAutomaticDismissal, !self.actionTriggeredSinceShow else { return }
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


    func resizeForCurrentContent(animated: Bool) {
        guard isVisible, !isAnimatingOut else { return }
        let targetHeight: CGFloat
        if panelState.isCompact {
            targetHeight = compactStatusFrameHeight()
        } else if panelVC.shouldShowActions {
            targetHeight = targetFrameHeight(forContentHeight: panelVC.currentContentHeight)
        } else {
            targetHeight = targetFrameHeight(forContentHeight: max(panelVC.currentContentHeight, idleDropFrameHeight))
        }
        guard resizeState.request(height: Double(targetHeight)) else { return }
        resizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.applyPendingContentResize() }
        resizeWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func applyPendingContentResize() {
        resizeWorkItem = nil
        guard let requestedHeight = resizeState.consumePendingHeight(), isVisible, !isAnimatingOut else { return }
        let targetHeight = CGFloat(requestedHeight)
        guard abs(frame.height - targetHeight) >= 1 else { return }
        let visibleFrame = currentVisibleFrame()
        var newFrame = frame
        let topY = frame.maxY
        newFrame.size.height = targetHeight
        newFrame.origin.y = max(visibleFrame.minY + 20, min(topY - targetHeight, visibleFrame.maxY - targetHeight - 20))
        isProgrammaticFrameChange = true
        setFrame(newFrame, display: true)
        isProgrammaticFrameChange = false
    }


    private func targetFrameHeight(forContentHeight contentHeight: CGFloat) -> CGFloat {
        let visibleFrame = currentVisibleFrame()
        let contentRect = NSRect(x: 0, y: 0, width: frame.width, height: contentHeight)
        let naturalHeight = frameRect(forContentRect: contentRect).height
        return max(compactFrameHeight, min(naturalHeight, visibleFrame.height - 40))
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
            logMsg("[Perf] panel_closed uptime=\(ProcessInfo.processInfo.systemUptime)")
            self.isProgrammaticFrameChange = false
            self.isAnimatingOut = false
        }
    }

    func beginRun(actionName: String, files: [URL]) {
        panelState.batchResults = []
        panelState.lastResult = nil
        panelState.clearRunningDetails()
        panelState.runningActionName = actionName
        panelState.runningFiles = files
        panelVC.refresh()
        resizeForCurrentContent(animated: true)
    }

    func updateRunningProgress(
        actionName: String,
        file: URL,
        fileIndex: Int,
        fileCount: Int,
        request: CommandExecutionRequest,
        stdout: String = "",
        stderr: String = ""
    ) {
        panelState.lastResult = nil
        panelState.runningActionName = actionName
        panelState.runningCurrentFile = file
        panelState.runningFileIndex = fileIndex
        panelState.runningFileCount = fileCount
        panelState.runningCommand = request.displayCommand
        panelState.runningWorkingDirectory = request.workingDirectory
        panelState.runningStdout = stdout
        panelState.runningStderr = stderr
        panelVC.refresh()
        resizeForCurrentContent(animated: true)
    }

    func showRunningResult(result: CommandResult) {
        panelState.lastResult = nil
        panelState.runningActionName = result.actionName
        panelState.runningStdout = result.stdout
        panelState.runningStderr = result.stderr
        panelVC.refresh()
        resizeForCurrentContent(animated: true)
    }

    func appendBatchResult(result: CommandResult) {
        panelState.lastResult = nil
        panelState.batchResults.append(result)
        panelVC.refresh()
    }

    func showRunResult(result: CommandResult) {
        let wasCompact = panelState.isCompact
        panelState.clearRunningDetails()
        panelState.lastResult = result

        switch result.status {
        case .success:
            panelState.isCompact = false
            cancelHideAfterSuccess()
            stopSuccessHoverMonitor()
            panelVC.refresh()
            resizeForCurrentContent(animated: true)
        case .failed, .timeout, .cancelled:
            cancelHideAfterSuccess()
            stopSuccessHoverMonitor()
            if wasCompact {
                expandFromCompactForError()
            } else {
                panelVC.refresh()
                resizeForCurrentContent(animated: true)
            }
        default:
            panelVC.refresh()
            resizeForCurrentContent(animated: true)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard canPersistUserResize, !isProgrammaticFrameChange else { return }
        let width = Int(frame.width.rounded())
        let height = Int(frame.height.rounded())
        guard resizeState.shouldPersist(width: width, height: height) else { return }
        persistResizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isProgrammaticFrameChange else { return }
            self.settingsStore.panelWidth = width
            self.settingsStore.panelHeight = height
            logMsg("[ActionPanelWindow] saved size width=\(width) height=\(height)")
        }
        persistResizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
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
