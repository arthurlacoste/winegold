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

    private var actionColumns: String {
        "id, name, description, icon_name, enabled, accepted_extensions, accepted_utis, executable_path, arguments_template, working_directory_template, output_path_template, requires_confirmation, timeout_seconds, is_favorite, display_order, created_at, updated_at"
    }

    public func listActions() throws -> [Action] {
        let stmt = try db.prepare("SELECT \(actionColumns) FROM actions ORDER BY is_favorite DESC, display_order ASC, name ASC")
        var actions: [Action] = []
        while stmt.step() {
            actions.append(try rowToAction(stmt))
        }
        return actions
    }

    public func listEnabledActions() throws -> [Action] {
        let stmt = try db.prepare("SELECT \(actionColumns) FROM actions WHERE enabled = 1 ORDER BY is_favorite DESC, display_order ASC, name ASC")
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
            output_path_template, requires_confirmation, timeout_seconds, is_favorite, display_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                isFavorite: existing.isFavorite,
                displayOrder: existing.displayOrder,
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
            output_path_template=?, requires_confirmation=?, timeout_seconds=?, is_favorite=?,
            display_order=?, created_at=?, updated_at=? WHERE id=?
        """)
        bindActionForUpdate(action, to: stmt)
        _ = stmt.step()
    }

    public func deleteAction(id: UUID) throws {
        let stmt = try db.prepare("DELETE FROM actions WHERE id = ?")
        stmt.bindText(id.uuidString, at: 1)
        _ = stmt.step()
    }

    public func setFavorite(id: UUID, isFavorite: Bool) throws {
        let stmt = try db.prepare("UPDATE actions SET is_favorite=?, updated_at=? WHERE id=?")
        stmt.bindInt(isFavorite ? 1 : 0, at: 1)
        stmt.bindText(dateFormatter.string(from: Date()), at: 2)
        stmt.bindText(id.uuidString, at: 3)
        _ = stmt.step()
    }

    public func moveAction(sourceID: UUID, before targetID: UUID) throws {
        var ordered = try listActions()
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = ordered.firstIndex(where: { $0.id == targetID }),
              sourceID != targetID else { return }
        let source = ordered.remove(at: sourceIndex)
        let adjustedTargetIndex = ordered.firstIndex(where: { $0.id == targetID }) ?? targetIndex
        ordered.insert(source, at: adjustedTargetIndex)
        for (index, action) in ordered.enumerated() {
            let stmt = try db.prepare("UPDATE actions SET display_order=?, updated_at=? WHERE id=?")
            stmt.bindInt(index, at: 1)
            stmt.bindText(dateFormatter.string(from: Date()), at: 2)
            stmt.bindText(action.id.uuidString, at: 3)
            _ = stmt.step()
        }
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
            argumentsTemplate: decodeArgumentsTemplate(argsStr, executablePath: stmt.columnText(at: 7)),
            workingDirectoryTemplate: stmt.columnIsNull(at: 9) ? nil : stmt.columnText(at: 9),
            outputPathTemplate: stmt.columnIsNull(at: 10) ? nil : stmt.columnText(at: 10),
            requiresConfirmation: stmt.columnInt(at: 11) != 0,
            timeoutSeconds: stmt.columnInt(at: 12),
            isFavorite: stmt.columnInt(at: 13) != 0,
            displayOrder: stmt.columnInt(at: 14),
            createdAt: dateFormatter.date(from: stmt.columnText(at: 15)) ?? Date(),
            updatedAt: dateFormatter.date(from: stmt.columnText(at: 16)) ?? Date()
        )
    }

    private func bindAction(_ action: Action, to stmt: Statement) {
        stmt.bindText(action.id.uuidString, at: 1)
        bindActionFields(action, to: stmt, startingAt: 2)
    }

    private func bindActionForUpdate(_ action: Action, to stmt: Statement) {
        bindActionFields(action, to: stmt, startingAt: 1)
        stmt.bindText(action.id.uuidString, at: 17)
    }

    private func encodeArgumentsTemplate(_ arguments: [String]) -> String {
        guard !arguments.isEmpty else { return "" }
        if let data = try? JSONEncoder().encode(arguments), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return arguments.joined(separator: "\n")
    }

    private func decodeArgumentsTemplate(_ storedValue: String, executablePath: String) -> [String] {
        guard !storedValue.isEmpty else { return [] }

        if let data = storedValue.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }

        if executablePath == "/bin/zsh", storedValue.hasPrefix("-lc\n") {
            return ["-lc", String(storedValue.dropFirst(4))]
        }

        return storedValue.components(separatedBy: "\n")
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
        stmt.bindText(encodeArgumentsTemplate(action.argumentsTemplate), at: start + 7)
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
        stmt.bindInt(action.isFavorite ? 1 : 0, at: start + 12)
        stmt.bindInt(action.displayOrder, at: start + 13)
        stmt.bindText(dateFormatter.string(from: action.createdAt), at: start + 14)
        stmt.bindText(dateFormatter.string(from: action.updatedAt), at: start + 15)
    }
}
