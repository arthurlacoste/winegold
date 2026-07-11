import Foundation

public struct Migrations {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func run() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS actions (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                icon_name TEXT,
                enabled INTEGER NOT NULL,
                accepted_extensions TEXT NOT NULL,
                accepted_utis TEXT NOT NULL,
                trigger_expression TEXT,
                executable_path TEXT NOT NULL,
                arguments_template TEXT NOT NULL,
                working_directory_template TEXT,
                output_path_template TEXT,
                success_message TEXT,
                requires_confirmation INTEGER NOT NULL,
                timeout_seconds INTEGER NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                display_order INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS run_history (
                id TEXT PRIMARY KEY,
                action_id TEXT NOT NULL,
                action_name TEXT NOT NULL,
                input_files TEXT NOT NULL,
                output_files TEXT NOT NULL,
                status TEXT NOT NULL,
                exit_code INTEGER,
                stdout TEXT NOT NULL,
                stderr TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY
            )
        """)


        try db.execute("""
            CREATE TABLE IF NOT EXISTS recipe_index (
                recipe_path TEXT PRIMARY KEY,
                external_id TEXT,
                content_hash TEXT,
                modification_time TEXT NOT NULL,
                file_size TEXT NOT NULL,
                status TEXT NOT NULL,
                parse_error TEXT
            )
        """)

        try ensureRecipeColumns()
        let version = try currentVersion()
        if version == 0 {
            try db.execute("INSERT INTO schema_version (version) VALUES (5)")
        } else {
            if version < 2 {
                try db.execute("ALTER TABLE actions ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0")
                try db.execute("ALTER TABLE actions ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0")
                try db.execute("INSERT INTO schema_version (version) VALUES (2)")
            }
            if version < 3 {
                try db.execute("ALTER TABLE actions ADD COLUMN success_message TEXT")
                try db.execute("INSERT INTO schema_version (version) VALUES (3)")
            }
            if version < 4 {
                try db.execute("ALTER TABLE actions ADD COLUMN trigger_expression TEXT")
                try db.execute("INSERT INTO schema_version (version) VALUES (4)")
            }
            if version < 5 {
                try addRecipeColumns()
                try db.execute("INSERT INTO schema_version (version) VALUES (5)")
            }
        }
    }

    private func ensureRecipeColumns() throws {
        let columns = try tableColumns("actions")
        if !columns.contains("source_kind") { try db.execute("ALTER TABLE actions ADD COLUMN source_kind TEXT NOT NULL DEFAULT 'legacy'") }
        if !columns.contains("external_id") { try db.execute("ALTER TABLE actions ADD COLUMN external_id TEXT") }
        if !columns.contains("recipe_path") { try db.execute("ALTER TABLE actions ADD COLUMN recipe_path TEXT") }
        if !columns.contains("recipe_hash") { try db.execute("ALTER TABLE actions ADD COLUMN recipe_hash TEXT") }
        if !columns.contains("available") { try db.execute("ALTER TABLE actions ADD COLUMN available INTEGER NOT NULL DEFAULT 1") }
        try db.execute("DROP INDEX IF EXISTS actions_external_id_idx")
        try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS actions_external_id_idx ON actions(external_id)")
    }

    private func addRecipeColumns() throws { try ensureRecipeColumns() }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let stmt = try db.prepare("PRAGMA table_info(\(table))")
        var values = Set<String>()
        while stmt.step() { values.insert(stmt.columnText(at: 1)) }
        return values
    }

    private func currentVersion() throws -> Int {
        let stmt = try db.prepare("SELECT MAX(version) FROM schema_version")
        if stmt.step() {
            return stmt.columnInt(at: 0)
        }
        return 0
    }
}
