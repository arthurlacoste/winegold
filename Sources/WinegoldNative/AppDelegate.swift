import Cocoa
import WinegoldCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarItem: NSStatusItem?
    private let settingsStore = SettingsStore()
    private var actionStore: ActionStore?
    private var runHistoryStore: RunHistoryStore?
    private let savedRunStore = SavedRunStore()
    private var screenEdgeService: ScreenEdgeService?
    private var actionPanelWindow: ActionPanelWindow?
    private var settingsWC: SettingsWindowController?
    private var database: Database?
    private var globalHotKey: GlobalHotKey?
    private weak var showPanelMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logMsg("[AppDelegate] app started")
        setupDatabase()
        setupMainMenu()
        setupMenuBar()
        setupGlobalHotKey()
        setupEdgeCatcher()
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

            try ensureDefaultActions(store: store)

            self.runHistoryStore = RunHistoryStore(db: db)
        } catch {
            print("DB init error: \(error)")
        }
    }

    private func ensureDefaultActions(store: ActionStore) throws {
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

        let existingNames = Set(try store.listActions().map { $0.name })
        for action in DefaultActions.all where !existingNames.contains(action.name) {
            try store.createAction(action)
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
            button.image = NSImage(systemSymbolName: "square.grid.3x1.folder.badge.plus", accessibilityDescription: "Winegold")
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
        showPanel(with: [], on: ScreenResolver.currentInteractionScreen())
    }

    private func setupEdgeCatcher() {
        screenEdgeService = ScreenEdgeService(onDragEnter: { [weak self] files, screen in
            self?.showPanel(with: files, on: screen)
        })
    }

    @objc private func togglePanel() {
        if actionPanelWindow?.isVisible == true {
            actionPanelWindow?.hide()
        } else {
            showPanel(with: [], on: ScreenResolver.currentInteractionScreen())
        }
    }

    private func ensureSettingsWindow() -> SettingsWindowController? {
        guard let actionStore else { return nil }
        if settingsWC == nil {
            settingsWC = SettingsWindowController(
                store: settingsStore,
                actionStore: actionStore,
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
        guard !files.isEmpty else { return false }
        return files.allSatisfy { file in
            let ext = file.pathExtension.lowercased()
            return ext == "yml" || ext == "yaml" || file.lastPathComponent.lowercased().hasSuffix(".add.yml")
        }
    }

    private func prioritizeInstallActionIfNeeded(_ actions: [Action], files: [URL]) -> [Action] {
        guard shouldAutoImportScripts(files) else { return actions }
        return actions.sorted { lhs, rhs in
            if lhs.name == DefaultActions.installAddScriptName { return true }
            if rhs.name == DefaultActions.installAddScriptName { return false }
            if lhs.name == "Print and clipboard" { return false }
            if rhs.name == "Print and clipboard" { return true }
            return lhs.name < rhs.name
        }
    }


    private func showPanel(with files: [URL], on requestedScreen: NSScreen? = nil) {
        let screen = requestedScreen ?? ScreenResolver.currentInteractionScreen()
        logMsg("[AppDelegate] showPanel files=\(files.count) mouse=\(NSStringFromPoint(NSEvent.mouseLocation)) screen=\(screen.map { NSStringFromRect($0.visibleFrame) } ?? "nil")")
        guard let store = actionStore,
              let runHistoryStore = runHistoryStore,
              let screen else {
            logMsg("[AppDelegate] showPanel guard failed")
            return
        }

        let actions = (try? store.listEnabledActions()) ?? []
        var matched = ActionMatcher().matchingActions(for: files, actions: actions)
        matched = prioritizeInstallActionIfNeeded(matched, files: files)
        let history = (try? runHistoryStore.recentRuns(limit: 10)) ?? []
        let savedHistory = savedRunStore.savedRuns(limit: 10)

        if shouldAutoImportScripts(files), let installAction = actions.first(where: { $0.name == DefaultActions.installAddScriptName }) {
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
                savedHistoryIds: Set(savedHistory.map { $0.id })
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
                settingsStore: settingsStore,
                onRunAction: { [weak self] action, files in
                    self?.runAction(action, files: files)
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
        panel.show()
    }


    private func refreshPanelActions() {
        guard let actionStore else { return }
        let actions = (try? actionStore.listEnabledActions()) ?? []
        let matched = ActionMatcher().matchingActions(for: actionPanelWindow?.currentFiles ?? [], actions: actions)
        actionPanelWindow?.replaceActions(allActions: actions, actions: matched)
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
        guard let actionStore else { return }
        actionPanelWindow?.beginRun(actionName: action.name, files: files)
        Task {
            let importer = LegacyActionImporter()
            var batchHadFailure = false
            for file in files {
                let startedAt = Date()
                var result = CommandResult(
                    actionId: action.id,
                    actionName: action.name,
                    inputFiles: [file.path],
                    status: .success,
                    startedAt: startedAt,
                    endedAt: Date()
                )
                do {
                    let importedActions = try importer.importActions(from: file)
                    var created: [String] = []
                    var updated: [String] = []
                    for imported in importedActions {
                        let didCreate = try actionStore.upsertActionByName(imported)
                        try actionStore.deleteDuplicateActionsByName(keeping: imported.name)
                        if didCreate { created.append(imported.name) } else { updated.append(imported.name) }
                    }
                    let createdLine = created.isEmpty ? "" : "Created: \(created.joined(separator: ", "))\n"
                    let updatedLine = updated.isEmpty ? "" : "Updated: \(updated.joined(separator: ", "))\n"
                    result.stdout = createdLine + updatedLine
                    logMsg("[AppDelegate] imported scripts from \(file.lastPathComponent): created=\(created) updated=\(updated)")
                    await MainActor.run {
                        self.settingsWC?.refreshActions()
                    }
                } catch {
                    result.status = .failed
                    result.stderr = "\(error.localizedDescription)\n"
                    logMsg("[AppDelegate] import script failed: \(error.localizedDescription)")
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

    private func failureDebugText(
        existingStderr: String,
        action: Action,
        request: CommandExecutionRequest
    ) -> String {
        let templateArguments = action.argumentsTemplate.enumerated().map { index, argument in
            let lineCount = argument.components(separatedBy: .newlines).count
            let preview = redactSecrets(argument.count > 2_000 ? String(argument.prefix(2_000)) + "\n…" : argument)
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

    private func redactSecrets(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"(?i)(Authorization:\s*(?:Bearer|DeepL-Auth-Key)\s+)[^\s\"]+"#,
            with: "$1[REDACTED]",
            options: .regularExpression
        )
    }

    private func runAction(_ action: Action, files: [URL]) {
        actionPanelWindow?.markActionTriggered()
        guard let runHistoryStore = runHistoryStore else { return }

        if action.name == DefaultActions.installAddScriptName {
            importScripts(files, using: action, runHistoryStore: runHistoryStore)
            return
        }

        if action.name == DefaultActions.createScriptFromFileTypeName {
            openNewScriptTemplate(for: files)
            return
        }

        let runner = CommandRunner()
        let resolver = ActionTemplateResolver()

        actionPanelWindow?.beginRun(actionName: action.name, files: files)

        Task {
            var batchHadFailure = false
            for (offset, file) in files.enumerated() {
                let args = resolver.resolve(argumentsTemplate: action.argumentsTemplate, for: file)
                let wd = resolver.resolve(workingDirectoryTemplate: action.workingDirectoryTemplate, for: file)

                let request = CommandExecutionRequest(
                    executablePath: action.executablePath,
                    arguments: args,
                    workingDirectory: wd,
                    timeoutSeconds: action.timeoutSeconds
                )
                let fileIndex = offset + 1

                await MainActor.run {
                    self.actionPanelWindow?.updateRunningProgress(
                        actionName: action.name,
                        file: file,
                        fileIndex: fileIndex,
                        fileCount: files.count,
                        request: request
                    )
                }

                let startedAt = Date()
                var result = await runner.run(request: request, onOutput: { [weak self] stdout, stderr in
                    guard Date().timeIntervalSince(startedAt) >= 0.3 else { return }
                    Task { @MainActor in
                        self?.actionPanelWindow?.updateRunningProgress(
                            actionName: action.name,
                            file: file,
                            fileIndex: fileIndex,
                            fileCount: files.count,
                            request: request,
                            stdout: stdout,
                            stderr: stderr
                        )
                    }
                })
                result.actionId = action.id
                result.actionName = action.name
                result.inputFiles = [file.path]

                if result.status != .success {
                    result.stderr = failureDebugText(
                        existingStderr: result.stderr,
                        action: action,
                        request: request
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
