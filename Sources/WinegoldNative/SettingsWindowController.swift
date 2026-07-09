import Cocoa
import WinegoldCore

class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let actionStore: ActionStore
    private let onLaunchAtLoginChanged: (Bool) -> Void

    init(store: SettingsStore, actionStore: ActionStore, onLaunchAtLoginChanged: @escaping (Bool) -> Void) {
        self.store = store
        self.actionStore = actionStore
        self.onLaunchAtLoginChanged = onLaunchAtLoginChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
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
            onLaunchAtLoginChanged: onLaunchAtLoginChanged
        )
        window.contentViewController = vc

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
    private let onLaunchAtLoginChanged: (Bool) -> Void

    private var launchAtLoginCheckbox: NSButton!
    private var notificationsCheckbox: NSButton!
    private var shortcutField: NSTextField!
    private var actionPopup: NSPopUpButton!
    private var nameField: NSTextField!
    private var extensionsField: NSTextField!
    private var commandTextView: NSTextView!
    private var testDropView: SettingsTestDropView!
    private var testResultTextView: NSTextView!
    private var selectedActionID: UUID?
    private var actions: [Action] = []

    init(store: SettingsStore, actionStore: ActionStore, onLaunchAtLoginChanged: @escaping (Bool) -> Void) {
        self.store = store
        self.actionStore = actionStore
        self.onLaunchAtLoginChanged = onLaunchAtLoginChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func loadView() {
        view = FlippedSettingsView(frame: NSRect(x: 0, y: 0, width: 760, height: 720))
        view.wantsLayer = true
        view.layer?.backgroundColor = WinegoldTheme.panelBackground(in: view).cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        reloadActions()
    }

    private func buildUI() {
        let padding: CGFloat = 24
        var y: CGFloat = 22
        let w = view.bounds.width - padding * 2

        let title = NSTextField(labelWithString: "Settings")
        title.font = .boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: padding, y: y, width: 240, height: 28)
        view.addSubview(title)
        y += 42

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginCheckbox.state = store.launchAtLogin ? .on : .off
        launchAtLoginCheckbox.frame = NSRect(x: padding, y: y, width: 200, height: 24)
        view.addSubview(launchAtLoginCheckbox)

        notificationsCheckbox = NSButton(checkboxWithTitle: "Show notifications", target: self, action: #selector(notificationsChanged))
        notificationsCheckbox.state = store.showNotifications ? .on : .off
        notificationsCheckbox.frame = NSRect(x: padding + 220, y: y, width: 200, height: 24)
        view.addSubview(notificationsCheckbox)

        let shortcutLabel = NSTextField(labelWithString: "Show panel shortcut")
        shortcutLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.frame = NSRect(x: padding + 430, y: y + 3, width: 130, height: 18)
        view.addSubview(shortcutLabel)

        shortcutField = NSTextField(frame: NSRect(x: padding + 560, y: y - 1, width: 130, height: 24))
        shortcutField.stringValue = store.showPanelShortcut
        shortcutField.target = self
        shortcutField.action = #selector(shortcutChanged)
        view.addSubview(shortcutField)

        y += 42

        addDivider(y: y, x: padding, width: w)
        y += 24

        let scriptTitle = NSTextField(labelWithString: "Scripts / actions")
        scriptTitle.font = .boldSystemFont(ofSize: 17)
        scriptTitle.frame = NSRect(x: padding, y: y, width: 220, height: 24)
        view.addSubview(scriptTitle)

        let hint = NSTextField(labelWithString: "Edit shell actions. .add.yml files can be imported from here, or by dragging them into Winegold.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: padding + 170, y: y + 3, width: w - 170, height: 20)
        view.addSubview(hint)
        y += 38

        actionPopup = NSPopUpButton(frame: NSRect(x: padding, y: y, width: 300, height: 28), pullsDown: false)
        actionPopup.target = self
        actionPopup.action = #selector(actionSelectionChanged)
        view.addSubview(actionPopup)

        let newButton = NSButton(title: "New", target: self, action: #selector(newAction))
        newButton.bezelStyle = .rounded
        newButton.frame = NSRect(x: padding + 312, y: y, width: 70, height: 28)
        view.addSubview(newButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: padding + 392, y: y, width: 70, height: 28)
        view.addSubview(saveButton)

        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteAction))
        deleteButton.bezelStyle = .rounded
        deleteButton.frame = NSRect(x: padding + 472, y: y, width: 78, height: 28)
        view.addSubview(deleteButton)

        let importButton = NSButton(title: "Import YAML…", target: self, action: #selector(importYAML))
        importButton.bezelStyle = .rounded
        importButton.frame = NSRect(x: padding + 560, y: y, width: 120, height: 28)
        view.addSubview(importButton)
        y += 38

        let exportButton = NSButton(title: "Export YAML…", target: self, action: #selector(exportYAML))
        exportButton.bezelStyle = .rounded
        exportButton.frame = NSRect(x: padding, y: y, width: 120, height: 28)
        view.addSubview(exportButton)

        let promptButton = NSButton(title: "Help prompt", target: self, action: #selector(openHelpPrompt))
        promptButton.bezelStyle = .rounded
        promptButton.frame = NSRect(x: padding + 132, y: y, width: 120, height: 28)
        view.addSubview(promptButton)

        let helpLine = NSTextField(labelWithString: "Export the selected action, or ask ChatGPT to improve the current script.")
        helpLine.font = .systemFont(ofSize: 12)
        helpLine.textColor = .secondaryLabelColor
        helpLine.frame = NSRect(x: padding + 266, y: y + 5, width: w - 266, height: 18)
        view.addSubview(helpLine)
        y += 48

        addFormLabel("Name", x: padding, y: y)
        nameField = NSTextField(frame: NSRect(x: padding + 110, y: y - 2, width: w - 110, height: 26))
        view.addSubview(nameField)
        y += 38

        addFormLabel("Extensions", x: padding, y: y)
        extensionsField = NSTextField(frame: NSRect(x: padding + 110, y: y - 2, width: w - 110, height: 26))
        extensionsField.placeholderString = "jpg, png, webp or *"
        view.addSubview(extensionsField)
        y += 38

        addFormLabel("Command", x: padding, y: y)
        let scroll = NSScrollView(frame: NSRect(x: padding + 110, y: y - 2, width: w - 110, height: 170))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        commandTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: w - 124, height: 170))
        commandTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        commandTextView.isAutomaticQuoteSubstitutionEnabled = false
        commandTextView.isAutomaticDashSubstitutionEnabled = false
        commandTextView.string = ""
        scroll.documentView = commandTextView
        view.addSubview(scroll)
        y += 186

        let placeholderHelp = NSTextField(labelWithString: "Placeholders: {input}, {parent}, {filename}, {basename}, {extension}, {dotExtension}, {inside}, {desktop}, {downloads}, {timestamp}.")
        placeholderHelp.font = .systemFont(ofSize: 11)
        placeholderHelp.textColor = .tertiaryLabelColor
        placeholderHelp.lineBreakMode = .byWordWrapping
        placeholderHelp.frame = NSRect(x: padding + 110, y: y, width: w - 110, height: 36)
        view.addSubview(placeholderHelp)
        y += 52

        addFormLabel("Test", x: padding, y: y)
        testDropView = SettingsTestDropView(frame: NSRect(x: padding + 110, y: y - 2, width: 220, height: 72))
        testDropView.onFilesDropped = { [weak self] files in
            self?.testCurrentAction(with: files)
        }
        view.addSubview(testDropView)

        let resultScroll = NSScrollView(frame: NSRect(x: padding + 344, y: y - 2, width: w - 344, height: 72))
        resultScroll.hasVerticalScroller = true
        resultScroll.autohidesScrollers = true
        resultScroll.borderType = .bezelBorder
        testResultTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: w - 360, height: 72))
        testResultTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        testResultTextView.isEditable = false
        testResultTextView.string = "Drop a file here to test the selected script."
        resultScroll.documentView = testResultTextView
        view.addSubview(resultScroll)
    }

    private func addDivider(y: CGFloat, x: CGFloat, width: CGFloat) {
        let line = NSView(frame: NSRect(x: x, y: y, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        view.addSubview(line)
    }

    private func addFormLabel(_ text: String, x: CGFloat, y: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: x, y: y + 2, width: 100, height: 20)
        view.addSubview(label)
    }

    func refreshActions() {
        let selected = selectedActionID
        reloadActions(select: selected)
    }

    func prepareNewScriptTemplate(for files: [URL]) {
        clearForm()
        let extensions = inferredExtensions(from: files)
        let extensionLabel = extensions.joined(separator: ", ")
        nameField.stringValue = defaultScriptName(for: extensions)
        extensionsField.stringValue = extensionLabel.isEmpty ? "*" : extensionLabel
        commandTextView.string = defaultScriptCommand(for: extensions)
        testResultTextView.string = files.isEmpty
            ? "New script template created. Drop a file here to test it."
            : "New script template for: \(files.map { $0.lastPathComponent }.joined(separator: ", "))"
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
        actions = (try? actionStore.listActions()) ?? []
        actionPopup.removeAllItems()
        for action in actions {
            actionPopup.addItem(withTitle: action.name)
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
        selectedActionID = action.id
        nameField.stringValue = action.name
        extensionsField.stringValue = action.acceptedExtensions.joined(separator: ", ")
        commandTextView.string = shellCommand(for: action)
    }

    private func clearForm() {
        selectedActionID = nil
        nameField.stringValue = ""
        extensionsField.stringValue = "*"
        commandTextView.string = ""
    }

    private func shellCommand(for action: Action) -> String {
        if action.executablePath == "/bin/zsh", action.argumentsTemplate.first == "-lc", action.argumentsTemplate.count >= 2 {
            return action.argumentsTemplate.dropFirst().joined(separator: " ")
        }
        return ([action.executablePath] + action.argumentsTemplate).joined(separator: " ")
    }

    private func formAction(existing: Action? = nil) -> Action? {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = commandTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensions = extensionsField.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !name.isEmpty, !command.isEmpty, !extensions.isEmpty else { return nil }

        return Action(
            id: existing?.id ?? UUID(),
            name: name,
            description: existing?.description ?? "User script",
            iconName: existing?.iconName ?? "terminal",
            enabled: existing?.enabled ?? true,
            acceptedExtensions: extensions,
            acceptedUTIs: existing?.acceptedUTIs ?? [],
            executablePath: "/bin/zsh",
            argumentsTemplate: ["-lc", command],
            workingDirectoryTemplate: existing?.workingDirectoryTemplate,
            outputPathTemplate: existing?.outputPathTemplate,
            requiresConfirmation: existing?.requiresConfirmation ?? false,
            timeoutSeconds: existing?.timeoutSeconds ?? 120,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }


    private func currentEditedAction() -> Action? {
        let existing = selectedActionID.flatMap { id in actions.first { $0.id == id } }
        return formAction(existing: existing)
    }

    private func yamlString(for action: Action) -> String {
        let command = shellCommand(for: action)
        let extensions = action.acceptedExtensions.isEmpty ? ["*"] : action.acceptedExtensions
        let extLines = extensions.map { "    - \(yamlScalar($0))" }.joined(separator: "\n")
        return """
        name: \(yamlScalar(action.name))
        trigger:
          fileExtension:
        \(extLines)
        cmd:
          exec: \(yamlScalar(command))
        """
    }

    private func yamlScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return "'\(escaped)'"
    }

    private func filenameSlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let slug = String(scalars).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? "winegold-action" : slug
    }

    private func currentExtensions() -> [String] {
        extensionsField.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
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

    private func testCurrentAction(with files: [URL]) {
        guard let action = currentEditedAction() else {
            showMessage("Name, extensions and command are required before testing.")
            return
        }
        guard let file = files.first else { return }
        testResultTextView.string = "Running \(action.name) on \(file.lastPathComponent)…"

        let resolver = ActionTemplateResolver()
        let args = resolver.resolve(argumentsTemplate: action.argumentsTemplate, for: file)
        let wd = resolver.resolve(workingDirectoryTemplate: action.workingDirectoryTemplate, for: file)
        let request = CommandExecutionRequest(
            executablePath: action.executablePath,
            arguments: args,
            workingDirectory: wd,
            timeoutSeconds: action.timeoutSeconds
        )

        Task {
            var result = await CommandRunner().run(request: request)
            result.actionId = action.id
            result.actionName = action.name
            result.inputFiles = [file.path]
            let output = testOutputText(result: result)
            await MainActor.run {
                self.testResultTextView.string = output
            }
        }
    }

    private func testOutputText(result: CommandResult) -> String {
        var parts: [String] = []
        parts.append("Status: \(result.status.rawValue)")
        if let exitCode = result.exitCode { parts.append("Exit: \(exitCode)") }
        if !result.stdout.isEmpty { parts.append("\nstdout:\n\(result.stdout)") }
        if !result.stderr.isEmpty { parts.append("\nstderr:\n\(result.stderr)") }
        return parts.joined(separator: "\n")
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
            showMessage("Name, extensions and command are required.")
            return
        }

        do {
            if existing == nil {
                try actionStore.createAction(action)
            } else {
                try actionStore.updateAction(action)
            }
            reloadActions(select: action.id)
        } catch {
            showMessage("Save failed: \(error.localizedDescription)")
        }
    }

    @objc private func deleteAction() {
        guard let selectedActionID else { return }
        do {
            try actionStore.deleteAction(id: selectedActionID)
            reloadActions()
        } catch {
            showMessage("Delete failed: \(error.localizedDescription)")
        }
    }

    @objc private func importYAML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["yml", "yaml"]
        guard panel.runModal() == .OK else { return }

        let importer = LegacyActionImporter()
        var importedNames: [String] = []
        do {
            for url in panel.urls {
                let imported = try importer.importActions(from: url)
                for action in imported {
                    _ = try actionStore.upsertActionByName(action)
                    try actionStore.deleteDuplicateActionsByName(keeping: action.name)
                    importedNames.append(action.name)
                }
            }
            reloadActions()
            showMessage("Imported: \(importedNames.joined(separator: ", "))")
        } catch {
            showMessage("Import failed: \(error.localizedDescription)")
        }
    }


    @objc private func exportYAML() {
        guard let action = currentEditedAction() else {
            showMessage("Name, extensions and command are required before exporting.")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Winegold YAML"
        panel.nameFieldStringValue = "\(filenameSlug(action.name)).add.yml"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try yamlString(for: action).write(to: url, atomically: true, encoding: .utf8)
            showMessage("Exported: \(url.lastPathComponent)")
        } catch {
            showMessage("Export failed: \(error.localizedDescription)")
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
        testResultTextView.string = "Help prompt copied to clipboard. Paste it into ChatGPT."
    }

    @objc private func launchAtLoginChanged() {
        let enabled = launchAtLoginCheckbox.state == .on
        store.launchAtLogin = enabled
        onLaunchAtLoginChanged(enabled)
    }

    @objc private func notificationsChanged() {
        store.showNotifications = notificationsCheckbox.state == .on
    }

    @objc private func shortcutChanged() {
        store.showPanelShortcut = shortcutField.stringValue
        shortcutField.stringValue = store.showPanelShortcut
    }
}


private final class SettingsTestDropView: NSView {
    override var isFlipped: Bool { true }
    var onFilesDropped: (([URL]) -> Void)?
    private let label = NSTextField(labelWithString: "Drop test file")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        registerForDraggedTypes(DragFileReader.supportedTypes)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 10, y: (bounds.height - 20) / 2, width: bounds.width - 20, height: 20)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingExited(nil)
        let files = DragFileReader.urls(from: sender)
        guard !files.isEmpty else { return false }
        onFilesDropped?(files)
        return true
    }
}

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}
