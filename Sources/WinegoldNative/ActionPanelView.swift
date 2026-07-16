import Cocoa
import UniformTypeIdentifiers
import WinegoldCore
import WinegoldUI

class ActionPanelViewController: NSViewController, NSSearchFieldDelegate {
    private let state: PanelState
    private let onRunAction: (Action, [URL]) -> Void
    private let onSetupAction: (Action, [URL]) -> Void
    private let onToggleSavedRun: (RunHistoryItem) -> Void
    private let onOpenSettings: () -> Void
    private let onToggleFavorite: (Action) -> Void
    private let onMoveAction: (Action, Action) -> Void
    private var cardViews: [ActionCardView] = []
    private var runGeneration = 0
    private var lastLayoutWidth: CGFloat = 0
    private var lastHadStatusArea = false
    private var actionRenderWindow = ActionRenderWindow(batchSize: 20)
    private var isRefreshing = false
    private var lastFilesSignature = ""
    private var showsRecentRuns = false
    private var showsTechnicalDetails = false
    private var isDraggingFiles = false
    private var dragPreviewFiles: [URL] = []
    private let settingsButton = NSButton()
    private let helpButton = NSButton()
    private let footerBar = PanelFooterBarView(frame: .zero)
    private let actionSearchField = NSSearchField()
    private var actionSearchQuery = ""
    private var keyboardSelection = KeyboardActionSelection()
    private var visibleActionItems: [PresentedAction] = []
    private var shouldRestoreSearchFocus = false
    private(set) var currentContentHeight: CGFloat = 0

    var shouldShowActions: Bool {
        !state.allActions.isEmpty || !state.files.isEmpty || !dragPreviewFiles.isEmpty || state.runningActionName != nil || state.lastResult != nil
    }

    var hasActiveFileDrag: Bool {
        isDraggingFiles || !dragPreviewFiles.isEmpty
    }

    private var previewMatchedActions: [Action] {
        guard !dragPreviewFiles.isEmpty else { return [] }
        return ActionMatcher().matchingActions(for: dragPreviewFiles, actions: state.allActions)
    }

    private let padding: CGFloat = 24
    private let scrollView = DropForwardingScrollView()
    private let contentView = PanelDropView(frame: .zero)

    init(
        state: PanelState,
        onRunAction: @escaping (Action, [URL]) -> Void,
        onSetupAction: @escaping (Action, [URL]) -> Void,
        onToggleSavedRun: @escaping (RunHistoryItem) -> Void,
        onOpenSettings: @escaping () -> Void,
        onToggleFavorite: @escaping (Action) -> Void,
        onMoveAction: @escaping (Action, Action) -> Void
    ) {
        self.state = state
        self.onRunAction = onRunAction
        self.onSetupAction = onSetupAction
        self.onToggleSavedRun = onToggleSavedRun
        self.onOpenSettings = onOpenSettings
        self.onToggleFavorite = onToggleFavorite
        self.onMoveAction = onMoveAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = PanelDropView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.panelBackground(in: view), in: view)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.panelBackground(in: view), in: view)
        let fileDropHandler: ([URL]) -> Void = { [weak self] files in
            self?.setDraggedFiles(files)
        }
        let filePreviewHandler: ([URL]) -> Void = { [weak self] files in
            self?.setDragPreviewFiles(files)
        }
        (view as? PanelDropView)?.onFilesDropped = fileDropHandler
        (view as? PanelDropView)?.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
            self?.refresh(animatedStatusInsert: false)
        }
        (view as? PanelDropView)?.onFilesPreviewed = filePreviewHandler
        scrollView.onFilesDropped = fileDropHandler
        scrollView.onFilesPreviewed = filePreviewHandler
        contentView.onFilesDropped = fileDropHandler
        contentView.onFilesPreviewed = filePreviewHandler
        let draggingHandler: (Bool) -> Void = { [weak self] dragging in
            self?.setDraggingFiles(dragging)
        }
        (view as? PanelDropView)?.onDraggingChanged = draggingHandler
        scrollView.onDraggingChanged = draggingHandler
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        contentView.onDraggingChanged = draggingHandler
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        logMsg("[PanelVC] viewDidLoad files=\(state.files.count) actions=\(state.actions.count)")
        applyTheme()
        actionSearchField.delegate = self
        configureBottomTools()
        buildUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if state.files.isEmpty, actionSearchField.superview != nil {
            view.window?.makeFirstResponder(actionSearchField)
        }
        applyTheme()
        refresh(animatedStatusInsert: false)
    }

    private func applyTheme() {
        view.layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.panelBackground(in: view), in: view)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.panelBackground(in: view), in: view)
        scrollView.drawsBackground = false
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyTheme()
        let width = view.bounds.width
        guard width > 0 else { return }
        layoutFooterBar()
        if abs(width - lastLayoutWidth) > 1 {
            refresh(animatedStatusInsert: false)
        }
    }

    func refresh(animatedStatusInsert: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let hasStatusArea = state.lastResult != nil || state.runningActionName != nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            contentView.layer?.removeAllAnimations()
            contentView.subviews.forEach {
                $0.layer?.removeAllAnimations()
                $0.removeFromSuperview()
            }
            cardViews.removeAll()
            buildUI()
        }
        lastHadStatusArea = hasStatusArea
    }

    private func buildUI(animateStatusInsert: Bool = false) {
        applyTheme()
        var y: CGFloat = 18
        let panelWidth = max(view.bounds.width, 320)
        lastLayoutWidth = panelWidth
        let w = panelWidth - padding * 2

        if state.isCompact {
            if let result = state.lastResult {
                y += addResult(result: result, y: y, w: w)
            } else {
                y += addLoading(actionName: state.runningActionName ?? "Running action", y: y, w: w)
            }
            installScrollView(panelWidth: panelWidth, contentHeight: max(y + 10, 98))
            return
        }

        if let result = state.lastResult {
            y += addDoneState(result: result, y: y, w: w)
        } else {
            y += addDropZone(y: y, w: w)
        }

        if shouldShowActions && !state.files.isEmpty {
            addFilesSection(y: &y, w: w)
        }

        if shouldShowActions {
            addActionsSection(y: &y, w: w)
            addRecentRunsLink(y: &y, w: w)
        }

        if shouldShowActions && showsRecentRuns {
            if !state.savedHistory.isEmpty {
                y += 12
                addSavedSection(y: &y, w: w)
            }
            if !state.history.isEmpty {
                y += 12
                addHistorySection(y: &y, w: w)
            }
        }

        installScrollView(panelWidth: panelWidth, contentHeight: y + 20)
    }

    private func addDropZone(y: CGFloat, w: CGFloat) -> CGFloat {
        let isRunning = state.runningActionName != nil
        let height: CGFloat = isRunning ? 148 : 118
        let container = PanelDropZoneView(frame: NSRect(x: padding, y: y, width: w, height: height))
        container.onFilesDropped = { [weak self] files in self?.setDraggedFiles(files) }
        container.onFilesPreviewed = { [weak self] files in self?.setDragPreviewFiles(files) }
        container.onDraggingChanged = { [weak self] dragging in self?.setDraggingFiles(dragging) }
        if !isRunning {
            container.onChooseFiles = { [weak self] in self?.chooseFiles() }
        }
        container.isHighlighted = isDraggingFiles

        if isRunning {
            let spinner = NSProgressIndicator(frame: NSRect(x: 18, y: 20, width: 22, height: 22))
            spinner.style = .spinning
            spinner.startAnimation(nil)
            container.addSubview(spinner)

            let file = state.runningCurrentFile ?? state.runningFiles.first ?? state.files.first
            let titleText = file.map { "\(state.runningActionName ?? "Running") \($0.lastPathComponent)" } ?? (state.runningActionName ?? "Running")
            let title = NSTextField(labelWithString: titleText)
            title.font = .systemFont(ofSize: 15, weight: .semibold)
            title.frame = NSRect(x: 54, y: 18, width: w - 100, height: 22)
            container.addSubview(title)

            let subtitle = NSTextField(labelWithString: "Running…")
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = .secondaryLabelColor
            subtitle.frame = NSRect(x: 54, y: 42, width: w - 100, height: 18)
            container.addSubview(subtitle)

            let info = NSButton(title: "ⓘ", target: self, action: #selector(toggleTechnicalDetails))
            info.isBordered = false
            info.font = .systemFont(ofSize: 15)
            info.frame = NSRect(x: w - 40, y: 15, width: 28, height: 28)
            info.toolTip = "Technical details"
            container.addSubview(info)

            if showsTechnicalDetails {
                let detailText = [state.runningWorkingDirectory.map { "cwd: \($0)" }, state.runningCommand.map { "command: \($0)" }, latestRunningOutputLine()].compactMap { $0 }.joined(separator: "\n")
                let details = NSTextField(wrappingLabelWithString: detailText.isEmpty ? "No technical details yet." : detailText)
                details.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
                details.textColor = .secondaryLabelColor
                details.frame = NSRect(x: 54, y: 68, width: w - 70, height: 62)
                container.addSubview(details)
            }
        } else {
            let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)!)
            icon.contentTintColor = .secondaryLabelColor
            icon.frame = NSRect(x: 18, y: 28, width: 36, height: 44)
            container.addSubview(icon)

            let title = NSTextField(labelWithString: !dragPreviewFiles.isEmpty ? "Drop to show compatible actions" : "Drop files here")
            title.font = .systemFont(ofSize: 15, weight: .semibold)
            title.frame = NSRect(x: 70, y: 25, width: w - 92, height: 22)
            container.addSubview(title)

            let droppedOrPreviewFiles = !dragPreviewFiles.isEmpty ? dragPreviewFiles : state.files
            let subtitleText = droppedOrPreviewFiles.isEmpty ? "Winegold will suggest compatible actions. Click anywhere here to choose files, or drag directly onto an action below." : droppedOrPreviewFiles.map(\.lastPathComponent).joined(separator: ", ")
            let subtitle = NSTextField(wrappingLabelWithString: subtitleText)
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = .secondaryLabelColor
            subtitle.frame = NSRect(x: 70, y: 48, width: w - 92, height: 48)
            container.addSubview(subtitle)
        }

        contentView.addSubview(container)
        return height + 18
    }

    private func addRecentRunsLink(y: inout CGFloat, w: CGFloat) {
        let button = NSButton(title: showsRecentRuns ? "Hide recent runs" : "Show recent runs", target: self, action: #selector(toggleRecentRuns))
        button.isBordered = false
        button.font = .systemFont(ofSize: 12)
        button.contentTintColor = .secondaryLabelColor
        button.frame = NSRect(x: padding, y: y, width: w, height: 28)
        contentView.addSubview(button)
        y += 32
    }

    private func configureBottomTools() {
        footerBar.wantsLayer = true
        view.addSubview(footerBar)

        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.isBordered = false
        settingsButton.toolTip = "Settings"
        settingsButton.target = self
        settingsButton.action = #selector(settingsClicked)
        footerBar.addSubview(settingsButton)

        helpButton.title = "?"
        helpButton.isBordered = false
        helpButton.contentTintColor = .secondaryLabelColor
        helpButton.font = .systemFont(ofSize: 14)
        helpButton.toolTip = "Help"
        helpButton.target = self
        helpButton.action = #selector(helpClicked)
        footerBar.addSubview(helpButton)
        layoutFooterBar()
    }

    private var footerHeight: CGFloat { 36 }

    private func layoutFooterBar() {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        footerBar.frame = NSRect(x: 0, y: max(0, view.bounds.height - footerHeight), width: view.bounds.width, height: footerHeight)
        let leftInset: CGFloat = 12
        let itemSpacing: CGFloat = 14
        settingsButton.frame = NSRect(x: leftInset, y: 6, width: 24, height: 24)
        helpButton.frame = NSRect(x: leftInset + 24 + itemSpacing, y: 6, width: 24, height: 24)
    }

    private func installScrollView(panelWidth: CGFloat, contentHeight: CGFloat) {
        currentContentHeight = contentHeight + footerHeight
        contentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: contentHeight)
        scrollView.documentView = contentView
        scrollView.hasVerticalScroller = !state.isCompact && shouldShowActions
        scrollView.autohidesScrollers = true
        scrollView.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: max(0, view.bounds.height - footerHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        if scrollView.superview == nil {
            view.addSubview(scrollView, positioned: .below, relativeTo: footerBar)
        }
        layoutFooterBar()
    }


    private func setDraggingFiles(_ dragging: Bool) {
        if !dragging, isMouseInsidePanelWindow() {
            return
        }
        if !dragging {
            dragPreviewFiles = []
        }
        guard isDraggingFiles != dragging || !dragging else { return }
        isDraggingFiles = dragging
        refresh()
        requestWindowResize(animated: true)
    }

    private func isMouseInsidePanelWindow() -> Bool {
        guard let window = view.window else { return false }
        return window.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }

    private func setDragPreviewFiles(_ files: [URL]) {
        guard !files.isEmpty else { return }
        let signature = files.map { $0.path }.joined(separator: "\n")
        guard signature != dragPreviewFiles.map({ $0.path }).joined(separator: "\n") else { return }
        dragPreviewFiles = files
        isDraggingFiles = true
        refresh()
        requestWindowResize(animated: true)
    }


    private func requestWindowResize(animated: Bool) {
        DispatchQueue.main.async { [weak self] in
            (self?.view.window as? ActionPanelWindow)?.resizeForCurrentContent(animated: animated)
        }
    }

    private func setDraggedFiles(_ files: [URL]) {
        guard !files.isEmpty else { return }
        let signature = PanelFileSelection.signature(for: files)
        if PanelFileSelection.shouldIgnore(
            files: files,
            currentFiles: state.files,
            lastSignature: lastFilesSignature,
            hasResult: state.lastResult != nil,
            isRunning: state.runningActionName != nil
        ) { return }
        lastFilesSignature = signature
        actionRenderWindow.reset()
        dragPreviewFiles = []
        isDraggingFiles = false

        state.files = files
        state.actions = ActionMatcher().matchingActions(for: files, actions: state.allActions)
        state.lastResult = nil
        state.batchResults = []
        state.activeActionId = nil
        state.clearRunningDetails()
        state.isCompact = false
        refresh()
        requestWindowResize(animated: true)
    }

    private func addHeader(y: inout CGFloat, w: CGFloat) {
        let icon = NSImageView(image: NSImage(systemSymbolName: "square.grid.3x1.folder.badge.plus", accessibilityDescription: nil)!)
        icon.frame = NSRect(x: padding, y: y + 4, width: 20, height: 20)
        icon.contentTintColor = .controlTextColor
        contentView.addSubview(icon)

        let title = NSTextField(labelWithString: "Winegold")
        title.font = .boldSystemFont(ofSize: 15)
        title.frame = NSRect(x: padding + 28, y: y + 4, width: 200, height: 20)
        contentView.addSubview(title)

        let btn = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!, target: self, action: #selector(settingsClicked))
        btn.isBordered = false
        btn.frame = NSRect(x: padding + w - 24, y: y + 2, width: 24, height: 24)
        contentView.addSubview(btn)

        y += 32
    }

    private func addDivider(y: inout CGFloat, w: CGFloat) {
        let line = NSBox(frame: NSRect(x: padding, y: y, width: w, height: 1))
        line.boxType = .separator
        contentView.addSubview(line)
        y += 12
    }

    private func addEmptyState(y: inout CGFloat, w: CGFloat) {
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.left.to.line", accessibilityDescription: nil)!)
        icon.frame = NSRect(x: padding + (w - 40) / 2, y: y + 40, width: 40, height: 40)
        icon.contentTintColor = .secondaryLabelColor
        contentView.addSubview(icon)

        let label = NSTextField(labelWithString: "Drag files to the right edge")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: padding, y: y + 88, width: w, height: 20)
        contentView.addSubview(label)

        y += 120
    }

    private func addFilesSection(y: inout CGFloat, w: CGFloat) {
        let label = sectionLabel("Files")
        label.frame.origin = CGPoint(x: padding, y: y)
        contentView.addSubview(label)
        y += 18

        for file in state.files {
            let icon = NSImageView(image: NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!)
            icon.frame = NSRect(x: padding, y: y + 2, width: 18, height: 18)
            icon.contentTintColor = .secondaryLabelColor
            contentView.addSubview(icon)

            let name = NSTextField(labelWithString: file.lastPathComponent)
            name.font = .systemFont(ofSize: 13)
            name.lineBreakMode = .byTruncatingMiddle
            name.frame = NSRect(x: padding + 26, y: y + 1, width: w - 26, height: 20)
            contentView.addSubview(name)

            y += 22
        }
        y += 8
    }

    private func startRun(action: Action, files: [URL]) {
        runGeneration += 1
        let generation = runGeneration

        state.files = files
        state.lastResult = nil
        state.batchResults = []
        state.activeActionId = action.id
        state.clearRunningDetails()
        state.runningFiles = files
        state.isCompact = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard self.runGeneration == generation else { return }
            guard self.state.lastResult == nil else { return }
            guard self.state.runningActionName == nil else { return }
            self.state.runningActionName = action.name
            self.refresh()
        }

        onRunAction(action, files)
    }

    private func addActionsSection(y: inout CGFloat, w: CGFloat) {
        let dragActions = previewMatchedActions
        let matchedActions: [Action]
        if !dragPreviewFiles.isEmpty {
            matchedActions = dragActions
        } else if state.files.isEmpty {
            matchedActions = state.allActions.filter(\.enabled)
        } else {
            matchedActions = state.actions
        }
        let presented = matchedActions.map { action -> PresentedAction in
            let metadata = state.actionMetadata[action.id]
            return PresentedAction(
                action: action,
                parentName: metadata?.parentName,
                parentExternalID: metadata?.parentExternalID,
                childActionID: metadata?.childActionID,
                usageCount: metadata?.usageCount ?? 0,
                localOrderOverride: metadata?.localOrderOverride
            )
        }
        let filtered = ActionPresentationPolicy().present(presented, query: actionSearchQuery)
        let renderedCount = actionRenderWindow.visibleCount(total: filtered.count)
        let visible = Array(filtered.prefix(renderedCount))
        visibleActionItems = visible
        keyboardSelection.clamp(count: visible.count)

        let label = sectionLabel("ACTIONS · \(matchedActions.count)")
        label.frame.origin = CGPoint(x: padding + 2, y: y)
        contentView.addSubview(label)
        y += 20

        if state.files.isEmpty || matchedActions.count > 10 || !actionSearchQuery.isEmpty {
            actionSearchField.placeholderString = "Search \(matchedActions.count) actions"
            actionSearchField.stringValue = actionSearchQuery
            actionSearchField.target = nil
            actionSearchField.action = nil
            actionSearchField.frame = NSRect(x: padding, y: y + 10, width: w, height: 28)
            contentView.addSubview(actionSearchField)
            y += 56
        }

        if visible.isEmpty {
            let text = actionSearchQuery.isEmpty ? "No compatible actions" : "No matching actions"
            let empty = NSTextField(labelWithString: text)
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: padding, y: y, width: w, height: 20)
            contentView.addSubview(empty)
            y += 24
            return
        }

        let rowHeight: CGFloat = 58
        let containerHeight = CGFloat(visible.count) * rowHeight
        let container = PanelActionListView(frame: NSRect(x: padding, y: y, width: w, height: containerHeight))
        contentView.addSubview(container)
        let validator = ActionValidator()

        for (index, item) in visible.enumerated() {
            let action = item.action
            let card = ActionCardView(
                action: action,
                status: validator.validate(action),
                isActive: state.activeActionId == action.id,
                isKeyboardSelected: index == keyboardSelection.index,
                setupRequirements: state.setupRequirements[action.id],
                inputActionLabel: paletteActionLabel(for: action),
                isGroupedRow: true,
                parentName: item.parentName,
                onDrop: { [weak self] droppedFiles in
                    let files = droppedFiles.isEmpty ? (self?.state.files ?? []) : droppedFiles
                    self?.select(action: action, files: files)
                },
                onSetup: { [weak self] action in self?.onSetupAction(action, self?.state.files ?? []) },
                onToggleFavorite: { [weak self] action in self?.onToggleFavorite(action) },
                onMoveBefore: { [weak self] source, target in self?.onMoveAction(source, target) },
                onSelection: { [weak self] in self?.selectCard(at: index) }
            )
            card.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: w, height: rowHeight)
            container.addSubview(card)
            cardViews.append(card)

            if index < visible.count - 1 {
                let separator = NSView(frame: NSRect(x: 0, y: CGFloat(index + 1) * rowHeight, width: w, height: 1))
                separator.wantsLayer = true
                separator.layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.separator(in: view), in: view)
                container.addSubview(separator)
            }
        }
        y += containerHeight + 12

        if actionRenderWindow.hasMore(total: filtered.count) {
            let remaining = filtered.count - visible.count
            let more = NSTextField(labelWithString: "Scroll to load \(remaining) more actions")
            more.font = .systemFont(ofSize: 11)
            more.textColor = .secondaryLabelColor
            more.alignment = .center
            more.frame = NSRect(x: padding, y: y, width: w, height: 18)
            contentView.addSubview(more)
            y += 24
        }
    }

    @objc private func scrollBoundsChanged() {
        guard let documentView = scrollView.documentView else { return }
        let visibleMaxY = scrollView.contentView.bounds.maxY
        guard visibleMaxY >= documentView.bounds.height - 120 else { return }
        let total = currentPresentedActions().count
        guard actionRenderWindow.loadNext(total: total) else { return }
        refresh(animatedStatusInsert: false)
    }

    private func currentPresentedActions() -> [PresentedAction] {
        let matchedActions: [Action]
        if !dragPreviewFiles.isEmpty {
            matchedActions = previewMatchedActions
        } else if state.files.isEmpty {
            matchedActions = state.allActions.filter(\.enabled)
        } else {
            matchedActions = state.actions
        }
        let presented = matchedActions.map { action -> PresentedAction in
            let metadata = state.actionMetadata[action.id]
            return PresentedAction(
                action: action,
                parentName: metadata?.parentName,
                parentExternalID: metadata?.parentExternalID,
                childActionID: metadata?.childActionID,
                usageCount: metadata?.usageCount ?? 0,
                localOrderOverride: metadata?.localOrderOverride
            )
        }
        return ActionPresentationPolicy().present(presented, query: actionSearchQuery)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard obj.object as AnyObject? === actionSearchField else { return }
        keyboardSelection.reset()
        releaseCardInteractionStates()
        syncCardSelection()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as AnyObject? === actionSearchField else { return }
        actionSearchQuery = actionSearchField.stringValue
        if state.files.isEmpty { showsRecentRuns = !actionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        actionRenderWindow.reset()
        keyboardSelection.reset()
        refreshKeepingSearchFocus()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === actionSearchField else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            keyboardSelection.moveUp(count: visibleActionItems.count)
            syncCardSelection()
            refreshKeepingSearchFocus()
            return true
        case #selector(NSResponder.moveDown(_:)):
            keyboardSelection.moveDown(count: visibleActionItems.count)
            syncCardSelection()
            refreshKeepingSearchFocus()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            runKeyboardSelectedAction()
            return true
        default:
            return false
        }
    }

    private func selectCard(at index: Int) {
        guard visibleActionItems.indices.contains(index) else { return }
        keyboardSelection.select(index: index, count: visibleActionItems.count)
        syncCardSelection()
    }

    private func syncCardSelection() {
        for (index, card) in cardViews.enumerated() {
            card.setSelected(index == keyboardSelection.index)
        }
    }

    private func releaseCardInteractionStates() {
        cardViews.forEach { $0.releaseInteractionState() }
    }

    private func refreshKeepingSearchFocus() {
        shouldRestoreSearchFocus = true
        refresh()
        requestWindowResize(animated: false)
        restoreSearchFocusIfNeeded()
    }

    private func restoreSearchFocusIfNeeded() {
        guard shouldRestoreSearchFocus else { return }
        shouldRestoreSearchFocus = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.actionSearchField.superview != nil else { return }
            self.view.window?.makeFirstResponder(self.actionSearchField)
            if let editor = self.actionSearchField.currentEditor() {
                editor.selectedRange = NSRange(location: self.actionSearchField.stringValue.utf16.count, length: 0)
            }
        }
    }

    private func runKeyboardSelectedAction() {
        guard !visibleActionItems.isEmpty else { return }
        keyboardSelection.clamp(count: visibleActionItems.count)
        let action = visibleActionItems[keyboardSelection.index].action
        select(action: action, files: state.files)
    }

    private func select(action: Action, files: [URL]) {
        if state.setupRequirements[action.id] != nil {
            onSetupAction(action, files)
            return
        }
        let items = files.map { DraggedItem(executionURL: $0) }
        switch RecipeInvocationValidator().validate(action, items: items) {
        case .valid:
            startRun(action: action, files: files)
        case let .missingInput(requirement):
            chooseInput(for: action, requirement: requirement)
        case let .incompatible(issues):
            showValidationError(issues.map(\.message).joined(separator: "\n"))
        }
    }

    private func chooseInput(for action: Action, requirement: RecipeInputRequirement) {
        if requirement == .url || requirement == .text {
            chooseTextualInput(for: action, requirement: requirement)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = action.maximumInputCount != 1
        switch requirement {
        case let .files(extensions):
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            let types = extensions.compactMap { UTType(filenameExtension: $0) }
            if !types.isEmpty { panel.allowedContentTypes = types }
        case .directories:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        case .items, .unresolved:
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
        case .url, .text:
            return
        case .none:
            startRun(action: action, files: [])
            return
        }
        let panelWindow = view.window as? ActionPanelWindow
        panelWindow?.beginModalInteraction()
        let response = panel.runModal()
        panelWindow?.endModalInteraction()
        guard response == .OK else { return }
        let items = panel.urls.map { DraggedItem(executionURL: $0) }
        switch RecipeInvocationValidator().validate(action, items: items) {
        case .valid:
            setDraggedFiles(panel.urls)
            startRun(action: action, files: panel.urls)
        case let .incompatible(issues):
            showValidationError(issues.map(\.message).joined(separator: "\n"))
        case .missingInput:
            showValidationError("This recipe still needs input.")
        }
    }


    private func chooseTextualInput(for action: Action, requirement: RecipeInputRequirement) {
        let alert = makeAppAlert()
        let isURL = requirement == .url
        alert.messageText = isURL ? "Enter URL" : "Enter text"
        alert.informativeText = isURL ? "Paste the URL required by this recipe." : "Enter the text required by this recipe."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: isURL ? 24 : 72))
        field.placeholderString = isURL ? "https://example.com" : "Text"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { showValidationError("Input cannot be empty."); return }
        if isURL, URLComponents(string: value)?.scheme == nil { showValidationError("Enter a valid URL."); return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WinegoldPaletteInputs", isDirectory: true)
            let file = try ContentAddressedFileStore(directory: directory).store(
                contents: value,
                prefix: isURL ? "dragged-url" : "dragged-text",
                fileExtension: isURL ? "url" : "txt"
            )
            let item = DraggedItem(executionURL: file, kind: isURL ? .url : .text, rawURL: isURL ? value : nil, rawText: isURL ? nil : value)
            switch RecipeInvocationValidator().validate(action, items: [item]) {
            case .valid: startRun(action: action, files: [file])
            case let .incompatible(issues): showValidationError(issues.map(\.message).joined(separator: "\n"))
            case .missingInput: showValidationError("This recipe still needs input.")
            }
        } catch {
            showValidationError(error.localizedDescription)
        }
    }

    private func paletteActionLabel(for action: Action) -> String? {
        guard state.files.isEmpty else { return nil }
        if state.setupRequirements[action.id] != nil { return nil }
        switch RecipeInputRequirementResolver().requirement(for: action) {
        case .none: return "Run"
        case .files: return "Choose file"
        case .directories: return "Choose folder"
        case .url: return "Enter URL"
        case .text: return "Enter text"
        case .items, .unresolved: return "Choose input"
        }
    }

    private func showValidationError(_ message: String) {
        let alert = makeAppAlert()
        alert.messageText = "Recipe cannot run"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func addLoading(actionName: String, y: CGFloat, w: CGFloat) -> CGFloat {
        let container = NSView(frame: NSRect(x: padding, y: y, width: w, height: 74))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = WinegoldTheme.layerColor(
            WinegoldTheme.cardBackground(in: view, emphasized: true),
            in: view
        )
        container.layer?.borderWidth = 1
        container.layer?.borderColor = WinegoldTheme.layerColor(
            NSColor.controlAccentColor.withAlphaComponent(0.35),
            in: view
        )

        let spinner = NSProgressIndicator(frame: NSRect(x: 14, y: 18, width: 28, height: 28))
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        let title = NSTextField(labelWithString: "Running…")
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.textColor = .controlTextColor
        title.frame = NSRect(x: 54, y: 13, width: w - 70, height: 20)
        container.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Running action: \(actionName)")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.frame = NSRect(x: 54, y: 34, width: w - 70, height: 18)
        container.addSubview(subtitle)

        var cy: CGFloat = 62
        let detailX: CGFloat = 54
        let detailW: CGFloat = w - 68

        if state.isCompact {
            if let fileText = runningFileText() {
                addCompactRunningLine(fileText, x: detailX, y: cy, w: detailW, to: container)
                cy += 18
            }
            if let output = latestRunningOutputLine() {
                addCompactRunningLine(output, x: detailX, y: cy, w: detailW, to: container)
                cy += 18
            } else if let command = state.runningCommand {
                addCompactRunningLine("Command: \(command)", x: detailX, y: cy, w: detailW, to: container)
                cy += 18
            }

            container.frame.size.height = max(cy + 10, 86)
            contentView.addSubview(container)
            return container.frame.height + 16
        }

        if let fileText = runningFileText() {
            addRunningLabel("File", value: fileText, y: &cy, w: w, to: container)
        }

        if let workingDirectory = state.runningWorkingDirectory, !workingDirectory.isEmpty {
            addRunningLabel("Working directory", value: workingDirectory, y: &cy, w: w, to: container)
        }

        if let command = state.runningCommand, !command.isEmpty {
            addRunningTextBlock(title: "Command", text: command, color: .labelColor, height: 44, y: &cy, w: w, to: container)
        }

        if !state.runningStdout.isEmpty {
            addRunningTextBlock(title: "Live output", text: state.runningStdout, color: .labelColor, height: 62, y: &cy, w: w, to: container)
        }

        if !state.runningStderr.isEmpty {
            addRunningTextBlock(title: "Live error", text: state.runningStderr, color: .systemRed, height: 48, y: &cy, w: w, to: container)
        }

        container.frame.size.height = min(max(cy + 12, 74), 280)
        contentView.addSubview(container)
        return container.frame.height + 16
    }

    private func runningFileText() -> String? {
        guard let file = state.runningCurrentFile else { return nil }
        let name = file.lastPathComponent
        guard let index = state.runningFileIndex, state.runningFileCount > 1 else { return name }
        return "\(name) (\(index)/\(state.runningFileCount))"
    }

    private func latestRunningOutputLine() -> String? {
        let combined = [state.runningStderr, state.runningStdout]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let lines = combined
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        guard let last = lines.last, !last.isEmpty else { return nil }
        return last
    }

    private func addCompactRunningLine(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, to container: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: x, y: y, width: w, height: 16)
        container.addSubview(label)
    }

    private func addRunningLabel(_ title: String, value: String, y: inout CGFloat, w: CGFloat, to container: NSView) {
        let label = NSTextField(labelWithString: "\(title): \(value)")
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.frame = NSRect(x: 54, y: y, width: w - 68, height: 18)
        container.addSubview(label)
        y += 20
    }

    private func addRunningTextBlock(title: String, text: String, color: NSColor, height: CGFloat, y: inout CGFloat, w: CGFloat, to container: NSView) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 10)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(x: 54, y: y, width: w - 68, height: 14)
        container.addSubview(titleLabel)
        y += 16

        let scroll = NSScrollView(frame: NSRect(x: 54, y: y, width: w - 68, height: height))
        let doc = NSTextView(frame: NSRect(x: 0, y: 0, width: w - 68, height: height))
        doc.string = text
        doc.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        doc.isEditable = false
        doc.drawsBackground = false
        doc.textColor = color
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        container.addSubview(scroll)
        y += height + 10
    }

    private func addDoneState(result: CommandResult, y: CGFloat, w: CGFloat) -> CGFloat {
        let height: CGFloat = 86
        let container = NSView(frame: NSRect(x: padding, y: y, width: w, height: height))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.cardBackground(in: view), in: view)
        container.layer?.borderWidth = 1
        container.layer?.borderColor = WinegoldTheme.layerColor(WinegoldTheme.border(in: view), in: view)

        let (iconName, iconColor) = iconFor(status: result.status)
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil)!)
        icon.contentTintColor = iconColor
        icon.frame = NSRect(x: 18, y: 28, width: 30, height: 30)
        container.addSubview(icon)

        let titleText: String
        switch result.status {
        case .success: titleText = result.completionMessage ?? "Done"
        case .failed: titleText = "Failed"
        case .timeout: titleText = "Timed out"
        case .cancelled: titleText = "Cancelled"
        default: titleText = result.status.rawValue.capitalized
        }
        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 64, y: 22, width: w - 150, height: 22)
        container.addSubview(title)

        let inputName = result.inputFiles.first.map { URL(fileURLWithPath: $0).lastPathComponent }
        let detailParts = [result.actionName, inputName].compactMap { $0 }
        let detail = NSTextField(labelWithString: detailParts.joined(separator: " · "))
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.frame = NSRect(x: 64, y: 46, width: w - 150, height: 18)
        container.addSubview(detail)

        let info = NSButton(title: "ⓘ", target: self, action: #selector(toggleTechnicalDetails))
        info.isBordered = false
        info.font = .systemFont(ofSize: 15)
        info.frame = NSRect(x: w - 42, y: 26, width: 28, height: 28)
        info.toolTip = "Technical details"
        container.addSubview(info)

        if showsTechnicalDetails {
            container.frame.size.height = 178
            let cy: CGFloat = 80
            let technical = [
                result.exitCode.map { "exit code: \($0)" },
                result.stdout.isEmpty ? nil : "stdout: \(result.stdout)",
                result.stderr.isEmpty ? nil : "stderr: \(result.stderr)"
            ].compactMap { $0 }.joined(separator: "\n")
            let details = NSTextField(wrappingLabelWithString: technical.isEmpty ? "No technical details." : technical)
            details.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            details.textColor = .secondaryLabelColor
            details.frame = NSRect(x: 64, y: cy, width: w - 82, height: 86)
            container.addSubview(details)
        }

        contentView.addSubview(container)
        return container.frame.height + 18
    }

    private func addResult(result: CommandResult, y: CGFloat, w: CGFloat) -> CGFloat {
        var cy: CGFloat = 0

        let container = NSView(frame: NSRect(x: padding, y: y, width: w, height: 60))
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.statusBackground(in: view), in: view)
        container.layer?.borderWidth = 1
        container.layer?.borderColor = WinegoldTheme.layerColor(WinegoldTheme.border(in: view), in: view)

        let (iconName, iconColor) = iconFor(status: result.status)
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil)!)
        icon.frame = NSRect(x: 10, y: cy + 22, width: 20, height: 20)
        icon.contentTintColor = iconColor
        container.addSubview(icon)

        let resultTitle = result.inputFiles.first.map { "\(result.actionName) - \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? result.actionName
        let name = NSTextField(labelWithString: resultTitle)
        name.font = .boldSystemFont(ofSize: 13)
        name.frame = NSRect(x: 38, y: cy + 24, width: 200, height: 18)
        container.addSubview(name)

        let statusText = NSTextField(labelWithString: result.status.rawValue.capitalized)
        statusText.font = .systemFont(ofSize: 11)
        statusText.textColor = iconColor
        statusText.alignment = .right
        statusText.frame = NSRect(x: w - 104, y: cy + 24, width: 88, height: 18)
        container.addSubview(statusText)
        cy += 46

        if !result.stdout.isEmpty {
            let outLabel = NSTextField(labelWithString: "Output")
            outLabel.font = .systemFont(ofSize: 10)
            outLabel.textColor = .secondaryLabelColor
            outLabel.frame = NSRect(x: 10, y: cy, width: w - 20, height: 14)
            container.addSubview(outLabel)
            cy += 16

            let scroll = NSScrollView(frame: NSRect(x: 10, y: cy, width: w - 20, height: 60))
            let doc = NSTextView(frame: NSRect(x: 0, y: 0, width: w - 20, height: 60))
            doc.string = result.stdout
            doc.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            doc.isEditable = false
            doc.drawsBackground = false
            doc.textColor = .labelColor
            scroll.documentView = doc
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            container.addSubview(scroll)
            cy += 64
        }

        if !result.stderr.isEmpty {
            let errLabel = NSTextField(labelWithString: "Error")
            errLabel.font = .systemFont(ofSize: 10)
            errLabel.textColor = .secondaryLabelColor
            errLabel.frame = NSRect(x: 10, y: cy, width: w - 20, height: 14)
            container.addSubview(errLabel)
            cy += 16

            let scroll = NSScrollView(frame: NSRect(x: 10, y: cy, width: w - 20, height: 40))
            let doc = NSTextView(frame: NSRect(x: 0, y: 0, width: w - 20, height: 40))
            doc.string = result.stderr
            doc.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            doc.textColor = .systemRed
            doc.isEditable = false
            doc.drawsBackground = false
            scroll.documentView = doc
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            container.addSubview(scroll)
            cy += 44
        }

        if let code = result.exitCode {
            let codeLabel = NSTextField(labelWithString: "Exit code: \(code)")
            codeLabel.font = .systemFont(ofSize: 10)
            codeLabel.textColor = .secondaryLabelColor
            codeLabel.frame = NSRect(x: 10, y: cy, width: w - 20, height: 14)
            container.addSubview(codeLabel)
            cy += 18
        }

        for path in result.outputFiles {
            let btn = NSButton(title: "Open output", target: self, action: #selector(openFile(_:)))
            btn.setButtonType(.momentaryPushIn)
            btn.bezelStyle = .rounded
            btn.controlSize = .small
            btn.frame = NSRect(x: 10, y: cy, width: 100, height: 20)
            btn.filePath = path
            container.addSubview(btn)
            cy += 26
        }

        container.frame.size.height = max(cy + 16, 60)
        contentView.addSubview(container)
        return container.frame.height + 16
    }

    private func addBatchResultsSection(y: inout CGFloat, w: CGFloat) {
        let label = sectionLabel("Batch results")
        label.frame.origin = CGPoint(x: padding, y: y)
        contentView.addSubview(label)
        y += 18
        for result in state.batchResults {
            y += addResult(result: result, y: y, w: w)
        }
    }

    private func addSavedSection(y: inout CGFloat, w: CGFloat) {
        let label = sectionLabel("Saved")
        label.frame.origin = CGPoint(x: padding, y: y)
        contentView.addSubview(label)
        y += 24

        for item in state.savedHistory.prefix(5) {
            let row = RecentActionRowView(
                item: item,
                isSaved: true,
                showsSaveButton: false,
                onRerun: { [weak self] historyItem in self?.rerun(historyItem) },
                onView: { [weak self] historyItem in self?.viewResult(historyItem) },
                onSave: { _ in }
            )
            row.frame = NSRect(x: padding, y: y, width: w, height: 52)
            contentView.addSubview(row)
            y += 60
        }
        y += 4
    }

    private func addHistorySection(y: inout CGFloat, w: CGFloat) {
        let label = sectionLabel("Recent")
        label.frame.origin = CGPoint(x: padding, y: y)
        contentView.addSubview(label)
        y += 24

        for item in state.history.prefix(5) {
            let row = RecentActionRowView(
                item: item,
                isSaved: state.savedHistoryIds.contains(item.id),
                showsSaveButton: true,
                onRerun: { [weak self] historyItem in self?.rerun(historyItem) },
                onView: { [weak self] historyItem in self?.viewResult(historyItem) },
                onSave: { [weak self] historyItem in self?.toggleSaved(historyItem) }
            )
            row.frame = NSRect(x: padding, y: y, width: w, height: 52)
            contentView.addSubview(row)
            y += 60
        }
        y += 4
    }


    private func matchingHistory(_ items: [RunHistoryItem]) -> [RunHistoryItem] {
        let query = actionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state.files.isEmpty, !query.isEmpty else { return items }
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return items.filter { item in
            [item.actionName, item.parentRecipeName, item.childActionName, item.inputFiles.joined(separator: " ")]
                .compactMap { $0 }
                .contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(needle) }
        }
    }

    private func toggleSaved(_ item: RunHistoryItem) {
        onToggleSavedRun(item)
    }

    private func viewResult(_ item: RunHistoryItem) {
        state.lastResult = CommandResult(
            id: item.id,
            actionId: item.actionId,
            actionName: item.actionName,
            parentRecipeID: item.parentRecipeID,
            childActionID: item.childActionID,
            parentRecipeName: item.parentRecipeName,
            childActionName: item.childActionName,
            inputFiles: item.inputFiles,
            outputFiles: item.outputFiles,
            status: item.status,
            exitCode: item.exitCode,
            stdout: item.stdout,
            stderr: item.stderr,
            startedAt: item.startedAt,
            endedAt: item.endedAt
        )
        state.clearRunningDetails()
        state.isCompact = false
        refresh()
    }

    private func rerun(_ item: RunHistoryItem) {
        let resolution = SavedRunResolver().resolve(item, actions: state.allActions)
        guard case let .available(action) = resolution else {
            logMsg("[PanelVC] rerun unavailable: This action no longer exists in its recipe.")
            return
        }

        let files = item.inputFiles.map { URL(fileURLWithPath: $0) }
        guard !files.isEmpty else {
            logMsg("[PanelVC] rerun failed, no input files: \(item.actionName)")
            return
        }

        state.files = files
        state.actions = ActionMatcher().matchingActions(for: files, actions: state.allActions)
        state.lastResult = nil
        state.batchResults = []
        state.activeActionId = action.id
        state.clearRunningDetails()
        state.isCompact = false
        refresh()
        startRun(action: action, files: files)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.sizeToFit()
        return label
    }

    private func iconFor(status: ExecutionStatus) -> (String, NSColor) {
        switch status {
        case .success: return ("checkmark.circle.fill", .systemGreen)
        case .failed, .timeout: return ("xmark.circle.fill", .systemRed)
        case .cancelled: return ("minus.circle.fill", .systemOrange)
        case .running: return ("arrow.triangle.2.circlepath", .systemBlue)
        case .pending: return ("clock", .secondaryLabelColor)
        }
    }

    @objc private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        let panelWindow = view.window as? ActionPanelWindow
        panelWindow?.beginModalInteraction()
        let response = panel.runModal()
        if response == .OK {
            setDraggedFiles(panel.urls)
        }
        panelWindow?.endModalInteraction()
    }

    @objc private func toggleRecentRuns() {
        showsRecentRuns.toggle()
        refresh()
    }

    @objc private func toggleTechnicalDetails() {
        showsTechnicalDetails.toggle()
        refresh()
    }

    @objc private func helpClicked() {
        NSWorkspace.shared.open(URL(string: "https://github.com/arthurlacoste/winegold/blob/main/docs/scripting.md")!)
    }

    @objc private func settingsClicked() { onOpenSettings() }

    @objc private func openFile(_ sender: NSButton) {
        if let path = sender.filePath {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
    }
}

private var filePathKey: UInt8 = 0

extension NSButton {
    var filePath: String? {
        get { objc_getAssociatedObject(self, &filePathKey) as? String }
        set { objc_setAssociatedObject(self, &filePathKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}



private final class PanelFooterBarView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = WinegoldTheme.layerColor(
            WinegoldTheme.panelBackground(in: self),
            alpha: 0.96,
            in: self
        )
        layer?.borderWidth = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = WinegoldTheme.layerColor(
            WinegoldTheme.panelBackground(in: self),
            alpha: 0.96,
            in: self
        )
    }
}

private final class PanelActionListView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.cardBackground(in: self), in: self)
        layer?.borderWidth = 1
        layer?.borderColor = WinegoldTheme.layerColor(WinegoldTheme.border(in: self), in: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.cardBackground(in: self), in: self)
        layer?.borderColor = WinegoldTheme.layerColor(WinegoldTheme.border(in: self), in: self)
    }
}

private final class PanelDropZoneView: NSView {
    override var isFlipped: Bool { true }
    var onFilesDropped: (([URL]) -> Void)?
    var onFilesPreviewed: (([URL]) -> Void)?
    var onDraggingChanged: ((Bool) -> Void)?
    var onChooseFiles: (() -> Void)?
    private var isPressed = false { didSet { applyStyle() } }
    var isHighlighted = false { didSet { applyStyle() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes(DragFileReader.supportedTypes)
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyle()
    }

    private func applyStyle() {
        layer?.cornerRadius = 14
        let emphasized = isHighlighted || isPressed
        layer?.borderWidth = emphasized ? 1.5 : 1
        let borderColor = emphasized ? NSColor.controlAccentColor.withAlphaComponent(0.55) : WinegoldTheme.border(in: self)
        let backgroundColor = emphasized ? NSColor.controlAccentColor.withAlphaComponent(0.08) : WinegoldTheme.cardBackground(in: self)
        layer?.borderColor = WinegoldTheme.layerColor(borderColor, in: self)
        layer?.backgroundColor = WinegoldTheme.layerColor(backgroundColor, in: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard onChooseFiles != nil else { return super.hitTest(point) }
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onChooseFiles != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        onChooseFiles != nil
    }

    override func mouseDown(with event: NSEvent) {
        guard onChooseFiles != nil else { return super.mouseDown(with: event) }
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard onChooseFiles != nil else { return super.mouseUp(with: event) }
        defer { isPressed = false }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onChooseFiles?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesPreviewed?(files) }
        onDraggingChanged?(true)
        isHighlighted = true
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesPreviewed?(files) }
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDraggingChanged?(false); isHighlighted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = DragFileReader.urls(from: sender)
        onDraggingChanged?(false)
        isHighlighted = false
        if !files.isEmpty { onFilesDropped?(files) }
        return !files.isEmpty
    }
}

private final class PanelDropView: NSView {
    override var isFlipped: Bool { true }
    var onFilesDropped: (([URL]) -> Void)?
    var onFilesPreviewed: (([URL]) -> Void)?
    var onDraggingChanged: ((Bool) -> Void)?
    var onAppearanceChanged: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(DragFileReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesPreviewed?(files) }
        onDraggingChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesPreviewed?(files) }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onDraggingChanged?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = DragFileReader.urls(from: sender)
        onDraggingChanged?(false)
        if !files.isEmpty { onFilesDropped?(files) }
        return !files.isEmpty
    }
}


private final class DropForwardingScrollView: NSScrollView {
    var onFilesDropped: (([URL]) -> Void)?
    var onFilesPreviewed: (([URL]) -> Void)?
    var onDraggingChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(DragFileReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.rowBackground(in: self), in: self)
        layer?.borderColor = WinegoldTheme.layerColor(WinegoldTheme.border(in: self), in: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesPreviewed?(files) }
        onDraggingChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesPreviewed?(files) }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onDraggingChanged?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = DragFileReader.urls(from: sender)
        onDraggingChanged?(false)
        if !files.isEmpty { onFilesDropped?(files) }
        return !files.isEmpty
    }
}

private final class RecentActionRowView: NSView {
    override var isFlipped: Bool { true }

    private let item: RunHistoryItem
    private let isSaved: Bool
    private let showsSaveButton: Bool
    private let onRerun: (RunHistoryItem) -> Void
    private let onView: (RunHistoryItem) -> Void
    private let onSave: (RunHistoryItem) -> Void

    private let dot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let saveCard = NSView()
    private let saveIcon = NSImageView()
    private let viewCard = NSView()
    private let viewIcon = NSImageView()
    private let runCard = NSView()
    private let runIcon = NSImageView()

    init(
        item: RunHistoryItem,
        isSaved: Bool,
        showsSaveButton: Bool,
        onRerun: @escaping (RunHistoryItem) -> Void,
        onView: @escaping (RunHistoryItem) -> Void,
        onSave: @escaping (RunHistoryItem) -> Void
    ) {
        self.item = item
        self.isSaved = isSaved
        self.showsSaveButton = showsSaveButton
        self.onRerun = onRerun
        self.onView = onView
        self.onSave = onSave
        super.init(frame: NSRect(x: 0, y: 0, width: 312, height: 52))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = WinegoldTheme.layerColor(WinegoldTheme.rowBackground(in: self), in: self)
        layer?.borderWidth = 1
        layer?.borderColor = WinegoldTheme.layerColor(WinegoldTheme.border(in: self), in: self)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let rowWidth = bounds.width
        let rightInset: CGFloat = 10
        let buttonSize = HistoryActionButtonStyle.size
        let runCardX = max(230, rowWidth - rightInset - buttonSize.width)
        let viewCardX = runCardX - buttonSize.width - HistoryActionButtonStyle.spacing
        let saveCardX = viewCardX - (showsSaveButton ? buttonSize.width + HistoryActionButtonStyle.spacing : 0)
        let timeX = max(164, saveCardX - 52)
        let labelWidth = max(80, timeX - 42)

        dot.frame = NSRect(x: 12, y: 22, width: 8, height: 8)
        nameLabel.frame = NSRect(x: 30, y: 9, width: labelWidth, height: 18)
        subtitleLabel.frame = NSRect(x: 30, y: 29, width: labelWidth, height: 16)
        timeLabel.frame = NSRect(x: timeX, y: 9, width: 42, height: 18)
        let buttonY = (bounds.height - buttonSize.height) / 2
        saveCard.frame = NSRect(origin: NSPoint(x: saveCardX, y: buttonY), size: buttonSize)
        saveIcon.frame = saveCard.frame
        viewCard.frame = NSRect(origin: NSPoint(x: viewCardX, y: buttonY), size: buttonSize)
        viewIcon.frame = viewCard.frame
        runCard.frame = NSRect(origin: NSPoint(x: runCardX, y: buttonY), size: buttonSize)
        runIcon.frame = runCard.frame
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        layer?.borderWidth = 1.5
        layer?.borderColor = WinegoldTheme.layerColor(.controlAccentColor, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            layer?.borderWidth = 1
            layer?.borderColor = WinegoldTheme.layerColor(WinegoldTheme.border(in: self), in: self)
        }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if showsSaveButton, saveCard.frame.contains(point) {
            logMsg("[RecentActionRowView] save: \(item.actionName)")
            onSave(item)
            return
        }
        if viewCard.frame.contains(point) {
            logMsg("[RecentActionRowView] view: \(item.actionName)")
            onView(item)
            return
        }
        logMsg("[RecentActionRowView] rerun: \(item.actionName)")
        onRerun(item)
    }

    private func setup() {
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        switch item.status {
        case .success: dot.layer?.backgroundColor = WinegoldTheme.layerColor(.systemGreen, in: dot)
        case .failed, .timeout: dot.layer?.backgroundColor = WinegoldTheme.layerColor(.systemRed, in: dot)
        default: dot.layer?.backgroundColor = WinegoldTheme.layerColor(.systemOrange, in: dot)
        }
        addSubview(dot)

        nameLabel.stringValue = item.actionName
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        let subtitleText = item.inputFiles.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No file"
        subtitleLabel.stringValue = subtitleText
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleLabel)

        timeLabel.stringValue = item.startedAt.formatted(date: .omitted, time: .shortened)
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        addSubview(timeLabel)

        if showsSaveButton {
            HistoryActionButtonStyle.configureCard(saveCard, backgroundColor: nil)
            addSubview(saveCard)

            HistoryActionButtonStyle.configureIcon(
                saveIcon,
                symbolName: isSaved ? "bookmark.fill" : "bookmark",
                accessibilityDescription: "Save",
                tintColor: .systemYellow
            )
            addSubview(saveIcon)
        }

        HistoryActionButtonStyle.configureCard(
            viewCard,
            backgroundColor: HistoryActionButtonStyle.eyeBackgroundColor
        )
        addSubview(viewCard)

        HistoryActionButtonStyle.configureIcon(
            viewIcon,
            symbolName: "eye",
            accessibilityDescription: "View result",
            tintColor: HistoryActionButtonStyle.eyeTintColor
        )
        addSubview(viewIcon)

        HistoryActionButtonStyle.configureCard(
            runCard,
            backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12)
        )
        addSubview(runCard)

        HistoryActionButtonStyle.configureIcon(
            runIcon,
            symbolName: "arrow.clockwise",
            accessibilityDescription: "Rerun",
            tintColor: .controlAccentColor
        )
        addSubview(runIcon)
    }
}
