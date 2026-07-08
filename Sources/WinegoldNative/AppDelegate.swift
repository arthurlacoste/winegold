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

    func applicationDidFinishLaunching(_ notification: Notification) {
        logMsg("[AppDelegate] app started")
        setupDatabase()
        setupMenuBar()
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

        let existingNames = Set(try store.listActions().map { $0.name })
        for action in DefaultActions.all where !existingNames.contains(action.name) {
            try store.createAction(action)
        }
    }

    private func setupMenuBar() {
        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = menuBarItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x1.folder.badge.plus", accessibilityDescription: "Winegold")
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Panel", action: #selector(togglePanel), keyEquivalent: "p")
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

    @objc private func openSettings() {
        guard let actionStore else { return }
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
                }
            )
        }
        settingsWC?.show()
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
                }
            )
            actionPanelWindow = panel
            logMsg("[AppDelegate] created panel")
        }
        panel.show()
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
        guard let actionStore else { return }
        Task {
            let importer = LegacyActionImporter()
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

                try? runHistoryStore.addRun(result)
                let resultCopy = result
                await MainActor.run {
                    self.actionPanelWindow?.showRunResult(result: resultCopy)
                }
            }
        }
    }

    private func runAction(_ action: Action, files: [URL]) {
        guard let runHistoryStore = runHistoryStore else { return }

        if action.name == DefaultActions.installAddScriptName {
            importScripts(files, using: action, runHistoryStore: runHistoryStore)
            return
        }

        let runner = CommandRunner()
        let resolver = ActionTemplateResolver()

        Task {
            for file in files {
                let args = resolver.resolve(argumentsTemplate: action.argumentsTemplate, for: file)
                let wd = resolver.resolve(workingDirectoryTemplate: action.workingDirectoryTemplate, for: file)

                let request = CommandExecutionRequest(
                    executablePath: action.executablePath,
                    arguments: args,
                    workingDirectory: wd,
                    timeoutSeconds: action.timeoutSeconds
                )

                var result = await runner.run(request: request)
                result.actionId = action.id
                result.actionName = action.name
                result.inputFiles = [file.path]

                if let outputTemplate = action.outputPathTemplate {
                    if let outputPath = resolver.resolve(outputPathTemplate: outputTemplate, for: file) {
                        result.outputFiles = [outputPath]
                    }
                }

                try? runHistoryStore.addRun(result)

                let resultCopy = result
                await MainActor.run {
                    self.actionPanelWindow?.showRunResult(result: resultCopy)
                }
            }
        }
    }
}
