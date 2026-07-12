import Cocoa
import WinegoldCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private struct PendingSetupRun {
        let action: Action
        let files: [URL]
    }
    private enum PanelInvocation {
        case shortcut
        case menu
        case drag

        var staysOpen: Bool { self == .shortcut }
    }

    private var menuBarItem: NSStatusItem?
    private let settingsStore = SettingsStore()
    private var actionStore: ActionStore?
    private var runHistoryStore: RunHistoryStore?
    private let savedRunStore = SavedRunStore()
    private var screenEdgeService: ScreenEdgeService?
    private var actionPanelWindow: ActionPanelWindow?
    private var settingsWC: SettingsWindowController?
    private var database: Database?
    private var recipeCoordinator: RecipeCoordinator?
    private var remoteRecipeInstaller: RemoteRecipeInstaller?
    private var recipeWatcher: RecipeWatcher?
    private var globalHotKey: GlobalHotKey?
    private weak var showPanelMenuItem: NSMenuItem?
    private var variableStore: RecipeVariableStore?
    private var keychainStore: LocalSecretStore?
    private var pendingSetupRun: PendingSetupRun?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logMsg("[AppDelegate] app started")
        setupDatabase()
        setupMainMenu()
        setupMenuBar()
        setupGlobalHotKey()
        setupEdgeCatcher()
        if ProcessInfo.processInfo.environment["WINEGOLD_UI_TEST_SHOW_PANEL"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.showPanelFromShortcut()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let recipeCoordinator else { return }
        do {
            try recipeCoordinator.reconcile()
            settingsWC?.refreshActions()
            refreshPanelActions()
            completePendingSetupIfReady()
        } catch {
            logMsg("[AppDelegate] active recipe reconcile failed: \(error.localizedDescription)")
        }
    }

    private func setupDatabase() {
        logMsg("[AppDelegate] setupDatabase")
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("WinegoldNative")

            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let dbPath = appSupport.appendingPathComponent("winegold.db").path

            let db = try Database(path: dbPath)
            try Migrations(db: db).run()
            self.database = db

            let store = ActionStore(db: db)
            self.actionStore = store

            try migrateLegacyDefaultRows(store: store)

            let recipeRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".winegold/recipes", isDirectory: true)
            try LegacyRecipeMigrator(db: db, root: recipeRoot).migrateIfNeeded()
            let vStore = RecipeVariableStore(db: db)
            self.variableStore = vStore
            let kStore = LocalSecretStore()
            self.keychainStore = kStore
            let coordinator = RecipeCoordinator(root: recipeRoot, db: db, variableStore: vStore, keychainStore: kStore)
            self.recipeCoordinator = coordinator
            self.remoteRecipeInstaller = RemoteRecipeInstaller(root: recipeRoot, db: db)
            try coordinator.reconcile()
            try migrateDefaultRecipes(store: store, coordinator: coordinator)
            try ensureDefaultRecipes(store: store, coordinator: coordinator)
            let watcher = RecipeWatcher(root: recipeRoot) { [weak self] in
                guard let self else { return }
                do {
                    try self.recipeCoordinator?.reconcile()
                    DispatchQueue.main.async {
                        self.settingsWC?.refreshActions()
                        self.refreshPanelActions()
                    }
                } catch {
                    logMsg("[AppDelegate] recipe reconcile failed: \(error.localizedDescription)")
                }
            }
            try watcher.start()
            self.recipeWatcher = watcher

            self.runHistoryStore = RunHistoryStore(db: db)
        } catch {
            print("DB init error: \(error)")
        }
    }

    private func migrateLegacyDefaultRows(store: ActionStore) throws {
        let existing = try store.listActions()
        if let oldPrint = existing.first(where: { $0.name == "Print file path" }) {
            let updated = Action(
                id: oldPrint.id,
                name: "Print and clipboard",
                description: "Print the full file path and copy it to clipboard",
                iconName: "doc.on.clipboard",
                enabled: oldPrint.enabled,
                acceptedExtensions: ["*"],
                acceptedUTIs: oldPrint.acceptedUTIs,
                executablePath: "/bin/zsh",
                argumentsTemplate: ["-lc", "printf '%s\n' '{input}'; printf '%s' '{input}' | pbcopy"],
                workingDirectoryTemplate: oldPrint.workingDirectoryTemplate,
                outputPathTemplate: oldPrint.outputPathTemplate,
                requiresConfirmation: oldPrint.requiresConfirmation,
                timeoutSeconds: max(oldPrint.timeoutSeconds, 30),
                createdAt: oldPrint.createdAt,
                updatedAt: Date()
            )
            try store.updateAction(updated)
        }

        let afterPrintRename = try store.listActions()
        if let oldOpenFolder = afterPrintRename.first(where: { $0.name == "Ouvrir dossier" }) {
            let updated = Action(
                id: oldOpenFolder.id,
                name: "Open Folder",
                description: "Open parent folder in Finder",
                iconName: "folder",
                enabled: oldOpenFolder.enabled,
                acceptedExtensions: oldOpenFolder.acceptedExtensions,
                acceptedUTIs: oldOpenFolder.acceptedUTIs,
                executablePath: oldOpenFolder.executablePath,
                argumentsTemplate: oldOpenFolder.argumentsTemplate,
                workingDirectoryTemplate: oldOpenFolder.workingDirectoryTemplate,
                outputPathTemplate: oldOpenFolder.outputPathTemplate,
                requiresConfirmation: oldOpenFolder.requiresConfirmation,
                timeoutSeconds: oldOpenFolder.timeoutSeconds,
                isFavorite: oldOpenFolder.isFavorite,
                displayOrder: oldOpenFolder.displayOrder,
                createdAt: oldOpenFolder.createdAt,
                updatedAt: Date()
            )
            try store.updateAction(updated)
            try store.deleteDuplicateActionsByName(keeping: "Open Folder")
        }

    }

    private func migrateDefaultRecipes(store: ActionStore, coordinator: RecipeCoordinator) throws {
        let migrations: [(oldName: String, newAction: Action)] = [
            ("Install .add.yml script", DefaultActions.all.first { $0.name == DefaultActions.installRecipeName }!),
            ("Print file path", DefaultActions.all.first { $0.name == "Print and clipboard" }!),
            ("Ouvrir dossier", DefaultActions.all.first { $0.name == "Open Folder" }!)
        ]
        for migration in migrations {
            guard let existing = try store.listActions().first(where: { $0.name == migration.oldName }) else { continue }
            var updated = migration.newAction
            updated.id = existing.id
            updated.enabled = existing.enabled
            updated.isFavorite = existing.isFavorite
            updated.displayOrder = existing.displayOrder
            updated.createdAt = existing.createdAt
            updated.updatedAt = Date()
            try coordinator.save(action: updated)
        }
    }

    private func ensureDefaultRecipes(store: ActionStore, coordinator: RecipeCoordinator) throws {
        let existingNames = Set(try store.listActions().map(\.name))
        for action in DefaultActions.all where !existingNames.contains(action.name) {
            try coordinator.save(action: action)
        }
    }


    private func setupMainMenu() {
        let mainMenu = NSMenu(title: "Winegold")

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Winegold")
        appMenu.addItem(NSMenuItem(title: "Quit Winegold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupMenuBar() {
        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = menuBarItem?.button {
            if let url = Bundle.main.url(forResource: "icon-bar", withExtension: "svg"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "wineglass", accessibilityDescription: "Winegold")
            }
            button.imagePosition = .imageOnly
            button.toolTip = "Winegold"
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Panel", action: #selector(togglePanel), keyEquivalent: "")
        applyShortcutToMenuItem(showItem)
        showPanelMenuItem = showItem
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menuBarItem?.menu = menu
    }

    private func setupGlobalHotKey() {
        let hotKey = GlobalHotKey { [weak self] in
            self?.showPanelFromShortcut()
        }
        globalHotKey = hotKey
        let registered = hotKey.register(shortcut: settingsStore.showPanelShortcut)
        logMsg("[AppDelegate] global shortcut \(settingsStore.showPanelShortcut): \(registered ? "registered" : "invalid or unavailable")")
    }

    private func refreshShowPanelShortcut() {
        let registered = globalHotKey?.register(shortcut: settingsStore.showPanelShortcut) ?? false
        if let showPanelMenuItem {
            applyShortcutToMenuItem(showPanelMenuItem)
        }
        logMsg("[AppDelegate] global shortcut updated to \(settingsStore.showPanelShortcut): \(registered ? "registered" : "invalid or unavailable")")
    }

    private func applyShortcutToMenuItem(_ item: NSMenuItem) {
        let parts = settingsStore.showPanelShortcut
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let key = parts.last, key.count == 1 else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = key
        var modifiers: NSEvent.ModifierFlags = []
        if parts.contains("cmd") || parts.contains("command") { modifiers.insert(.command) }
        if parts.contains("shift") { modifiers.insert(.shift) }
        if parts.contains("alt") || parts.contains("option") { modifiers.insert(.option) }
        if parts.contains("ctrl") || parts.contains("control") { modifiers.insert(.control) }
        item.keyEquivalentModifierMask = modifiers
    }

    private func showPanelFromShortcut() {
        showPanel(with: [], on: ScreenResolver.currentInteractionScreen(), invocation: .shortcut)
    }

    private func setupEdgeCatcher() {
        screenEdgeService = ScreenEdgeService(side: settingsStore.panelSide, onDragEnter: { [weak self] files, screen in
            guard !files.isEmpty else {
                logMsg("[AppDelegate] ignored empty drag event")
                return
            }
            self?.showPanel(with: files, on: screen, invocation: .drag)
        })
    }

    @objc private func togglePanel() {
        if actionPanelWindow?.isVisible == true {
            actionPanelWindow?.hide()
        } else {
            showPanel(with: [], on: ScreenResolver.currentInteractionScreen(), invocation: .menu)
        }
    }

    private func ensureSettingsWindow() -> SettingsWindowController? {
        guard let actionStore else { return nil }
        if settingsWC == nil {
            settingsWC = SettingsWindowController(
                store: settingsStore,
                actionStore: actionStore,
                recipeCoordinator: recipeCoordinator,
                remoteRecipeInstaller: remoteRecipeInstaller,
                variableStore: variableStore,
                keychainStore: keychainStore,
                onLaunchAtLoginChanged: { enabled in
                    if #available(macOS 13, *) {
                        let svc = LoginItemService()
                        do {
                            if enabled {
                                try svc.register()
                            } else {
                                try svc.unregister()
                            }
                        } catch {
                            print("Login item error: \(error)")
                        }
                    }
                },
                onShortcutChanged: { [weak self] in
                    self?.refreshShowPanelShortcut()
                },
                onPanelSideChanged: { [weak self] side in
                    self?.screenEdgeService?.setSide(side)
                    self?.actionPanelWindow?.move(to: side, animated: true)
                },
                onConfigurationChanged: { [weak self] in
                    self?.refreshPanelActions()
                    self?.completePendingSetupIfReady()
                }
            )
        }
        return settingsWC
    }

    @objc private func openSettings() {
        guard let settingsWC = ensureSettingsWindow() else { return }
        settingsWC.show()
    }

    private func openNewScriptTemplate(for files: [URL]) {
        guard let settingsWC = ensureSettingsWindow() else { return }
        actionPanelWindow?.hide()
        settingsWC.showNewScriptTemplate(for: files)
    }

    private func shouldAutoImportScripts(_ files: [URL]) -> Bool {
        guard !files.isEmpty, let recipeCoordinator else { return false }
        return files.allSatisfy { file in
            (try? recipeCoordinator.inspectInstallation(file)) != nil
        }
    }

    private func prioritizeInstallActionIfNeeded(_ actions: [Action], files: [URL]) -> [Action] {
        guard shouldAutoImportScripts(files) else { return actions }
        return actions.sorted { lhs, rhs in
            if lhs.name == DefaultActions.installRecipeName { return true }
            if rhs.name == DefaultActions.installRecipeName { return false }
            if lhs.name == "Print and clipboard" { return false }
            if rhs.name == "Print and clipboard" { return true }
            return lhs.name < rhs.name
        }
    }


    private func showPanel(with files: [URL], on requestedScreen: NSScreen? = nil, invocation: PanelInvocation = .menu) {
        let screen = requestedScreen ?? ScreenResolver.currentInteractionScreen()
        logMsg("[AppDelegate] showPanel files=\(files.count) mouse=\(NSStringFromPoint(NSEvent.mouseLocation)) screen=\(screen.map { NSStringFromRect($0.visibleFrame) } ?? "nil")")
        guard let store = actionStore,
              let runHistoryStore = runHistoryStore,
              let screen else {
            logMsg("[AppDelegate] showPanel guard failed")
            return
        }

        let storedActions = panelStoredActions(store)
        let actions = runtimeActions(storedActions, for: files.first)
        let requirements = setupRequirements(for: actions)
        var matched = ActionMatcher().matchingActions(for: files, actions: actions)
        matched = prioritizeInstallActionIfNeeded(matched, files: files)
        if invocation == .drag, matched.isEmpty, !shouldAutoImportScripts(files) {
            logMsg("[AppDelegate] ignored drag with no matching action files=\(files.map { $0.lastPathComponent })")
            return
        }
        let history = (try? runHistoryStore.recentRuns(limit: 10)) ?? []
        let savedHistory = savedRunStore.savedRuns(limit: 10)

        if shouldAutoImportScripts(files), let installAction = actions.first(where: { $0.name == DefaultActions.installRecipeName }) {
            logMsg("[AppDelegate] auto-importing script file(s): \(files.map { $0.lastPathComponent })")
            importScripts(files, using: installAction, runHistoryStore: runHistoryStore)
            return
        }

        let panel: ActionPanelWindow
        if let existingPanel = actionPanelWindow {
            existingPanel.update(
                screen: screen,
                files: files,
                actions: matched,
                allActions: actions,
                history: history,
                savedHistory: savedHistory,
                savedHistoryIds: Set(savedHistory.map { $0.id }),
                setupRequirements: requirements
            )
            panel = existingPanel
            logMsg("[AppDelegate] reused existing panel")
        } else {
            panel = ActionPanelWindow(
                screen: screen,
                files: files,
                actions: matched,
                allActions: actions,
                history: history,
                savedHistory: savedHistory,
                savedHistoryIds: Set(savedHistory.map { $0.id }),
                setupRequirements: requirements,
                settingsStore: settingsStore,
                onRunAction: { [weak self] action, files in
                    self?.runAction(action, files: files)
                },
                onSetupAction: { [weak self] action, files in
                    self?.beginSetup(action, files: files)
                },
                onToggleSavedRun: { [weak self] item in
                    self?.toggleSavedRun(item)
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onToggleFavorite: { [weak self] action in
                    self?.toggleActionFavorite(action)
                },
                onMoveAction: { [weak self] source, target in
                    self?.moveAction(source, before: target)
                }
            )
            actionPanelWindow = panel
            logMsg("[AppDelegate] created panel")
        }
        panel.show(staysOpen: invocation.staysOpen)
    }


    private func runtimeActions(_ actions: [Action], for file: URL?) -> [Action] {
        guard let file else { return actions }
        let resolver = ActionTemplateResolver()
        return actions.map { action in
            var runtime = action
            runtime.runtimeNameTemplate = action.name
            runtime.name = resolver.resolve(template: action.name, for: file)
            return runtime
        }
    }

    private func refreshPanelActions() {
        guard let actionStore else { return }
        let storedActions = panelStoredActions(actionStore)
        let files = actionPanelWindow?.currentFiles ?? []
        let actions = runtimeActions(storedActions, for: files.first)
        let matched = ActionMatcher().matchingActions(for: files, actions: actions)
        actionPanelWindow?.replaceActions(
            allActions: actions,
            actions: matched,
            setupRequirements: setupRequirements(for: actions)
        )
    }

    private func panelStoredActions(_ store: ActionStore) -> [Action] {
        let available = (try? store.listEnabledActions()) ?? []
        let blocked = (try? store.listNeedingSetup()) ?? []
        return available + blocked.filter { candidate in
            !available.contains(where: { $0.id == candidate.id })
        }
    }

    private func setupRequirements(for actions: [Action]) -> [UUID: RecipeSetupRequirements] {
        guard let recipeCoordinator else { return [:] }
        return Dictionary(uniqueKeysWithValues: actions.compactMap { action in
            guard let requirements = try? recipeCoordinator.setupRequirements(for: action.id),
                  !requirements.isReady else { return nil }
            return (action.id, requirements)
        })
    }

    private func beginSetup(_ action: Action, files: [URL]) {
        guard let requirements = try? recipeCoordinator?.setupRequirements(for: action.id),
              !requirements.isReady else {
            runAction(action, files: files)
            return
        }

        if requirements.missingCommands.count + requirements.missingVariables.count > 1 {
            let overview = makeAppAlert()
            overview.messageText = "Set up \(action.name)"
            overview.informativeText = requirements.summary
            overview.addButton(withTitle: "Complete setup and run")
            overview.addButton(withTitle: "Cancel")
            guard overview.runModal() == .alertFirstButtonReturn else { return }
        }

        pendingSetupRun = PendingSetupRun(action: action, files: files)
        if !requirements.missingCommands.isEmpty,
           !confirmAndLaunchInstallation(for: requirements.missingCommands) {
            pendingSetupRun = nil
            return
        }
        if !requirements.missingVariables.isEmpty {
            actionPanelWindow?.hide()
            ensureSettingsWindow()?.showConfiguration(for: action.id) { [weak self] in
                guard self?.pendingSetupRun?.action.id == action.id else { return }
                self?.pendingSetupRun = nil
            }
        }
    }

    private func confirmAndLaunchInstallation(for commands: [String]) -> Bool {
        let valid = commands.filter { command in
            !command.isEmpty && command.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._+-")).contains($0)
            }
        }
        guard valid.count == commands.count else { return false }
        let installCommand = "brew install " + valid.map(shellQuote).joined(separator: " ")
        let alert = makeAppAlert()
        alert.messageText = valid.count == 1 ? "Install \(valid[0])?" : "Install required commands?"
        alert.informativeText = "Winegold will open Terminal with:\n\n\(installCommand)\n\nReview the command before running it."
        alert.addButton(withTitle: "Run in Terminal")
        alert.addButton(withTitle: "Open instructions")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let escaped = installCommand.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"Terminal\" to do script \"\(escaped)\""]
            try? process.run()
            return true
        case .alertSecondButtonReturn:
            if let command = valid.first,
               let encoded = command.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://formulae.brew.sh/formula/\(encoded)") {
                NSWorkspace.shared.open(url)
            }
            return true
        default:
            return false
        }
    }

    private func completePendingSetupIfReady() {
        guard let pending = pendingSetupRun, let recipeCoordinator else { return }
        _ = try? recipeCoordinator.reconcile()
        guard let requirements = try? recipeCoordinator.setupRequirements(for: pending.action.id),
              requirements.isReady else {
            refreshPanelActions()
            settingsWC?.refreshActions()
            return
        }
        pendingSetupRun = nil
        refreshPanelActions()
        settingsWC?.refreshActions()
        runAction(pending.action, files: pending.files)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
    }

    private func toggleActionFavorite(_ action: Action) {
        guard let actionStore else { return }
        do {
            try actionStore.setFavorite(id: action.id, isFavorite: !action.isFavorite)
            refreshPanelActions()
        } catch {
            logMsg("[AppDelegate] favorite failed: \(error.localizedDescription)")
        }
    }

    private func moveAction(_ source: Action, before target: Action) {
        guard let actionStore else { return }
        do {
            try actionStore.moveAction(sourceID: source.id, before: target.id)
            refreshPanelActions()
        } catch {
            logMsg("[AppDelegate] move action failed: \(error.localizedDescription)")
        }
    }

    private func toggleSavedRun(_ item: RunHistoryItem) {
        if savedRunStore.isSaved(item) {
            savedRunStore.unsave(item)
        } else {
            savedRunStore.save(item)
        }
        let saved = savedRunStore.savedRuns(limit: 10)
        actionPanelWindow?.updateSavedHistory(saved, savedIds: Set(saved.map { $0.id }))
    }


    private func importScripts(_ files: [URL], using action: Action, runHistoryStore: RunHistoryStore) {
        actionPanelWindow?.markActionTriggered()
        guard let recipeCoordinator else { return }
        actionPanelWindow?.beginRun(actionName: action.name, files: files)
        Task { @MainActor in
            var failed = false
            for file in files {
                let startedAt = Date()
                var result = CommandResult(actionId: action.id, actionName: action.name, inputFiles: [file.path], status: .success, startedAt: startedAt, endedAt: Date())
                do {
                    let preview = try recipeCoordinator.inspectInstallation(file)
                    let alert = makeAppAlert()
                    alert.messageText = "Install Winegold recipe?"
                    alert.informativeText = installationSummaryText(preview)
                    alert.addButton(withTitle: "Install")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else {
                        result.status = .failed
                        result.stderr = "Installation cancelled.\n"
                        failed = true
                        try? runHistoryStore.addRun(result)
                        actionPanelWindow?.showRunResult(result: result)
                        continue
                    }
                    let summary = try recipeCoordinator.install(file)
                    result.stdout = "Installed: \(summary.recipeNames.joined(separator: ", "))\nDestination: \(summary.destination.path)\n"
                    settingsWC?.refreshActions()
                    refreshPanelActions()
                } catch {
                    failed = true
                    result.status = .failed
                    result.stderr = "\(error.localizedDescription)\n"
                }
                try? runHistoryStore.addRun(result)
                actionPanelWindow?.showRunResult(result: result)
            }
            if files.count > 1, failed {
                logMsg("[AppDelegate] one or more recipe installations failed")
            }
        }
    }

    private func installationSummaryText(_ summary: RecipeInstallationSummary) -> String {
        var lines = [
            "Recipes: \(summary.recipeNames.joined(separator: ", "))",
            "Files copied: \(summary.copiedFiles.count)",
            "Destination: \(summary.destination.path)"
        ]
        if !summary.warnings.isEmpty { lines.append("Warnings:\n" + summary.warnings.joined(separator: "\n")) }
        return lines.joined(separator: "\n")
    }

    private func failureDebugText(
        existingStderr: String,
        action: Action,
        request: CommandExecutionRequest,
        secretValues: [String] = []
    ) -> String {
        let redactor = SecretRedactor()
        let templateArguments = action.argumentsTemplate.enumerated().map { index, argument in
            let lineCount = argument.components(separatedBy: .newlines).count
            let preview = redactor.redact(argument.count > 2_000 ? String(argument.prefix(2_000)) + "\n\u{2026}" : argument, secretValues: secretValues)
            return "Argument template [\(index)] (\(lineCount) line(s), \(argument.count) chars):\n\(preview)"
        }.joined(separator: "\n\n")

        let resolvedArguments = request.arguments.enumerated().map { index, argument in
            let lineCount = argument.components(separatedBy: .newlines).count
            return "Resolved argument [\(index)]: \(lineCount) line(s), \(argument.count) chars"
        }.joined(separator: "\n")

        let workingDirectory = request.workingDirectory ?? "(default)"
        let debug = """

        [Winegold debug]
        Executable: \(request.executablePath)
        Working directory: \(workingDirectory)
        Argument count: \(request.arguments.count)
        \(resolvedArguments)

        \(templateArguments)
        """

        return existingStderr.trimmingCharacters(in: .newlines) + debug + "\n"
    }

    private func runAction(_ action: Action, files: [URL]) {
        if let requirements = try? recipeCoordinator?.setupRequirements(for: action.id),
           !requirements.isReady {
            beginSetup(action, files: files)
            return
        }
        actionPanelWindow?.markActionTriggered()
        guard let runHistoryStore = runHistoryStore else { return }

        if action.name == DefaultActions.installRecipeName {
            importScripts(files, using: action, runHistoryStore: runHistoryStore)
            return
        }

        if action.name == DefaultActions.createScriptFromFileTypeName {
            openNewScriptTemplate(for: files)
            let result = CommandResult(
                actionId: action.id,
                actionName: action.name,
                inputFiles: files.map { $0.path },
                status: .success,
                stdout: "Opened script template.\n",
                startedAt: Date(),
                endedAt: Date()
            )
            try? runHistoryStore.addRun(result)
            actionPanelWindow?.showRunResult(result: result)
            return
        }

        let runner = CommandRunner()
        let resolver = ActionTemplateResolver()
        let recipeVars = recipeCoordinator?.resolveRecipeVariables(for: action.id)
        let recipeEnvironment = recipeVars?.environment
        let secretValues = recipeVars?.secretValues ?? []

        actionPanelWindow?.beginRun(actionName: action.name, files: files)

        Task {
            var batchHadFailure = false
            for (offset, file) in files.enumerated() {
                let resolvedActionName = resolver.resolve(template: action.runtimeNameTemplate ?? action.name, for: file)
                let wd = resolver.resolve(workingDirectoryTemplate: action.workingDirectoryTemplate, for: file)
                let args = resolver.resolve(argumentsTemplate: action.argumentsTemplate, for: file)
                    .map { $0.replacingOccurrences(of: "{recipeDir}", with: wd ?? "") }

                var request = CommandExecutionRequest(
                    executablePath: action.executablePath,
                    arguments: args,
                    workingDirectory: wd,
                    timeoutSeconds: action.timeoutSeconds
                )
                if let recipeEnvironment, !recipeEnvironment.isEmpty {
                    request.environment = recipeEnvironment
                }
                let redactor = SecretRedactor()
                let redactedRequest = redactor.redactCommand(request, secretValues: secretValues)
                let fileIndex = offset + 1

                await MainActor.run {
                    self.actionPanelWindow?.updateRunningProgress(
                        actionName: resolvedActionName,
                        file: file,
                        fileIndex: fileIndex,
                        fileCount: files.count,
                        request: redactedRequest
                    )
                }

                let startedAt = Date()
                var result = await runner.run(request: request, onOutput: { [weak self] stdout, stderr in
                    guard Date().timeIntervalSince(startedAt) >= 0.3 else { return }
                    let rStdout = secretValues.isEmpty ? stdout : redactor.redact(stdout, secretValues: secretValues)
                    let rStderr = secretValues.isEmpty ? stderr : redactor.redact(stderr, secretValues: secretValues)
                    Task { @MainActor in
                        self?.actionPanelWindow?.updateRunningProgress(
                            actionName: resolvedActionName,
                            file: file,
                            fileIndex: fileIndex,
                            fileCount: files.count,
                            request: redactedRequest,
                            stdout: rStdout,
                            stderr: rStderr
                        )
                    }
                })
                result.actionId = action.id
                result.actionName = resolvedActionName
                result.inputFiles = [file.path]
                if result.status == .success, let template = action.successMessage {
                    let message = resolver.resolve(template: template, for: file)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    result.completionMessage = message.isEmpty ? nil : message
                }

                if !secretValues.isEmpty {
                    result.stdout = redactor.redact(result.stdout, secretValues: secretValues)
                    result.stderr = redactor.redact(result.stderr, secretValues: secretValues)
                }

                if result.status != .success {
                    result.stderr = failureDebugText(
                        existingStderr: result.stderr,
                        action: action,
                        request: redactedRequest,
                        secretValues: secretValues
                    )
                }

                if let outputTemplate = action.outputPathTemplate {
                    if let outputPath = resolver.resolve(outputPathTemplate: outputTemplate, for: file) {
                        result.outputFiles = [outputPath]
                    }
                }

                if result.status != .success { batchHadFailure = true }
                try? runHistoryStore.addRun(result)

                let resultCopy = result
                await MainActor.run {
                    if files.count > 1 {
                        self.actionPanelWindow?.appendBatchResult(result: resultCopy)
                    } else {
                        self.actionPanelWindow?.showRunResult(result: resultCopy)
                    }
                }
            }

            if files.count > 1 {
                let finalStatus: ExecutionStatus = batchHadFailure ? .failed : .success
                await MainActor.run {
                    let final = CommandResult(actionId: action.id, actionName: action.name, inputFiles: files.map { $0.path }, status: finalStatus, startedAt: Date(), endedAt: Date())
                    self.actionPanelWindow?.showRunResult(result: final)
                }
            }
        }
    }
}
