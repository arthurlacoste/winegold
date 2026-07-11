import Cocoa
import WinegoldCore
import WinegoldUI
import UniformTypeIdentifiers

class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let actionStore: ActionStore
    private let recipeCoordinator: RecipeCoordinator?
    private let variableStore: RecipeVariableStore?
    private let keychainStore: KeychainSecretStore?
    private let onLaunchAtLoginChanged: (Bool) -> Void
    private let onShortcutChanged: () -> Void
    private let onPanelSideChanged: (PanelSide) -> Void
    private let onConfigurationChanged: () -> Void

    init(store: SettingsStore, actionStore: ActionStore, recipeCoordinator: RecipeCoordinator?, variableStore: RecipeVariableStore? = nil, keychainStore: KeychainSecretStore? = nil, onLaunchAtLoginChanged: @escaping (Bool) -> Void, onShortcutChanged: @escaping () -> Void, onPanelSideChanged: @escaping (PanelSide) -> Void, onConfigurationChanged: @escaping () -> Void = {}) {
        self.store = store
        self.actionStore = actionStore
        self.recipeCoordinator = recipeCoordinator
        self.variableStore = variableStore
        self.keychainStore = keychainStore
        self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
        self.onShortcutChanged = onShortcutChanged
        self.onPanelSideChanged = onPanelSideChanged
        self.onConfigurationChanged = onConfigurationChanged

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Winegold Settings"
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.center()

        let vc = SettingsViewController(
            store: store,
            actionStore: actionStore,
            recipeCoordinator: recipeCoordinator,
            variableStore: variableStore,
            keychainStore: keychainStore,
            onLaunchAtLoginChanged: onLaunchAtLoginChanged,
            onShortcutChanged: onShortcutChanged,
            onPanelSideChanged: onPanelSideChanged,
            onConfigurationChanged: onConfigurationChanged
        )
        window.contentViewController = vc
        window.onSaveShortcut = { [weak vc] in vc?.saveFromShortcut() }

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func show() {
        refreshActions()
        window?.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func refreshActions() {
        (window?.contentViewController as? SettingsViewController)?.refreshActions()
    }

    func showNewScriptTemplate(for files: [URL]) {
        show()
        (window?.contentViewController as? SettingsViewController)?.prepareNewScriptTemplate(for: files)
    }
}

class SettingsViewController: NSViewController {
    private var store: SettingsStore
    private let actionStore: ActionStore
    private let recipeCoordinator: RecipeCoordinator?
    private let variableStore: RecipeVariableStore?
    private let keychainStore: KeychainSecretStore?
    private let onLaunchAtLoginChanged: (Bool) -> Void
    private let onShortcutChanged: () -> Void
    private let onPanelSideChanged: (PanelSide) -> Void
    private let onConfigurationChanged: () -> Void

    private var launchAtLoginCheckbox: NSButton!
    private var notificationsCheckbox: NSButton!
    private var shortcutField: NSTextField!
    private var panelSideControl: NSSegmentedControl!
    private var actionPopup: NSPopUpButton!
    private var nameField: NSTextField!
    private var triggerEditor: TriggerEditorView!
    private var successMessageField: NSTextField!
    private var commandTextView: NSTextView!
    private var selectedActionID: UUID?
    private var selectedRecipeIssuePath: URL?
    private var actions: [Action] = []
    private var recipeIssues: [RecipeIndexEntry] = []
    private var issuePopup: NSPopUpButton!
    private var issueLabel: NSTextField!
    private var configurationStack: NSStackView?
    private var needsSetupBadge: NSTextField?
    private var settingsContentView: FlippedSettingsView!

    init(store: SettingsStore, actionStore: ActionStore, recipeCoordinator: RecipeCoordinator?, variableStore: RecipeVariableStore? = nil, keychainStore: KeychainSecretStore? = nil, onLaunchAtLoginChanged: @escaping (Bool) -> Void, onShortcutChanged: @escaping () -> Void, onPanelSideChanged: @escaping (PanelSide) -> Void, onConfigurationChanged: @escaping () -> Void = {}) {
        self.store = store
        self.actionStore = actionStore
        self.recipeCoordinator = recipeCoordinator
        self.variableStore = variableStore
        self.keychainStore = keychainStore
        self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
        self.onShortcutChanged = onShortcutChanged
        self.onPanelSideChanged = onPanelSideChanged
        self.onConfigurationChanged = onConfigurationChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 900))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        settingsContentView = FlippedSettingsView(frame: NSRect(x: 0, y: 0, width: 760, height: 1180))
        settingsContentView.wantsLayer = true
        settingsContentView.layer?.backgroundColor = WinegoldTheme.panelBackground(in: settingsContentView).cgColor
        scrollView.documentView = settingsContentView
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadActions()
    }

    private func buildUI() {
        let padding: CGFloat = 24
        var y: CGFloat = 22
        let w = settingsContentView.bounds.width - padding * 2

        let title = NSTextField(labelWithString: "Settings")
        title.font = .boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: padding, y: y, width: 240, height: 28)
        settingsContentView.addSubview(title)
        y += 42

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginCheckbox.state = store.launchAtLogin ? .on : .off
        launchAtLoginCheckbox.frame = NSRect(x: padding, y: y, width: 200, height: 24)
        settingsContentView.addSubview(launchAtLoginCheckbox)

        notificationsCheckbox = NSButton(checkboxWithTitle: "Show notifications", target: self, action: #selector(notificationsChanged))
        notificationsCheckbox.state = store.showNotifications ? .on : .off
        notificationsCheckbox.frame = NSRect(x: padding + 220, y: y, width: 200, height: 24)
        settingsContentView.addSubview(notificationsCheckbox)

        let shortcutLabel = NSTextField(labelWithString: "Show panel shortcut")
        shortcutLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.frame = NSRect(x: padding + 430, y: y + 3, width: 130, height: 18)
        settingsContentView.addSubview(shortcutLabel)

        shortcutField = NSTextField(frame: NSRect(x: padding + 560, y: y - 1, width: 130, height: 24))
        shortcutField.stringValue = store.showPanelShortcut
        shortcutField.target = self
        shortcutField.action = #selector(shortcutChanged)
        settingsContentView.addSubview(shortcutField)

        y += 42

        panelSideControl = NSSegmentedControl(labels: ["Left", "Right"], trackingMode: .selectOne, target: self, action: #selector(panelSideChanged))
        panelSideControl.selectedSegment = store.panelSide == .left ? 0 : 1
        panelSideControl.frame = NSRect(x: padding, y: y, width: 170, height: 26)
        settingsContentView.addSubview(panelSideControl)

        let panelSideLabel = NSTextField(labelWithString: "Bottom panel side")
        panelSideLabel.font = .systemFont(ofSize: 12)
        panelSideLabel.textColor = .secondaryLabelColor
        panelSideLabel.frame = NSRect(x: padding + 184, y: y + 4, width: 150, height: 18)
        settingsContentView.addSubview(panelSideLabel)
        y += 40
        addDivider(y: y, x: padding, width: w)
        y += 24

        let scriptTitle = NSTextField(labelWithString: "Scripts / actions")
        scriptTitle.font = .boldSystemFont(ofSize: 17)
        scriptTitle.frame = NSRect(x: padding, y: y, width: 220, height: 24)
        settingsContentView.addSubview(scriptTitle)

        let hint = NSTextField(labelWithString: "Edit .wg.yml recipes. Files and folders can be installed here or by dragging them into Winegold.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: padding + 170, y: y + 3, width: w - 170, height: 20)
        settingsContentView.addSubview(hint)
        y += 38

        actionPopup = NSPopUpButton(frame: NSRect(x: padding, y: y, width: 300, height: 28), pullsDown: false)
        actionPopup.target = self
        actionPopup.action = #selector(actionSelectionChanged)
        settingsContentView.addSubview(actionPopup)

        let newButton = NSButton(title: "New", target: self, action: #selector(newAction))
        newButton.bezelStyle = .rounded
        newButton.frame = NSRect(x: padding + 312, y: y, width: 70, height: 28)
        settingsContentView.addSubview(newButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: padding + 392, y: y, width: 70, height: 28)
        settingsContentView.addSubview(saveButton)

        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteAction))
        deleteButton.bezelStyle = .rounded
        deleteButton.frame = NSRect(x: padding + 472, y: y, width: 78, height: 28)
        settingsContentView.addSubview(deleteButton)

        let revealButton = NSButton(title: "Reveal", target: self, action: #selector(revealRecipe))
        revealButton.bezelStyle = .rounded
        revealButton.frame = NSRect(x: padding + 560, y: y, width: 72, height: 28)
        settingsContentView.addSubview(revealButton)

        let importButton = NSButton(title: "Install…", target: self, action: #selector(importYAML))
        importButton.bezelStyle = .rounded
        importButton.frame = NSRect(x: padding + 638, y: y, width: 82, height: 28)
        settingsContentView.addSubview(importButton)
        y += 38

        issuePopup = NSPopUpButton(frame: NSRect(x: padding, y: y, width: 300, height: 26), pullsDown: false)
        issuePopup.target = self
        issuePopup.action = #selector(recipeIssueChanged)
        settingsContentView.addSubview(issuePopup)
        issueLabel = NSTextField(labelWithString: "")
        issueLabel.textColor = .systemRed
        issueLabel.font = .systemFont(ofSize: 11)
        issueLabel.lineBreakMode = .byTruncatingMiddle
        issueLabel.frame = NSRect(x: padding + 312, y: y + 3, width: w - 312, height: 20)
        settingsContentView.addSubview(issueLabel)
        y += 36

        let promptButton = NSButton(title: "Help prompt", target: self, action: #selector(openHelpPrompt))
        promptButton.bezelStyle = .rounded
        promptButton.frame = NSRect(x: padding, y: y, width: 120, height: 28)
        settingsContentView.addSubview(promptButton)

        let helpLine = NSTextField(labelWithString: "Ask ChatGPT to improve the current recipe.")
        helpLine.font = .systemFont(ofSize: 12)
        helpLine.textColor = .secondaryLabelColor
        helpLine.frame = NSRect(x: padding + 134, y: y + 5, width: w - 134, height: 18)
        settingsContentView.addSubview(helpLine)
        y += 48

        addFormLabel("Name", x: padding, y: y)
        nameField = NSTextField(frame: NSRect(x: padding + 110, y: y - 2, width: w - 110, height: 26))
        settingsContentView.addSubview(nameField)
        y += 38

        addFormLabel("Trigger", x: padding, y: y)
        triggerEditor = TriggerEditorView(frame: NSRect(x: padding + 110, y: y - 2, width: w - 110, height: 210))
        settingsContentView.addSubview(triggerEditor)
        y += 220

        addFormLabel("On success", x: padding, y: y)
        successMessageField = NSTextField(frame: NSRect(x: padding + 110, y: y - 2, width: w - 110, height: 26))
        successMessageField.placeholderString = "Optional, e.g. Created {basename}.jpg"
        settingsContentView.addSubview(successMessageField)
        y += 38

        addFormLabel("Command", x: padding, y: y)
        let scroll = NSScrollView(frame: NSRect(x: padding + 110, y: y - 2, width: w - 110, height: 145))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        commandTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: w - 124, height: 145))
        commandTextView.font = NSFont(name: "Menlo", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        commandTextView.isRichText = false
        commandTextView.importsGraphics = false
        commandTextView.isHorizontallyResizable = false
        commandTextView.isVerticallyResizable = true
        commandTextView.textContainer?.widthTracksTextView = true
        commandTextView.textContainer?.containerSize = NSSize(width: w - 124, height: CGFloat.greatestFiniteMagnitude)
        commandTextView.isAutomaticQuoteSubstitutionEnabled = false
        commandTextView.isAutomaticDashSubstitutionEnabled = false
        commandTextView.string = ""
        scroll.documentView = commandTextView
        settingsContentView.addSubview(scroll)
        y += 160

        let placeholderHelp = NSTextField(labelWithString: "Placeholders: {input}, {parent}, {filename}, {basename}, {extension}, {dotExtension}, {inside}, {desktop}, {downloads}, {timestamp}, {recipeDir}.")
        placeholderHelp.font = .systemFont(ofSize: 11)
        placeholderHelp.textColor = .tertiaryLabelColor
        placeholderHelp.lineBreakMode = .byWordWrapping
        placeholderHelp.frame = NSRect(x: padding + 110, y: y, width: w - 250, height: 36)
        settingsContentView.addSubview(placeholderHelp)

        let docsButton = NSButton(title: "Open scripting docs", target: self, action: #selector(openScriptingDocs))
        docsButton.bezelStyle = .inline
        docsButton.frame = NSRect(x: padding + w - 130, y: y - 1, width: 130, height: 22)
        settingsContentView.addSubview(docsButton)
        y += 52

        addDivider(y: y, x: padding, width: w)
        y += 24

        let configTitle = NSTextField(labelWithString: "Configuration")
        configTitle.font = .boldSystemFont(ofSize: 17)
        configTitle.frame = NSRect(x: padding, y: y, width: 220, height: 24)
        settingsContentView.addSubview(configTitle)

        needsSetupBadge = NSTextField(labelWithString: "Needs setup")
        needsSetupBadge!.font = .systemFont(ofSize: 11, weight: .medium)
        needsSetupBadge!.textColor = .white
        needsSetupBadge!.wantsLayer = true
        needsSetupBadge!.layer?.backgroundColor = NSColor.systemOrange.cgColor
        needsSetupBadge!.layer?.cornerRadius = 4
        needsSetupBadge!.frame = NSRect(x: padding + 140, y: y + 3, width: 80, height: 18)
        needsSetupBadge!.alignment = .center
        needsSetupBadge!.isHidden = true
        settingsContentView.addSubview(needsSetupBadge!)
        y += 32

        configurationStack = NSStackView(frame: NSRect(x: padding + 110, y: y, width: w - 110, height: 200))
        configurationStack!.orientation = .vertical
        configurationStack!.alignment = .leading
        configurationStack!.spacing = 8
        configurationStack!.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        settingsContentView.addSubview(configurationStack!)
        y += 220
    }

    private func addDivider(y: CGFloat, x: CGFloat, width: CGFloat) {
        let line = NSView(frame: NSRect(x: x, y: y, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        settingsContentView.addSubview(line)
    }

    private func addFormLabel(_ text: String, x: CGFloat, y: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: x, y: y + 2, width: 100, height: 20)
        settingsContentView.addSubview(label)
    }

    func refreshActions() {
        let selected = selectedActionID
        reloadActions(select: selected)
    }

    func prepareNewScriptTemplate(for files: [URL]) {
        clearForm()
        let extensions = inferredExtensions(from: files)
        nameField.stringValue = defaultScriptName(for: extensions)
        triggerEditor.stringValue = extensionExpression(extensions)
        successMessageField.stringValue = ""
        commandTextView.string = defaultScriptCommand(for: extensions)
        nameField.becomeFirstResponder()
    }

    private func inferredExtensions(from files: [URL]) -> [String] {
        let values = files.map { file -> String in
            let ext = file.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !ext.isEmpty { return ext }
            if file.hasDirectoryPath { return "folder" }
            return "*"
        }
        let unique = Array(NSOrderedSet(array: values)) as? [String]
        return unique?.isEmpty == false ? unique! : ["*"]
    }

    private func defaultScriptName(for extensions: [String]) -> String {
        let label = extensions.filter { $0 != "*" }.joined(separator: ", ")
        if label.isEmpty { return "New Winegold script" }
        return "New \(label) script"
    }

    private func defaultScriptCommand(for extensions: [String]) -> String {
        let label = extensions.joined(separator: ", ")
        return """
        # New Winegold script for: \(label)
        # Available placeholders:
        # {input}, {parent}, {filename}, {basename}, {extension}, {dotExtension}, {inside}, {desktop}, {downloads}, {timestamp}

        echo "{input}"
        """
    }

    private func reloadActions(select idToSelect: UUID? = nil) {
        let available = (try? actionStore.listActions()) ?? []
        let needingSetup = (try? actionStore.listNeedingSetup()) ?? []
        actions = available + needingSetup.filter { pending in !available.contains(where: { $0.id == pending.id }) }
        recipeIssues = ((try? recipeCoordinator?.entries()) ?? []).filter { $0.status == "invalid" }
        issuePopup.removeAllItems()
        issuePopup.addItem(withTitle: recipeIssues.isEmpty ? "No recipe errors" : "Recipe errors (\(recipeIssues.count))")
        for issue in recipeIssues { issuePopup.addItem(withTitle: URL(fileURLWithPath: issue.path).lastPathComponent) }
        issuePopup.isEnabled = !recipeIssues.isEmpty
        issueLabel.stringValue = recipeIssues.first?.parseError ?? ""
        actionPopup.removeAllItems()
        for action in actions {
            let baseTitle = action.category.map { "\($0) / \(action.name)" } ?? action.name
            let title = needingSetup.contains(where: { $0.id == action.id }) ? "\(baseTitle) · Needs setup" : baseTitle
            actionPopup.addItem(withTitle: title)
            actionPopup.lastItem?.representedObject = action.id.uuidString
        }

        if let idToSelect, let index = actions.firstIndex(where: { $0.id == idToSelect }) {
            actionPopup.selectItem(at: index)
            loadAction(actions[index])
        } else if let first = actions.first {
            actionPopup.selectItem(at: 0)
            loadAction(first)
        } else {
            clearForm()
        }
    }

    private func loadAction(_ action: Action) {
        selectedRecipeIssuePath = nil
        selectedActionID = action.id
        nameField.stringValue = action.name
        triggerEditor.stringValue = action.triggerExpression ?? extensionExpression(action.acceptedExtensions)
        successMessageField.stringValue = action.successMessage ?? ""
        commandTextView.string = shellCommand(for: action)
        refreshConfiguration(for: action)
    }

    private func refreshConfiguration(for action: Action) {
        guard let stack = configurationStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        needsSetupBadge?.isHidden = true

        guard let recipeCoordinator, let variableStore, let keychainStore else {
            let label = NSTextField(labelWithString: "No variables.")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(label)
            return
        }

        guard let variables = recipeCoordinator.recipeVariables(for: action.id),
              let externalID = recipeCoordinator.recipeExternalID(for: action.id) else {
            let label = NSTextField(labelWithString: "No variables.")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(label)
            return
        }

        let resolver = RecipeVariableResolver(variableStore: variableStore, keychainStore: keychainStore)
        let resolved = resolver.resolve(variables: variables, externalID: externalID, appEnvironment: ProcessInfo.processInfo.environment)
        let setupStatus = resolver.setupStatus(variables: variables, externalID: externalID, appEnvironment: ProcessInfo.processInfo.environment)
        let consentMgr = RecipeConsentManager(variableStore: variableStore, keychainStore: keychainStore)
        let warnings = consentMgr.consentWarnings(variables: variables, externalID: externalID)

        if case .needsSetup = setupStatus {
            needsSetupBadge?.isHidden = false
        }

        for variable in variables {
            let row = buildVariableRow(variable: variable, resolved: resolved, externalID: externalID, warnings: warnings)
            stack.addArrangedSubview(row)
        }

        stack.frame.size.height = stack.arrangedSubviews.reduce(CGFloat(0)) { $0 + $1.frame.height + 8 }
    }

    private func buildVariableRow(variable: RecipeVariable, resolved: [String: String], externalID: String, warnings: [String: String]) -> NSView {
        let rowHeight: CGFloat = variable.secret ? 56 : 32
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: rowHeight))

        let label = NSTextField(labelWithString: variable.label)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 0, y: rowHeight - 18, width: 160, height: 16)
        row.addSubview(label)

        if variable.required {
            let req = NSTextField(labelWithString: "Required")
            req.font = .systemFont(ofSize: 9, weight: .medium)
            req.textColor = .systemOrange
            req.frame = NSRect(x: 164, y: rowHeight - 17, width: 52, height: 14)
            row.addSubview(req)
        }

        if let warning = warnings[variable.name] {
            let warn = NSTextField(wrappingLabelWithString: warning)
            warn.font = .systemFont(ofSize: 10)
            warn.textColor = .systemOrange
            warn.frame = NSRect(x: 0, y: -4, width: 400, height: 14)
            row.addSubview(warn)
        }

        if variable.secret {
            let masked = NSTextField(labelWithString: resolved[variable.name] != nil ? "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}" : "Not set")
            masked.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            masked.textColor = resolved[variable.name] != nil ? .labelColor : .tertiaryLabelColor
            masked.frame = NSRect(x: 0, y: rowHeight - 38, width: 200, height: 18)
            row.addSubview(masked)

            let source = configSourceLabel(variable: variable, resolved: resolved, externalID: externalID)
            source.frame = NSRect(x: 204, y: rowHeight - 38, width: 80, height: 18)
            row.addSubview(source)

            let replaceButton = NSButton(title: resolved[variable.name] != nil ? "Replace secret" : "Set up", target: self, action: #selector(setupVariable(_:)))
            replaceButton.bezelStyle = .rounded
            replaceButton.controlSize = .small
            replaceButton.tag = configTagFor(variable: variable)
            replaceButton.frame = NSRect(x: 290, y: rowHeight - 40, width: 100, height: 22)
            row.addSubview(replaceButton)

            if resolved[variable.name] != nil {
                let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeVariable(_:)))
                removeButton.bezelStyle = .rounded
                removeButton.controlSize = .small
                removeButton.tag = configTagFor(variable: variable)
                removeButton.frame = NSRect(x: 0, y: rowHeight - 56, width: 70, height: 18)
                row.addSubview(removeButton)
            }
        } else {
            let valueField = NSTextField(frame: NSRect(x: 0, y: rowHeight - 28, width: 240, height: 22))
            valueField.stringValue = resolved[variable.name] ?? variable.defaultValue ?? ""
            valueField.placeholderString = variable.defaultValue ?? "Value"
            valueField.font = .systemFont(ofSize: 11)
            valueField.tag = configTagFor(variable: variable)
            valueField.target = self
            valueField.action = #selector(variableFieldChanged(_:))
            row.addSubview(valueField)

            let source = configSourceLabel(variable: variable, resolved: resolved, externalID: externalID)
            source.frame = NSRect(x: 244, y: rowHeight - 26, width: 80, height: 18)
            row.addSubview(source)

            if resolved[variable.name] != nil && variable.defaultValue == nil {
                let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeVariable(_:)))
                removeButton.bezelStyle = .rounded
                removeButton.controlSize = .small
                removeButton.tag = configTagFor(variable: variable)
                removeButton.frame = NSRect(x: 330, y: rowHeight - 28, width: 70, height: 22)
                row.addSubview(removeButton)
            }
        }

        return row
    }

    private func configSourceLabel(variable: RecipeVariable, resolved: [String: String], externalID: String) -> NSTextField {
        let text: String
        if variable.secret {
            let privateKey = RecipeVariableResolver.privateSecretStorageKey(variable: variable.name, externalID: externalID)
            if keychainStore?.read(key: privateKey) != nil {
                text = "Winegold"
            } else if let sharedKey = variable.key,
                      variableStore?.consentStatus(key: sharedKey, externalID: externalID) == true,
                      keychainStore?.read(key: RecipeVariableResolver.sharedSecretStorageKey(sharedKey)) != nil {
                text = "Winegold"
            } else if let envVal = ProcessInfo.processInfo.environment[variable.name], !envVal.isEmpty {
                text = "Inherited environment"
            } else {
                text = "Not set"
            }
        } else if variableStore?.readOverride(externalID: externalID, variableName: variable.name) != nil {
            text = "Winegold"
        } else if let envVal = ProcessInfo.processInfo.environment[variable.name], !envVal.isEmpty {
            text = "Inherited environment"
        } else if variable.defaultValue != nil {
            text = "YAML default"
        } else {
            text = "Not set"
        }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func configTagFor(variable: RecipeVariable) -> Int {
        variable.name.hashValue & 0x7FFFFFFF
    }

    private func promptForSecret(label: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Set up \(label)"
        alert.informativeText = "Enter the required value. Winegold will store it in macOS Keychain."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "Required value"
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    @objc private func setupVariable(_ sender: NSButton) {
        guard let actionID = selectedActionID,
              let recipeCoordinator,
              let variableStore,
              let keychainStore,
              let variables = recipeCoordinator.recipeVariables(for: actionID),
              let externalID = recipeCoordinator.recipeExternalID(for: actionID),
              let variable = variables.first(where: { configTagFor(variable: $0) == sender.tag }),
              variable.secret else { return }

        if let sharedKey = variable.key {
            let sharedStorageKey = RecipeVariableResolver.sharedSecretStorageKey(sharedKey)
            let sharedExists = keychainStore.read(key: sharedStorageKey) != nil
            let hasConsent = variableStore.consentStatus(key: sharedKey, externalID: externalID)

            if sharedExists && !hasConsent {
                let alert = NSAlert()
                alert.messageText = "Shared required value"
                alert.informativeText = "This recipe requests access to your saved \"\(variable.label)\". You can approve access or enter a separate value for this recipe."
                alert.addButton(withTitle: "Use saved value")
                alert.addButton(withTitle: "Enter separate value")
                alert.addButton(withTitle: "Cancel")
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    variableStore.grantConsent(key: sharedKey, externalID: externalID)
                case .alertSecondButtonReturn:
                    guard let value = promptForSecret(label: variable.label) else { return }
                    variableStore.savePrivateSecret(externalID: externalID, variableName: variable.name, value: value, keychainStore: keychainStore)
                default:
                    return
                }
            } else {
                guard let value = promptForSecret(label: variable.label) else { return }
                variableStore.saveSharedSecret(key: sharedKey, externalID: externalID, value: value, keychainStore: keychainStore)
            }
        } else {
            guard let value = promptForSecret(label: variable.label) else { return }
            variableStore.savePrivateSecret(externalID: externalID, variableName: variable.name, value: value, keychainStore: keychainStore)
        }

        finishConfigurationChange(actionID: actionID)
    }

    private func finishConfigurationChange(actionID: UUID) {
        do {
            try recipeCoordinator?.reconcile()
            reloadActions(select: actionID)
            onConfigurationChanged()
        } catch {
            showMessage("Configuration failed: \(error.localizedDescription)")
        }
    }

    @objc private func variableFieldChanged(_ sender: NSTextField) {
        guard let actionID = selectedActionID,
              let recipeCoordinator,
              let variableStore,
              let variables = recipeCoordinator.recipeVariables(for: actionID),
              let externalID = recipeCoordinator.recipeExternalID(for: actionID) else { return }
        let variable = variables.first { configTagFor(variable: $0) == sender.tag }
        guard let variable else { return }

        let value = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            variableStore.deleteOverride(externalID: externalID, variableName: variable.name)
        } else {
            variableStore.writeOverride(externalID: externalID, variableName: variable.name, value: value)
        }
        finishConfigurationChange(actionID: actionID)
    }

    @objc private func removeVariable(_ sender: NSButton) {
        guard let actionID = selectedActionID,
              let recipeCoordinator,
              let variableStore,
              let keychainStore,
              let variables = recipeCoordinator.recipeVariables(for: actionID),
              let externalID = recipeCoordinator.recipeExternalID(for: actionID),
              let variable = variables.first(where: { configTagFor(variable: $0) == sender.tag }) else { return }

        if variable.secret {
            let privateKey = RecipeVariableResolver.privateSecretStorageKey(variable: variable.name, externalID: externalID)
            if keychainStore.read(key: privateKey) != nil {
                keychainStore.delete(key: privateKey)
            } else if let sharedKey = variable.key {
                variableStore.revokeConsent(key: sharedKey, externalID: externalID)
            }
        } else {
            variableStore.deleteOverride(externalID: externalID, variableName: variable.name)
        }
        finishConfigurationChange(actionID: actionID)
    }

    private func clearForm() {
        selectedActionID = nil
        selectedRecipeIssuePath = nil
        nameField.stringValue = ""
        triggerEditor.stringValue = "extension in {\"*\"}"
        successMessageField.stringValue = ""
        commandTextView.string = ""
    }

    private func shellCommand(for action: Action) -> String {
        if action.executablePath == "/bin/zsh", action.argumentsTemplate.first == "-lc", action.argumentsTemplate.count >= 2 {
            return action.argumentsTemplate.dropFirst().joined(separator: " ")
        }
        return ([action.executablePath] + action.argumentsTemplate).joined(separator: " ")
    }

    private func formAction(existing: Action? = nil) -> Action? {
        let commandText = commandTextView.string
        if let pastedAction = actionFromPastedYAML(commandText, existing: existing) {
            return pastedAction
        }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensions = currentExtensions()
        let trigger = triggerEditor.stringValue
        let successMessage = normalizedSuccessMessage()

        guard !name.isEmpty, !command.isEmpty, (try? TriggerParser().parse(trigger)) != nil else { return nil }

        return Action(
            id: existing?.id ?? UUID(),
            name: name,
            description: existing?.description ?? "User script",
            iconName: existing?.iconName ?? "terminal",
            enabled: existing?.enabled ?? true,
            acceptedExtensions: extensions,
            acceptedUTIs: existing?.acceptedUTIs ?? [],
            triggerExpression: trigger,
            executablePath: "/bin/zsh",
            argumentsTemplate: ["-lc", command],
            workingDirectoryTemplate: existing?.workingDirectoryTemplate,
            outputPathTemplate: existing?.outputPathTemplate,
            successMessage: successMessage,
            requiresConfirmation: existing?.requiresConfirmation ?? false,
            timeoutSeconds: existing?.timeoutSeconds ?? 120,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    private func actionFromPastedYAML(_ text: String, existing: Action?) -> Action? {
        guard looksLikeWinegoldYAML(text), var action = try? LegacyActionImporter().importLegacyYAML(text, sourceName: "pasted.add.yml") else {
            return nil
        }

        action.id = existing?.id ?? action.id
        action.description = existing?.description ?? action.description
        action.enabled = existing?.enabled ?? true
        action.acceptedUTIs = existing?.acceptedUTIs ?? []
        action.requiresConfirmation = existing?.requiresConfirmation ?? false
        action.timeoutSeconds = existing?.timeoutSeconds ?? action.timeoutSeconds
        action.isFavorite = existing?.isFavorite ?? false
        action.displayOrder = existing?.displayOrder ?? 0
        action.createdAt = existing?.createdAt ?? action.createdAt
        action.successMessage = normalizedSuccessMessage() ?? action.successMessage
        action.updatedAt = Date()
        return action
    }

    private func looksLikeWinegoldYAML(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return lines.contains { $0.hasPrefix("name:") }
            && lines.contains { $0.hasPrefix("trigger:") }
            && lines.contains("cmd:")
            && lines.contains { $0.hasPrefix("exec:") }
    }


    private func normalizedSuccessMessage() -> String? {
        let value = successMessageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func currentExtensions() -> [String] {
        guard let parsed = try? TriggerParser().parse(triggerEditor.stringValue),
              case let .condition(field, op, value) = parsed, field == "extension", op == .in,
              case let .collection(values) = value else { return [] }
        return values
    }

    private func extensionExpression(_ extensions: [String]) -> String {
        let values = extensions.isEmpty ? ["*"] : extensions
        return TriggerSerializer().serialize(.condition(field: "extension", operator: .in, value: .collection(values)))
    }

    private func helpPromptFromForm() -> String {
        ScriptingHelpPrompt.make(
            scriptName: nameField.stringValue,
            extensions: currentExtensions(),
            command: commandTextView.string
        )
    }

    private func chatGPTURL() -> URL? {
        URL(string: "https://chatgpt.com/")
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    @objc private func actionSelectionChanged() {
        guard actionPopup.indexOfSelectedItem >= 0, actionPopup.indexOfSelectedItem < actions.count else { return }
        loadAction(actions[actionPopup.indexOfSelectedItem])
    }

    @objc private func newAction() {
        clearForm()
        nameField.becomeFirstResponder()
    }

    @objc private func saveAction() {
        let existing = selectedActionID.flatMap { id in actions.first { $0.id == id } }
        guard let action = formAction(existing: existing) else {
            showMessage("Name, a valid trigger, and command are required.")
            return
        }

        do {
            if let issuePath = selectedRecipeIssuePath, let recipeCoordinator {
                try recipeCoordinator.repairInvalidRecipe(at: issuePath, action: action)
                selectedRecipeIssuePath = nil
                reloadActions()
            } else if let recipeCoordinator {
                try recipeCoordinator.save(action: action)
                reloadActions(select: action.id)
            } else if existing == nil {
                try actionStore.createAction(action)
                reloadActions(select: action.id)
            } else {
                try actionStore.updateAction(action)
                reloadActions(select: action.id)
            }
        } catch {
            showMessage("Save failed: \(error.localizedDescription)")
        }
    }

    @objc private func deleteAction() {
        guard let selectedActionID else { return }
        do {
            if let recipeCoordinator {
                try recipeCoordinator.delete(actionID: selectedActionID)
            } else {
                try actionStore.deleteAction(id: selectedActionID)
            }
            reloadActions()
        } catch {
            showMessage("Delete failed: \(error.localizedDescription)")
        }
    }

    @objc private func revealRecipe() {
        if let selectedActionID, let url = try? recipeCoordinator?.path(for: selectedActionID) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let issue = selectedRecipeIssue() {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: issue.path)])
        }
    }

    @objc private func recipeIssueChanged() {
        guard let issue = selectedRecipeIssue() else {
            issueLabel.stringValue = ""
            return
        }
        issueLabel.stringValue = issue.parseError ?? ""
        let path = URL(fileURLWithPath: issue.path)
        guard let draft = try? recipeCoordinator?.repairDraft(at: path) else { return }
        selectedActionID = nil
        selectedRecipeIssuePath = path
        nameField.stringValue = draft.name
        triggerEditor.stringValue = draft.trigger
        successMessageField.stringValue = draft.successMessage ?? ""
        commandTextView.string = draft.command
        needsSetupBadge?.isHidden = true
        configurationStack?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let note = NSTextField(labelWithString: "Repair this recipe, then Save.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .systemOrange
        configurationStack?.addArrangedSubview(note)
    }

    private func selectedRecipeIssue() -> RecipeIndexEntry? {
        let index = issuePopup.indexOfSelectedItem - 1
        guard index >= 0, index < recipeIssues.count else { return recipeIssues.first }
        return recipeIssues[index]
    }

    @objc private func importYAML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["yml", "yaml"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }

        let importer = LegacyActionImporter()
        var importedNames: [String] = []
        do {
            for url in panel.urls {
                if let recipeCoordinator {
                    let summary = try recipeCoordinator.install(url)
                    importedNames.append(contentsOf: summary.recipeNames)
                } else {
                    let imported = try importer.importActions(from: url)
                    for action in imported {
                        _ = try actionStore.upsertActionByName(action)
                        importedNames.append(action.name)
                    }
                }
            }
            reloadActions()
            showMessage("Imported: \(importedNames.joined(separator: ", "))")
        } catch {
            showMessage("Import failed: \(error.localizedDescription)")
        }
    }


    @objc private func openHelpPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(helpPromptFromForm(), forType: .string)

        if let url = chatGPTURL() {
            view.window?.orderBack(nil)
            NSWorkspace.shared.open(url)
        }
        showMessage("Help prompt copied to clipboard. Paste it into ChatGPT.")
    }

    func saveFromShortcut() {
        shortcutChanged()
        notificationsChanged()
        launchAtLoginChanged()
        saveAction()
    }

    @objc private func openScriptingDocs() {
        guard let docsURL = URL(string: "https://github.com/arthurlacoste/winegold/blob/main/docs/scripting.md") else { return }
        NSWorkspace.shared.open(docsURL)
    }

    @objc private func launchAtLoginChanged() {
        let enabled = launchAtLoginCheckbox.state == .on
        store.launchAtLogin = enabled
        onLaunchAtLoginChanged(enabled)
    }

    @objc private func notificationsChanged() {
        store.showNotifications = notificationsCheckbox.state == .on
    }

    @objc private func panelSideChanged() {
        let side: PanelSide = panelSideControl.selectedSegment == 0 ? .left : .right
        store.panelSide = side
        onPanelSideChanged(side)
    }

    @objc private func shortcutChanged() {
        store.showPanelShortcut = shortcutField.stringValue
        shortcutField.stringValue = store.showPanelShortcut
        onShortcutChanged()
    }
}


private final class SettingsWindow: NSWindow {
    var onSaveShortcut: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "s" {
            onSaveShortcut?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}
