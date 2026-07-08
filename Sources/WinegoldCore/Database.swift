import Foundation
import CSQLite

public enum DatabaseError: LocalizedError {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "DB open: \(msg)"
        case .executeFailed(let msg): return "DB execute: \(msg)"
        case .prepareFailed(let msg): return "DB prepare: \(msg)"
        case .stepFailed(let msg): return "DB step: \(msg)"
        }
    }
}

public final class Database {
    private var db: OpaquePointer?

    public init(path: String) throws {
        let rc = sqlite3_open(path, &db)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw DatabaseError.openFailed(msg)
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
    }

    public func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        guard rc == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.executeFailed(msg)
        }
    }

    public func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let s = stmt else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(msg)
        }
        return Statement(handle: s, db: db)
    }

    public func lastInsertRowId() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    deinit {
        sqlite3_close(db)
    }
}

public final class Statement {
    private let handle: OpaquePointer
    private let db: OpaquePointer?

    init(handle: OpaquePointer, db: OpaquePointer?) {
        self.handle = handle
        self.db = db
    }

    public func bindText(_ value: String, at index: Int32) {
        sqlite3_bind_text(handle, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    public func bindInt(_ value: Int, at index: Int32) {
        sqlite3_bind_int64(handle, index, Int64(value))
    }

    public func bindNull(at index: Int32) {
        sqlite3_bind_null(handle, index)
    }

    public func step() -> Bool {
        sqlite3_step(handle) == SQLITE_ROW
    }

    public func reset() {
        sqlite3_reset(handle)
    }

    public func columnText(at index: Int32) -> String {
        guard let c = sqlite3_column_text(handle, index) else { return "" }
        return String(cString: c)
    }

    public func columnInt(at index: Int32) -> Int {
        Int(sqlite3_column_int64(handle, index))
    }

    public func columnIsNull(at index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    deinit {
        sqlite3_finalize(handle)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
