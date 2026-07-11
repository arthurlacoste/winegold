import Foundation

public struct LegacyRecipeMigrator {
    private let db: Database
    private let root: URL

    public init(db: Database, root: URL) {
        self.db = db
        self.root = root
    }

    public func migrateIfNeeded() throws {
        try db.execute("CREATE TABLE IF NOT EXISTS app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        let marker = try db.prepare("SELECT value FROM app_metadata WHERE key='recipe_file_migration_version'")
        if marker.step(), marker.columnText(at: 0) == "1" { return }

        let actions = try ActionStore(db: db).listActions()
        guard !actions.isEmpty else { try markComplete(); return }

        let parent = root.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".recipes-migration-\(UUID().uuidString)")
        let migrated = staging.appendingPathComponent("migrated")
        try FileManager.default.createDirectory(at: migrated, withIntermediateDirectories: true)
        let serializer = RecipeSerializer()
        let parser = RecipeParser()

        do {
            for action in actions {
                let command = action.argumentsTemplate.count > 1 ? action.argumentsTemplate[1] : action.argumentsTemplate.joined(separator: " ")
                let document = RecipeDocument(
                    id: action.id.uuidString,
                    name: action.name,
                    description: action.description,
                    enabled: action.enabled,
                    trigger: action.triggerExpression ?? legacyTrigger(action.acceptedExtensions),
                    command: command,
                    successMessage: action.successMessage
                )
                let url = migrated.appendingPathComponent("\(RecipeFileStore.slug(action.name))-\(action.id.uuidString.prefix(8)).wg.yml")
                let text = serializer.serialize(document)
                _ = try parser.parse(text: text)
                try Data(text.utf8).write(to: url, options: .atomic)
                _ = try parser.parse(url: url)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent("migrated")
            if FileManager.default.fileExists(atPath: destination.path) {
                for file in try FileManager.default.contentsOfDirectory(at: migrated, includingPropertiesForKeys: nil) {
                    let target = destination.appendingPathComponent(file.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.moveItem(at: file, to: target) }
                }
            } else {
                try FileManager.default.moveItem(at: migrated, to: destination)
            }
            try? FileManager.default.removeItem(at: staging)
            try markComplete()
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private func markComplete() throws {
        try db.execute("INSERT OR REPLACE INTO app_metadata (key, value) VALUES ('recipe_file_migration_version', '1')")
    }

    private func legacyTrigger(_ extensions: [String]) -> String {
        TriggerSerializer().serialize(.condition(field: "extension", operator: .in, value: .collection(extensions.isEmpty ? ["*"] : extensions)))
    }
}
