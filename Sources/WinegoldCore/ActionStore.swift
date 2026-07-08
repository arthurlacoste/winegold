import Foundation
import CSQLite

public struct ActionStore {
    private let db: Database
    private let dateFormatter: DateFormatter

    public init(db: Database) {
        self.db = db
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    }

    public func listActions() throws -> [Action] {
        let stmt = try db.prepare("SELECT * FROM actions ORDER BY name")
        var actions: [Action] = []
        while stmt.step() {
            actions.append(try rowToAction(stmt))
        }
        return actions
    }

    public func listEnabledActions() throws -> [Action] {
        let stmt = try db.prepare("SELECT * FROM actions WHERE enabled = 1 ORDER BY name")
        var actions: [Action] = []
        while stmt.step() {
            actions.append(try rowToAction(stmt))
        }
        return actions
    }

    public func createAction(_ action: Action) throws {
        let stmt = try db.prepare("""
            INSERT INTO actions (id, name, description, icon_name, enabled, accepted_extensions,
            accepted_utis, executable_path, arguments_template, working_directory_template,
            output_path_template, requires_confirmation, timeout_seconds, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        bindAction(action, to: stmt)
        _ = stmt.step()
    }


    public func upsertActionByName(_ action: Action) throws -> Bool {
        let existing = try listActions().first { $0.name == action.name }
        if let existing {
            let updated = Action(
                id: existing.id,
                name: action.name,
                description: action.description,
                iconName: action.iconName,
                enabled: action.enabled,
                acceptedExtensions: action.acceptedExtensions,
                acceptedUTIs: action.acceptedUTIs,
                executablePath: action.executablePath,
                argumentsTemplate: action.argumentsTemplate,
                workingDirectoryTemplate: action.workingDirectoryTemplate,
                outputPathTemplate: action.outputPathTemplate,
                requiresConfirmation: action.requiresConfirmation,
                timeoutSeconds: action.timeoutSeconds,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
            try updateAction(updated)
            return false
        }

        try createAction(action)
        return true
    }

    public func deleteDuplicateActionsByName(keeping name: String) throws {
        let matching = try listActions().filter { $0.name == name }
        guard matching.count > 1 else { return }
        for duplicate in matching.dropFirst() {
            try deleteAction(id: duplicate.id)
        }
    }

    public func updateAction(_ action: Action) throws {
        let stmt = try db.prepare("""
            UPDATE actions SET name=?, description=?, icon_name=?, enabled=?, accepted_extensions=?,
            accepted_utis=?, executable_path=?, arguments_template=?, working_directory_template=?,
            output_path_template=?, requires_confirmation=?, timeout_seconds=?, created_at=?,
            updated_at=? WHERE id=?
        """)
        bindActionForUpdate(action, to: stmt)
        _ = stmt.step()
    }

    public func deleteAction(id: UUID) throws {
        let stmt = try db.prepare("DELETE FROM actions WHERE id = ?")
        stmt.bindText(id.uuidString, at: 1)
        _ = stmt.step()
    }

    public func count() throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM actions")
        if stmt.step() {
            return stmt.columnInt(at: 0)
        }
        return 0
    }

    private func rowToAction(_ stmt: Statement) throws -> Action {
        let extsStr = stmt.columnText(at: 5)
        let utisStr = stmt.columnText(at: 6)
        let argsStr = stmt.columnText(at: 8)

        return Action(
            id: UUID(uuidString: stmt.columnText(at: 0)) ?? UUID(),
            name: stmt.columnText(at: 1),
            description: stmt.columnText(at: 2),
            iconName: stmt.columnIsNull(at: 3) ? nil : stmt.columnText(at: 3),
            enabled: stmt.columnInt(at: 4) != 0,
            acceptedExtensions: extsStr.isEmpty ? [] : extsStr.components(separatedBy: ","),
            acceptedUTIs: utisStr.isEmpty ? [] : utisStr.components(separatedBy: ","),
            executablePath: stmt.columnText(at: 7),
            argumentsTemplate: argsStr.isEmpty ? [] : argsStr.components(separatedBy: "\n"),
            workingDirectoryTemplate: stmt.columnIsNull(at: 9) ? nil : stmt.columnText(at: 9),
            outputPathTemplate: stmt.columnIsNull(at: 10) ? nil : stmt.columnText(at: 10),
            requiresConfirmation: stmt.columnInt(at: 11) != 0,
            timeoutSeconds: stmt.columnInt(at: 12),
            createdAt: dateFormatter.date(from: stmt.columnText(at: 13)) ?? Date(),
            updatedAt: dateFormatter.date(from: stmt.columnText(at: 14)) ?? Date()
        )
    }

    private func bindAction(_ action: Action, to stmt: Statement) {
        stmt.bindText(action.id.uuidString, at: 1)
        bindActionFields(action, to: stmt, startingAt: 2)
    }

    private func bindActionForUpdate(_ action: Action, to stmt: Statement) {
        bindActionFields(action, to: stmt, startingAt: 1)
        stmt.bindText(action.id.uuidString, at: 15)
    }

    private func bindActionFields(_ action: Action, to stmt: Statement, startingAt start: Int32) {
        stmt.bindText(action.name, at: start)
        stmt.bindText(action.description, at: start + 1)
        if let icon = action.iconName {
            stmt.bindText(icon, at: start + 2)
        } else {
            stmt.bindNull(at: start + 2)
        }
        stmt.bindInt(action.enabled ? 1 : 0, at: start + 3)
        stmt.bindText(action.acceptedExtensions.joined(separator: ","), at: start + 4)
        stmt.bindText(action.acceptedUTIs.joined(separator: ","), at: start + 5)
        stmt.bindText(action.executablePath, at: start + 6)
        stmt.bindText(action.argumentsTemplate.joined(separator: "\n"), at: start + 7)
        if let wd = action.workingDirectoryTemplate {
            stmt.bindText(wd, at: start + 8)
        } else {
            stmt.bindNull(at: start + 8)
        }
        if let out = action.outputPathTemplate {
            stmt.bindText(out, at: start + 9)
        } else {
            stmt.bindNull(at: start + 9)
        }
        stmt.bindInt(action.requiresConfirmation ? 1 : 0, at: start + 10)
        stmt.bindInt(action.timeoutSeconds, at: start + 11)
        stmt.bindText(dateFormatter.string(from: action.createdAt), at: start + 12)
        stmt.bindText(dateFormatter.string(from: action.updatedAt), at: start + 13)
    }
}
