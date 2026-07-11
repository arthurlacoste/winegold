import Foundation

public struct RecipeIndexEntry: Equatable {
    public let externalID: String?
    public let path: String
    public let contentHash: String?
    public let modificationTime: Double
    public let fileSize: Int64
    public let status: String
    public let parseError: String?
    public let installedFrom: String?
    public let installedAt: String?
}

public struct RecipeIndexStore {
    private let db: Database
    private let root: URL?
    public init(db: Database, root: URL? = nil) { self.db = db; self.root = root }

    public func entries() throws -> [RecipeIndexEntry] {
        let stmt = try db.prepare("SELECT external_id, recipe_path, content_hash, modification_time, file_size, status, parse_error, installed_from, installed_at FROM recipe_index")
        var values: [RecipeIndexEntry] = []
        while stmt.step() {
            values.append(RecipeIndexEntry(
                externalID: stmt.columnIsNull(at: 0) ? nil : stmt.columnText(at: 0),
                path: stmt.columnText(at: 1),
                contentHash: stmt.columnIsNull(at: 2) ? nil : stmt.columnText(at: 2),
                modificationTime: Double(stmt.columnText(at: 3)) ?? 0,
                fileSize: Int64(stmt.columnText(at: 4)) ?? 0,
                status: stmt.columnText(at: 5),
                parseError: stmt.columnIsNull(at: 6) ? nil : stmt.columnText(at: 6),
                installedFrom: stmt.columnIsNull(at: 7) ? nil : stmt.columnText(at: 7),
                installedAt: stmt.columnIsNull(at: 8) ? nil : stmt.columnText(at: 8)
            ))
        }
        return values
    }

    public func validRecord(_ record: RecipeRecord, snapshot: RecipeFileSnapshot, needsSetup: Bool = false) throws {
        guard let externalID = record.document.id else { return }
        try db.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let actionStore = ActionStore(db: db)
            try actionStore.upsertDerivedRecipe(record.action, externalID: externalID, path: record.url.path, hash: record.contentHash, category: category(for: record.url), available: !needsSetup)
            let stmt = try db.prepare("""
                INSERT INTO recipe_index (recipe_path, external_id, content_hash, modification_time, file_size, status, parse_error)
                VALUES (?, ?, ?, ?, ?, 'valid', NULL)
                ON CONFLICT(recipe_path) DO UPDATE SET external_id=excluded.external_id, content_hash=excluded.content_hash,
                modification_time=excluded.modification_time, file_size=excluded.file_size, status='valid', parse_error=NULL
            """)
            bind(snapshot: snapshot, externalID: externalID, hash: record.contentHash, to: stmt)
            _ = stmt.step()
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    public func invalid(snapshot: RecipeFileSnapshot, error: Error) throws {
        let stmt = try db.prepare("""
            INSERT INTO recipe_index (recipe_path, external_id, content_hash, modification_time, file_size, status, parse_error)
            VALUES (?, NULL, NULL, ?, ?, 'invalid', ?)
            ON CONFLICT(recipe_path) DO UPDATE SET modification_time=excluded.modification_time, file_size=excluded.file_size,
            status='invalid', parse_error=excluded.parse_error
        """)
        stmt.bindText(snapshot.url.path, at: 1)
        stmt.bindText(String(snapshot.modificationDate.timeIntervalSince1970), at: 2)
        stmt.bindText(String(snapshot.fileSize), at: 3)
        stmt.bindText(error.localizedDescription, at: 4)
        _ = stmt.step()
        let disable = try db.prepare("UPDATE actions SET available=0 WHERE recipe_path=?")
        disable.bindText(snapshot.url.path, at: 1); _ = disable.step()
    }

    public func markMissing(paths: Set<String>) throws {
        for entry in try entries() where !paths.contains(entry.path) {
            let stmt = try db.prepare("UPDATE recipe_index SET status='missing', parse_error=NULL WHERE recipe_path=?")
            stmt.bindText(entry.path, at: 1); _ = stmt.step()
            let disable = try db.prepare("UPDATE actions SET available=0 WHERE recipe_path=?")
            disable.bindText(entry.path, at: 1); _ = disable.step()
        }
    }


    public func recordInstallation(destination: URL, source: URL, at date: Date = Date()) throws {
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let timestamp = ISO8601DateFormatter().string(from: date)
        for entry in try entries() {
            let recipePath = URL(fileURLWithPath: entry.path).resolvingSymlinksInPath().standardizedFileURL.path
            guard recipePath == destinationPath || recipePath.hasPrefix(destinationPath + "/") else { continue }
            let stmt = try db.prepare("UPDATE recipe_index SET installed_from=?, installed_at=? WHERE recipe_path=?")
            stmt.bindText(sourcePath, at: 1)
            stmt.bindText(timestamp, at: 2)
            stmt.bindText(entry.path, at: 3)
            _ = stmt.step()
        }
    }
    public func hasAvailableAction(externalID: String?) throws -> Bool {
        guard let externalID else { return false }
        let stmt = try db.prepare("SELECT COUNT(*) FROM actions WHERE external_id=? AND available=1")
        stmt.bindText(externalID, at: 1)
        return stmt.step() && stmt.columnInt(at: 0) > 0
    }

    public func path(for actionID: UUID) throws -> URL? {
        let stmt = try db.prepare("SELECT recipe_path FROM actions WHERE id=? AND source_kind='recipe'")
        stmt.bindText(actionID.uuidString, at: 1)
        return stmt.step() && !stmt.columnText(at: 0).isEmpty ? URL(fileURLWithPath: stmt.columnText(at: 0)) : nil
    }


    private func category(for recipeURL: URL) -> String? {
        guard let root else { return nil }
        let parent = recipeURL.deletingLastPathComponent().standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard parent != rootPath, parent.hasPrefix(rootPath + "/") else { return nil }
        return String(parent.dropFirst(rootPath.count + 1))
    }
    private func bind(snapshot: RecipeFileSnapshot, externalID: String, hash: String, to stmt: Statement) {
        stmt.bindText(snapshot.url.path, at: 1)
        stmt.bindText(externalID, at: 2)
        stmt.bindText(hash, at: 3)
        stmt.bindText(String(snapshot.modificationDate.timeIntervalSince1970), at: 4)
        stmt.bindText(String(snapshot.fileSize), at: 5)
    }
}

public final class RecipeCoordinator {
    public let root: URL
    private let scanner: RecipeScanner
    private let parser: RecipeParser
    private let index: RecipeIndexStore
    private let fileStore: RecipeFileStore
    private let variableStore: RecipeVariableStore?
    private let keychainStore: KeychainSecretStore?

    public init(root: URL, db: Database, scanner: RecipeScanner = RecipeScanner(), parser: RecipeParser = RecipeParser(), variableStore: RecipeVariableStore? = nil, keychainStore: KeychainSecretStore? = nil) {
        self.root = root
        self.scanner = scanner
        self.parser = parser
        self.index = RecipeIndexStore(db: db, root: root)
        self.fileStore = RecipeFileStore(root: root)
        self.variableStore = variableStore
        self.keychainStore = keychainStore
    }

    @discardableResult public func reconcile() throws -> [RecipeIndexEntry] {
        let snapshots = try scanner.scan(root: root)
        let previous = Dictionary(uniqueKeysWithValues: try index.entries().map { ($0.path, $0) })
        for snapshot in snapshots {
            let old = previous[snapshot.url.path]
            let metadataMatches = old?.status == "valid"
                && old?.modificationTime == snapshot.modificationDate.timeIntervalSince1970
                && old?.fileSize == snapshot.fileSize
            if metadataMatches,
               let oldHash = old?.contentHash,
               RecipeParser.hash(try Data(contentsOf: snapshot.url)) == oldHash,
               try index.hasAvailableAction(externalID: old?.externalID) {
                continue
            }
            do {
                var record = try parser.parse(url: snapshot.url)
                if record.document.id == nil { fatalError("parser always assigns id") }
                let sourceText = String(decoding: try Data(contentsOf: snapshot.url), as: UTF8.self)
                if !sourceText.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("id:") }) {
                    record = try fileStore.write(record.document, to: snapshot.url)
                }
                let refreshedValues = try snapshot.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let refreshed = RecipeFileSnapshot(url: snapshot.url, modificationDate: refreshedValues.contentModificationDate ?? snapshot.modificationDate, fileSize: Int64(refreshedValues.fileSize ?? Int(snapshot.fileSize)))
                let needsSetup = checkNeedsSetup(record: record)
                try index.validRecord(record, snapshot: refreshed, needsSetup: needsSetup)
            } catch {
                try index.invalid(snapshot: snapshot, error: error)
            }
        }
        try index.markMissing(paths: Set(snapshots.map { $0.url.path }))
        return try index.entries()
    }

    private func checkNeedsSetup(record: RecipeRecord) -> Bool {
        guard let variables = record.document.variables, !variables.isEmpty else { return false }
        guard let variableStore, let keychainStore else { return false }
        let resolver = RecipeVariableResolver(variableStore: variableStore, keychainStore: keychainStore)
        let status = resolver.setupStatus(variables: variables, externalID: record.document.id ?? "", appEnvironment: ProcessInfo.processInfo.environment)
        if case .needsSetup = status { return true }
        return false
    }

    public func setupStatus(for actionID: UUID) throws -> RecipeSetupStatus? {
        guard let path = try index.path(for: actionID) else { return nil }
        let record = try parser.parse(url: path)
        guard let variables = record.document.variables, !variables.isEmpty else { return nil }
        guard let variableStore, let keychainStore else { return .ready }
        let resolver = RecipeVariableResolver(variableStore: variableStore, keychainStore: keychainStore)
        return resolver.setupStatus(variables: variables, externalID: record.document.id ?? "", appEnvironment: ProcessInfo.processInfo.environment)
    }

    public func repairDraft(at path: URL) throws -> RecipeDocument {
        try parser.repairDraft(url: path)
    }

    public func repairInvalidRecipe(at path: URL, action: Action) throws {
        let draft = try parser.repairDraft(url: path)
        let document = RecipeDocument(
            id: draft.id,
            name: action.name,
            description: draft.description,
            version: draft.version,
            enabled: draft.enabled,
            trigger: action.triggerExpression ?? "extension in {\"*\"}",
            command: action.argumentsTemplate.count > 1 ? action.argumentsTemplate[1] : action.argumentsTemplate.joined(separator: " "),
            successMessage: action.successMessage,
            supportFiles: draft.supportFiles,
            requirements: draft.requirements,
            variables: draft.variables
        )
        _ = try fileStore.repair(document, at: path)
        _ = try reconcile()
    }

    public func save(action: Action) throws {
        let path = try index.path(for: action.id)
        var document: RecipeDocument
        if let path, FileManager.default.fileExists(atPath: path.path) {
            document = try parser.parse(url: path).document
            document.name = action.name
            document.description = action.description
            document.enabled = action.enabled
            document.trigger = action.triggerExpression ?? "extension in {\"*\"}"
            document.command = action.argumentsTemplate.count > 1 ? action.argumentsTemplate[1] : action.argumentsTemplate.joined(separator: " ")
            document.successMessage = action.successMessage
            _ = try fileStore.write(document, to: path)
        } else {
            document = RecipeDocument(
                id: try externalID(for: action.id),
                name: action.name,
                description: action.description,
                enabled: action.enabled,
                trigger: action.triggerExpression ?? "extension in {\"*\"}",
                command: action.argumentsTemplate.count > 1 ? action.argumentsTemplate[1] : action.argumentsTemplate.joined(separator: " "),
                successMessage: action.successMessage
            )
            _ = try fileStore.create(document)
        }
        _ = try reconcile()
    }

    public func entries() throws -> [RecipeIndexEntry] { try index.entries() }

    public func path(for actionID: UUID) throws -> URL? { try index.path(for: actionID) }

    public func resolveRecipeVariables(for actionID: UUID) -> (environment: [String: String], secretValues: [String])? {
        guard let variableStore, let keychainStore else { return nil }
        guard let path = try? index.path(for: actionID),
              let record = try? parser.parse(url: path),
              let variables = record.document.variables, !variables.isEmpty,
              let externalID = record.document.id else { return nil }
        let resolver = RecipeVariableResolver(variableStore: variableStore, keychainStore: keychainStore)
        let environment = resolver.resolve(variables: variables, externalID: externalID, appEnvironment: ProcessInfo.processInfo.environment)
        let secretValues = resolver.secretValues(variables: variables, externalID: externalID, appEnvironment: ProcessInfo.processInfo.environment)
        return (environment, secretValues)
    }

    public func consentWarnings(for actionID: UUID) -> [String: String] {
        guard let variableStore, let keychainStore else { return [:] }
        guard let path = try? index.path(for: actionID),
              let record = try? parser.parse(url: path),
              let variables = record.document.variables, !variables.isEmpty,
              let externalID = record.document.id else { return [:] }
        return RecipeConsentManager(variableStore: variableStore, keychainStore: keychainStore)
            .consentWarnings(variables: variables, externalID: externalID)
    }

    public func recipeVariables(for actionID: UUID) -> [RecipeVariable]? {
        guard let path = try? index.path(for: actionID),
              let record = try? parser.parse(url: path),
              let variables = record.document.variables, !variables.isEmpty else { return nil }
        return variables
    }

    public func recipeExternalID(for actionID: UUID) -> String? {
        guard let path = try? index.path(for: actionID),
              let record = try? parser.parse(url: path) else { return nil }
        return record.document.id
    }

    public func install(_ source: URL) throws -> RecipeInstallationSummary {
        let summary = try RecipeInstaller(root: root).install(source)
        _ = try reconcile()
        try index.recordInstallation(destination: summary.destination, source: source)
        return summary
    }

    public func inspectInstallation(_ source: URL) throws -> RecipeInstallationSummary {
        try RecipeInstaller(root: root).inspect(source)
    }

    public func delete(actionID: UUID) throws {
        guard let path = try index.path(for: actionID) else { return }
        try fileStore.remove(path)
        _ = try reconcile()
    }

    private func externalID(for actionID: UUID) throws -> String? {
        try index.entries().first { $0.externalID.map { RecipeParser.runtimeUUID(for: $0) } == actionID }?.externalID
    }
}

public final class RecipeWatcher: @unchecked Sendable {
    private let root: URL
    private let queue = DispatchQueue(label: "winegold.recipe-watcher")
    private let onChange: () -> Void
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var debounce: DispatchWorkItem?
    private var isStarted = false

    public init(root: URL, onChange: @escaping () -> Void) {
        self.root = root
        self.onChange = onChange
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var startError: Error?
        queue.sync {
            do {
                isStarted = true
                try refreshSources()
            } catch {
                startError = error
            }
        }
        if let startError { throw startError }
    }

    public func stop() {
        queue.sync {
            isStarted = false
            debounce?.cancel()
            debounce = nil
            let current = Array(sources.values)
            sources.removeAll()
            current.forEach { $0.cancel() }
        }
    }

    private func refreshSources() throws {
        guard isStarted else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directories = try watchedDirectories()
        let wanted = Set(directories.map(\.path))

        for path in sources.keys where !wanted.contains(path) {
            sources.removeValue(forKey: path)?.cancel()
        }
        for directory in directories where sources[directory.path] == nil {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.schedule() }
            source.setCancelHandler { close(descriptor) }
            sources[directory.path] = source
            source.resume()
        }
    }

    private func watchedDirectories() throws -> [URL] {
        var directories = [root]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return directories }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isDirectory == true else { continue }
            let name = url.lastPathComponent.lowercased()
            if name.hasPrefix(".") || RecipeScanner.ignoredDirectories.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            directories.append(url)
        }
        return directories
    }

    private func schedule() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isStarted else { return }
            self.onChange()
            let current = Array(self.sources.values)
            self.sources.removeAll()
            current.forEach { $0.cancel() }
            try? self.refreshSources()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    deinit {
        if isStarted { stop() }
    }
}
