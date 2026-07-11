import Foundation

public struct RecipeIndexEntry: Equatable {
    public let externalID: String?
    public let path: String
    public let contentHash: String?
    public let modificationTime: Double
    public let fileSize: Int64
    public let status: String
    public let parseError: String?
}

public struct RecipeIndexStore {
    private let db: Database
    public init(db: Database) { self.db = db }

    public func entries() throws -> [RecipeIndexEntry] {
        let stmt = try db.prepare("SELECT external_id, recipe_path, content_hash, modification_time, file_size, status, parse_error FROM recipe_index")
        var values: [RecipeIndexEntry] = []
        while stmt.step() {
            values.append(RecipeIndexEntry(
                externalID: stmt.columnIsNull(at: 0) ? nil : stmt.columnText(at: 0),
                path: stmt.columnText(at: 1),
                contentHash: stmt.columnIsNull(at: 2) ? nil : stmt.columnText(at: 2),
                modificationTime: Double(stmt.columnText(at: 3)) ?? 0,
                fileSize: Int64(stmt.columnText(at: 4)) ?? 0,
                status: stmt.columnText(at: 5),
                parseError: stmt.columnIsNull(at: 6) ? nil : stmt.columnText(at: 6)
            ))
        }
        return values
    }

    public func validRecord(_ record: RecipeRecord, snapshot: RecipeFileSnapshot) throws {
        guard let externalID = record.document.id else { return }
        try db.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let actionStore = ActionStore(db: db)
            try actionStore.upsertDerivedRecipe(record.action, externalID: externalID, path: record.url.path, hash: record.contentHash)
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

    public func path(for actionID: UUID) throws -> URL? {
        let stmt = try db.prepare("SELECT recipe_path FROM actions WHERE id=? AND source_kind='recipe'")
        stmt.bindText(actionID.uuidString, at: 1)
        return stmt.step() && !stmt.columnText(at: 0).isEmpty ? URL(fileURLWithPath: stmt.columnText(at: 0)) : nil
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

    public init(root: URL, db: Database, scanner: RecipeScanner = RecipeScanner(), parser: RecipeParser = RecipeParser()) {
        self.root = root
        self.scanner = scanner
        self.parser = parser
        self.index = RecipeIndexStore(db: db)
        self.fileStore = RecipeFileStore(root: root)
    }

    @discardableResult public func reconcile() throws -> [RecipeIndexEntry] {
        let snapshots = try scanner.scan(root: root)
        let previous = Dictionary(uniqueKeysWithValues: try index.entries().map { ($0.path, $0) })
        for snapshot in snapshots {
            let old = previous[snapshot.url.path]
            let unchanged = old?.status == "valid" && old?.modificationTime == snapshot.modificationDate.timeIntervalSince1970 && old?.fileSize == snapshot.fileSize
            if unchanged { continue }
            do {
                var record = try parser.parse(url: snapshot.url)
                if record.document.id == nil { fatalError("parser always assigns id") }
                let sourceText = String(decoding: try Data(contentsOf: snapshot.url), as: UTF8.self)
                if !sourceText.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("id:") }) {
                    record = try fileStore.write(record.document, to: snapshot.url)
                }
                let refreshedValues = try snapshot.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let refreshed = RecipeFileSnapshot(url: snapshot.url, modificationDate: refreshedValues.contentModificationDate ?? snapshot.modificationDate, fileSize: Int64(refreshedValues.fileSize ?? Int(snapshot.fileSize)))
                try index.validRecord(record, snapshot: refreshed)
            } catch {
                try index.invalid(snapshot: snapshot, error: error)
            }
        }
        try index.markMissing(paths: Set(snapshots.map { $0.url.path }))
        return try index.entries()
    }

    public func save(action: Action) throws {
        let document = RecipeDocument(id: try externalID(for: action.id), name: action.name, description: action.description, enabled: action.enabled, trigger: action.triggerExpression ?? "extension in {\"*\"}", command: action.argumentsTemplate.count > 1 ? action.argumentsTemplate[1] : action.argumentsTemplate.joined(separator: " "), successMessage: action.successMessage)
        if let path = try index.path(for: action.id) { _ = try fileStore.write(document, to: path) }
        else { _ = try fileStore.create(document) }
        _ = try reconcile()
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
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var descriptor: Int32 = -1

    public init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.root = root
        self.onChange = onChange
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        descriptor = open(root.path, O_EVTONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib, .link], queue: queue)
        source.setEventHandler { [weak self] in self?.schedule() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        self.source = source
        source.resume()
    }

    public func stop() { source?.cancel(); source = nil; debounce?.cancel() }

    private func schedule() {
        debounce?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        debounce = work
        queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    deinit { stop() }
}
