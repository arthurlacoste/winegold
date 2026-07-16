import Foundation

public struct RunHistoryItem: Identifiable, Codable {
    public var id: UUID
    public var actionId: UUID
    public var actionName: String
    public var parentRecipeID: String?
    public var childActionID: String?
    public var parentRecipeName: String?
    public var childActionName: String?
    public var inputFiles: [String]
    public var outputFiles: [String]
    public var status: ExecutionStatus
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        actionId: UUID,
        actionName: String,
        parentRecipeID: String? = nil,
        childActionID: String? = nil,
        parentRecipeName: String? = nil,
        childActionName: String? = nil,
        inputFiles: [String] = [],
        outputFiles: [String] = [],
        status: ExecutionStatus = .pending,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.actionId = actionId
        self.actionName = actionName
        self.parentRecipeID = parentRecipeID
        self.childActionID = childActionID
        self.parentRecipeName = parentRecipeName
        self.childActionName = childActionName
        self.inputFiles = inputFiles
        self.outputFiles = outputFiles
        self.status = status
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public init(from result: CommandResult) {
        self.id = result.id
        self.actionId = result.actionId
        self.actionName = result.actionName
        self.parentRecipeID = result.parentRecipeID
        self.childActionID = result.childActionID
        self.parentRecipeName = result.parentRecipeName
        self.childActionName = result.childActionName
        self.inputFiles = result.inputFiles
        self.outputFiles = result.outputFiles
        self.status = result.status
        self.exitCode = result.exitCode
        self.stdout = result.stdout
        self.stderr = result.stderr
        self.startedAt = result.startedAt
        self.endedAt = result.endedAt
    }
}

public struct RunHistoryStore {
    private let db: Database
    private let dateFormatter: DateFormatter

    public init(db: Database) {
        self.db = db
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    }

    public func addRun(_ result: CommandResult) throws {
        let item = RunHistoryItem(from: result)
        let stmt = try db.prepare("""
            INSERT INTO run_history (id, action_id, action_name, input_files, output_files,
            status, exit_code, stdout, stderr, started_at, ended_at, parent_recipe_id, child_action_id,
            parent_recipe_name, child_action_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        stmt.bindText(item.id.uuidString, at: 1)
        stmt.bindText(item.actionId.uuidString, at: 2)
        stmt.bindText(item.actionName, at: 3)
        stmt.bindText(item.inputFiles.joined(separator: "\n"), at: 4)
        stmt.bindText(item.outputFiles.joined(separator: "\n"), at: 5)
        stmt.bindText(item.status.rawValue, at: 6)
        if let code = item.exitCode {
            stmt.bindInt(Int(code), at: 7)
        } else {
            stmt.bindNull(at: 7)
        }
        stmt.bindText(item.stdout, at: 8)
        stmt.bindText(item.stderr, at: 9)
        stmt.bindText(dateFormatter.string(from: item.startedAt), at: 10)
        if let ended = item.endedAt { stmt.bindText(dateFormatter.string(from: ended), at: 11) } else { stmt.bindNull(at: 11) }
        if let value = item.parentRecipeID { stmt.bindText(value, at: 12) } else { stmt.bindNull(at: 12) }
        if let value = item.childActionID { stmt.bindText(value, at: 13) } else { stmt.bindNull(at: 13) }
        if let value = item.parentRecipeName { stmt.bindText(value, at: 14) } else { stmt.bindNull(at: 14) }
        if let value = item.childActionName { stmt.bindText(value, at: 15) } else { stmt.bindNull(at: 15) }
        _ = stmt.step()
    }

    public func recentRuns(limit: Int = 100) throws -> [RunHistoryItem] {
        let stmt = try db.prepare("SELECT id, action_id, action_name, input_files, output_files, status, exit_code, stdout, stderr, started_at, ended_at, parent_recipe_id, child_action_id, parent_recipe_name, child_action_name FROM run_history ORDER BY started_at DESC LIMIT ?")
        stmt.bindInt(limit, at: 1)
        var items: [RunHistoryItem] = []
        while stmt.step() {
            items.append(rowToItem(stmt))
        }
        return items
    }

    public func clearHistory() throws {
        try db.execute("DELETE FROM run_history")
    }

    private func rowToItem(_ stmt: Statement) -> RunHistoryItem {
        RunHistoryItem(
            id: UUID(uuidString: stmt.columnText(at: 0)) ?? UUID(),
            actionId: UUID(uuidString: stmt.columnText(at: 1)) ?? UUID(),
            actionName: stmt.columnText(at: 2),
            parentRecipeID: stmt.columnIsNull(at: 11) ? nil : stmt.columnText(at: 11),
            childActionID: stmt.columnIsNull(at: 12) ? nil : stmt.columnText(at: 12),
            parentRecipeName: stmt.columnIsNull(at: 13) ? nil : stmt.columnText(at: 13),
            childActionName: stmt.columnIsNull(at: 14) ? nil : stmt.columnText(at: 14),
            inputFiles: stmt.columnText(at: 3).components(separatedBy: "\n").filter { !$0.isEmpty },
            outputFiles: stmt.columnText(at: 4).components(separatedBy: "\n").filter { !$0.isEmpty },
            status: ExecutionStatus(rawValue: stmt.columnText(at: 5)) ?? .failed,
            exitCode: stmt.columnIsNull(at: 6) ? nil : Int32(stmt.columnInt(at: 6)),
            stdout: stmt.columnText(at: 7),
            stderr: stmt.columnText(at: 8),
            startedAt: dateFormatter.date(from: stmt.columnText(at: 9)) ?? Date(),
            endedAt: stmt.columnIsNull(at: 10) ? nil : dateFormatter.date(from: stmt.columnText(at: 10))
        )
    }
}
