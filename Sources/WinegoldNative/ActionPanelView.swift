import Cocoa
import WinegoldCore

class ActionPanelViewController: NSViewController {
    private let state: PanelState
    private let onRunAction: (Action, [URL]) -> Void
    private let onToggleSavedRun: (RunHistoryItem) -> Void
    private let onOpenSettings: () -> Void
    private let onToggleFavorite: (Action) -> Void
    private let onMoveAction: (Action, Action) -> Void
    private var cardViews: [ActionCardView] = []
    private var runGeneration = 0
    private var lastLayoutWidth: CGFloat = 0
    private var lastHadStatusArea = false
    private var isRefreshing = false
    private var lastFilesSignature = ""

    private let padding: CGFloat = 24
    private let scrollView = DropForwardingScrollView()
    private let contentView = PanelDropView(frame: .zero)

    init(
        state: PanelState,
        onRunAction: @escaping (Action, [URL]) -> Void,
        onToggleSavedRun: @escaping (RunHistoryItem) -> Void,
        onOpenSettings: @escaping () -> Void,
        onToggleFavorite: @escaping (Action) -> Void,
        onMoveAction: @escaping (Action, Action) -> Void
    ) {
        self.state = state
        self.onRunAction = onRunAction
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
        view.layer?.backgroundColor = WinegoldTheme.panelBackground(in: view).cgColor
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = WinegoldTheme.panelBackground(in: view).cgColor
        let fileDropHandler: ([URL]) -> Void = { [weak self] files in
            self?.setDraggedFiles(files)
        }
        (view as? PanelDropView)?.onFilesDropped = fileDropHandler
        scrollView.onFilesDropped = fileDropHandler
        contentView.onFilesDropped = fileDropHandler
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        logMsg("[PanelVC] viewDidLoad files=\(state.files.count) actions=\(state.actions.count)")
        applyTheme()
        buildUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyTheme()
        refresh(animatedStatusInsert: false)
    }

    private func applyTheme() {
        view.layer?.backgroundColor = WinegoldTheme.panelBackground(in: view).cgColor
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = WinegoldTheme.panelBackground(in: view).cgColor
        scrollView.drawsBackground = false
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyTheme()
        let width = view.bounds.width
        guard width > 0 else { return }
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
        let w: CGFloat = panelWidth - padding * 2

        if state.isCompact {
            if let result = state.lastResult {
                y += addResult(result: result, y: y, w: w)
            } else if let runningActionName = state.runningActionName {
                y += addLoading(actionName: runningActionName, y: y, w: w)
            } else {
                y += addLoading(actionName: "Action en cours", y: y, w: w)
            }
            installScrollView(panelWidth: panelWidth, contentHeight: max(y + 10, 98))
            return
        }

        addHeader(y: &y, w: w)
        addDivider(y: &y, w: w)

        if let result = state.lastResult {
            y += addResult(result: result, y: y, w: w)
        } else if let runningActionName = state.runningActionName {
            y += addLoading(actionName: runningActionName, y: y, w: w)
        }

        if state.files.isEmpty {
            addEmptyState(y: &y, w: w)
        } else {
            addFilesSection(y: &y, w: w)
            addActionsSection(y: &y, w: w)
        }

        if !state.savedHistory.isEmpty {
            y += 18
            addSavedSection(y: &y, w: w)
        }

        if !state.history.isEmpty {
            y += 18
            addHistorySection(y: &y, w: w)
        }

        installScrollView(panelWidth: panelWidth, contentHeight: max(y + 24, 520))
    }

    private func installScrollView(panelWidth: CGFloat, contentHeight: CGFloat) {
        contentView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: contentHeight)
        scrollView.documentView = contentView
        scrollView.hasVerticalScroller = !state.isCompact
        scrollView.autohidesScrollers = true
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        if scrollView.superview == nil {
            view.addSubview(scrollView)
        }
    }


    private func setDraggedFiles(_ files: [URL]) {
        guard !files.isEmpty else { return }
        let signature = files.map { $0.path }.joined(separator: "\n")
        let isSameDragPayload = signature == lastFilesSignature
        if isSameDragPayload, state.lastResult == nil, state.runningActionName == nil { return }
        lastFilesSignature = signature

        state.files = files
        state.actions = ActionMatcher().matchingActions(for: files, actions: state.allActions)
        state.lastResult = nil
        state.activeActionId = nil
        state.runningActionName = nil
        state.runningFiles = []
        state.isCompact = false
        refresh()
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
        let line = NSView(frame: NSRect(x: padding, y: y, width: w, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
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
        state.activeActionId = action.id
        state.runningActionName = nil
        state.runningFiles = files
        state.isCompact = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard self.runGeneration == generation else { return }
            guard self.state.lastResult == nil else { return }
            self.state.runningActionName = action.name
            self.refresh()
        }

        onRunAction(action, files)
    }

    private func addActionsSection(y: inout CGFloat, w: CGFloat) {
        let label = sectionLabel("Actions")
        label.frame.origin = CGPoint(x: padding, y: y)
        contentView.addSubview(label)
        y += 18

        if state.actions.isEmpty {
            let empty = NSTextField(labelWithString: "No compatible actions")
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            empty.frame = NSRect(x: padding, y: y, width: w, height: 20)
            contentView.addSubview(empty)
            y += 24
            return
        }

        for action in state.actions {
            let validator = ActionValidator()
            let status = validator.validate(action)
            let card = ActionCardView(
                action: action,
                status: status,
                isActive: state.activeActionId == action.id,
                onDrop: { [weak self] droppedFiles in
                    let files = droppedFiles.isEmpty ? (self?.state.files ?? []) : droppedFiles
                    logMsg("[PanelVC] onDrop action=\(action.name) files=\(files.map { $0.lastPathComponent })")
                    guard !files.isEmpty else { return }
                    self?.startRun(action: action, files: files)
                },
                onToggleFavorite: { [weak self] action in
                    self?.onToggleFavorite(action)
                },
                onMoveBefore: { [weak self] source, target in
                    self?.onMoveAction(source, target)
                }
            )
            card.frame = NSRect(x: padding, y: y, width: w, height: 64)
            contentView.addSubview(card)
            cardViews.append(card)
            y += 76
        }
    }

    private func addLoading(actionName: String, y: CGFloat, w: CGFloat) -> CGFloat {
        let container = NSView(frame: NSRect(x: padding, y: y, width: w, height: 74))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = WinegoldTheme.cardBackground(in: view, emphasized: true).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor

        let spinner = NSProgressIndicator(frame: NSRect(x: 14, y: 20, width: 28, height: 28))
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        let title = NSTextField(labelWithString: "Running…")
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.textColor = .controlTextColor
        title.frame = NSRect(x: 54, y: 15, width: w - 70, height: 20)
        container.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Running action: \(actionName)")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.frame = NSRect(x: 54, y: 37, width: w - 70, height: 18)
        container.addSubview(subtitle)

        contentView.addSubview(container)
        return 90
    }

    private func addResult(result: CommandResult, y: CGFloat, w: CGFloat) -> CGFloat {
        var cy: CGFloat = 0

        let container = NSView(frame: NSRect(x: padding, y: y, width: w, height: 60))
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = WinegoldTheme.statusBackground(in: view).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = WinegoldTheme.border(in: view).cgColor

        let (iconName, iconColor) = iconFor(status: result.status)
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil)!)
        icon.frame = NSRect(x: 10, y: cy + 22, width: 20, height: 20)
        icon.contentTintColor = iconColor
        container.addSubview(icon)

        let name = NSTextField(labelWithString: result.actionName)
        name.font = .boldSystemFont(ofSize: 13)
        name.frame = NSRect(x: 38, y: cy + 24, width: 200, height: 18)
        container.addSubview(name)

        let statusText = NSTextField(labelWithString: result.status.rawValue.capitalized)
        statusText.font = .systemFont(ofSize: 11)
        statusText.textColor = iconColor
        statusText.frame = NSRect(x: w - 80, y: cy + 24, width: 80, height: 18)
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

        container.frame.size.height = min(max(cy + 10, 60), 190)
        contentView.addSubview(container)
        return container.frame.height + 16
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

    private func toggleSaved(_ item: RunHistoryItem) {
        onToggleSavedRun(item)
    }

    private func viewResult(_ item: RunHistoryItem) {
        state.lastResult = CommandResult(
            id: item.id,
            actionId: item.actionId,
            actionName: item.actionName,
            inputFiles: item.inputFiles,
            outputFiles: item.outputFiles,
            status: item.status,
            exitCode: item.exitCode,
            stdout: item.stdout,
            stderr: item.stderr,
            startedAt: item.startedAt,
            endedAt: item.endedAt
        )
        state.runningActionName = nil
        state.runningFiles = []
        state.isCompact = false
        refresh()
    }

    private func rerun(_ item: RunHistoryItem) {
        let action = state.allActions.first { $0.id == item.actionId }
            ?? state.allActions.first { $0.name == item.actionName }
        guard let action else {
            logMsg("[PanelVC] rerun failed, action not found: \(item.actionName)")
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
        state.activeActionId = action.id
        state.isCompact = false
        refresh()
        startRun(action: action, files: files)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
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


private final class PanelDropView: NSView {
    override var isFlipped: Bool { true }
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(DragFileReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesDropped?(files) }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesDropped?(files) }
        return !files.isEmpty
    }
}


private final class DropForwardingScrollView: NSScrollView {
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(DragFileReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let files = DragFileReader.urls(from: sender)
        if !files.isEmpty { onFilesDropped?(files) }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = DragFileReader.urls(from: sender)
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
        layer?.backgroundColor = WinegoldTheme.rowBackground(in: self).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = WinegoldTheme.border(in: self).cgColor
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let rowWidth = bounds.width
        let rightInset: CGFloat = 10
        let buttonWidth: CGFloat = 28
        let runCardX = max(230, rowWidth - rightInset - buttonWidth)
        let viewCardX = runCardX - 36
        let saveCardX = viewCardX - (showsSaveButton ? 36 : 0)
        let timeX = max(164, saveCardX - 52)
        let labelWidth = max(80, timeX - 42)

        dot.frame = NSRect(x: 12, y: 22, width: 8, height: 8)
        nameLabel.frame = NSRect(x: 30, y: 9, width: labelWidth, height: 18)
        subtitleLabel.frame = NSRect(x: 30, y: 29, width: labelWidth, height: 16)
        timeLabel.frame = NSRect(x: timeX, y: 9, width: 42, height: 18)
        saveCard.frame = NSRect(x: saveCardX, y: 10, width: buttonWidth, height: 32)
        saveIcon.frame = NSRect(x: saveCardX + 7, y: 18, width: 14, height: 14)
        viewCard.frame = NSRect(x: viewCardX, y: 10, width: buttonWidth, height: 32)
        viewIcon.frame = NSRect(x: viewCardX + 7, y: 18, width: 14, height: 14)
        runCard.frame = NSRect(x: runCardX, y: 10, width: buttonWidth, height: 32)
        runIcon.frame = NSRect(x: runCardX + 7, y: 18, width: 14, height: 14)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            layer?.borderWidth = 1
            layer?.borderColor = WinegoldTheme.border(in: self).cgColor
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
        case .success: dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        case .failed, .timeout: dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        default: dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
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
            saveCard.wantsLayer = true
            saveCard.layer?.cornerRadius = 9
            saveCard.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(isSaved ? 0.22 : 0.10).cgColor
            saveCard.layer?.borderWidth = 1
            saveCard.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(isSaved ? 0.55 : 0.28).cgColor
            addSubview(saveCard)

            saveIcon.image = NSImage(systemSymbolName: isSaved ? "bookmark.fill" : "bookmark", accessibilityDescription: "Save")
            saveIcon.contentTintColor = .systemYellow
            addSubview(saveIcon)
        }

        viewCard.wantsLayer = true
        viewCard.layer?.cornerRadius = 9
        viewCard.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.10).cgColor
        viewCard.layer?.borderWidth = 1
        viewCard.layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.20).cgColor
        addSubview(viewCard)

        viewIcon.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "View result")
        viewIcon.contentTintColor = .secondaryLabelColor
        addSubview(viewIcon)

        runCard.wantsLayer = true
        runCard.layer?.cornerRadius = 9
        runCard.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        runCard.layer?.borderWidth = 1
        runCard.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
        addSubview(runCard)

        runIcon.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Rerun")
        runIcon.contentTintColor = .controlAccentColor
        addSubview(runIcon)
    }
}
