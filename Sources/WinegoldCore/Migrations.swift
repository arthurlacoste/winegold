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
                executable_path TEXT NOT NULL,
                arguments_template TEXT NOT NULL,
                working_directory_template TEXT,
                output_path_template TEXT,
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

        let version = try currentVersion()
        if version == 0 {
            try db.execute("INSERT INTO schema_version (version) VALUES (2)")
        } else if version < 2 {
            try db.execute("ALTER TABLE actions ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0")
            try db.execute("ALTER TABLE actions ADD COLUMN display_order INTEGER NOT NULL DEFAULT 0")
            try db.execute("INSERT INTO schema_version (version) VALUES (2)")
        }
    }

    private func currentVersion() throws -> Int {
        let stmt = try db.prepare("SELECT MAX(version) FROM schema_version")
        if stmt.step() {
            return stmt.columnInt(at: 0)
        }
        return 0
    }
}
