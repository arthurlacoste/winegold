import Foundation
import CSQLite

public struct RecipeActionMetadata: Equatable {
    public let action: Action
    public let externalID: String?
    public let parentExternalID: String?
    public let childActionID: String?
    public let parentName: String?
    public let usageCount: Int
    public let lastUsedAt: Date?
    public let localEnabledOverride: Bool?
    public let localOrderOverride: Int?

    public var effectiveEnabled: Bool { localEnabledOverride ?? action.enabled }
}

public struct ActionStore {
    private let db: Database
    private let dateFormatter: DateFormatter

    public init(db: Database) {
        self.db = db
        self.dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    }

    private var actionColumns: String {
        "id, name, description, icon_name, enabled, accepted_extensions, accepted_utis, trigger_expression, executable_path, arguments_template, working_directory_template, output_path_template, success_message, requires_confirmation, timeout_seconds, is_favorite, display_order, created_at, updated_at, category, minimum_input_count, maximum_input_count"
    }

    public func listActions() throws -> [Action] {
        let stmt = try db.prepare("SELECT \(actionColumns) FROM actions WHERE available = 1 ORDER BY is_favorite DESC, display_order ASC, name ASC")
        var actions: [Action] = []
        while stmt.step() {
            actions.append(try rowToAction(stmt))
        }
        return actions
    }

    public func listEnabledActions() throws -> [Action] {
        let stmt = try db.prepare("SELECT \(actionColumns) FROM actions WHERE enabled = 1 AND available = 1 ORDER BY is_favorite DESC, display_order ASC, name ASC")
        var actions: [Action] = []
        while stmt.step() {
            actions.append(try rowToAction(stmt))
        }
        return actions
    }

    public func upsertDerivedRecipe(
        _ action: Action,
        externalID: String,
        parentExternalID: String? = nil,
        childActionID: String? = nil,
        parentName: String? = nil,
        path: String,
        hash: String,
        category: String?,
        available: Bool = true
    ) throws {
        let claimLegacy = try db.prepare("UPDATE actions SET external_id=?, source_kind='recipe' WHERE id=? AND external_id IS NULL")
        claimLegacy.bindText(externalID, at: 1)
        claimLegacy.bindText(action.id.uuidString, at: 2)
        _ = claimLegacy.step()
        let existing = try db.prepare("SELECT is_favorite, display_order, created_at, local_enabled_override, local_order_override FROM actions WHERE external_id=?")
        existing.bindText(externalID, at: 1)
        var derived = action
        var localEnabledOverride: Bool?
        var localOrderOverride: Int?
        if existing.step() {
            derived.isFavorite = existing.columnInt(at: 0) != 0
            derived.displayOrder = existing.columnInt(at: 1)
            derived.createdAt = dateFormatter.date(from: existing.columnText(at: 2)) ?? action.createdAt
            localEnabledOverride = existing.columnIsNull(at: 3) ? nil : existing.columnInt(at: 3) != 0
            localOrderOverride = existing.columnIsNull(at: 4) ? nil : existing.columnInt(at: 4)
        }
        if let localEnabledOverride { derived.enabled = localEnabledOverride }
        if let localOrderOverride { derived.displayOrder = localOrderOverride }
        let stmt = try db.prepare("""
            INSERT INTO actions (id, name, description, icon_name, enabled, accepted_extensions, accepted_utis,
            trigger_expression, executable_path, arguments_template, working_directory_template, output_path_template,
            success_message, requires_confirmation, timeout_seconds, is_favorite, display_order, created_at, updated_at,
            source_kind, external_id, recipe_path, recipe_hash, available, category, parent_external_id, child_action_id,
            parent_name, local_enabled_override, local_order_override, minimum_input_count, maximum_input_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'recipe', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(external_id) DO UPDATE SET id=excluded.id, name=excluded.name, description=excluded.description,
            icon_name=excluded.icon_name, enabled=excluded.enabled, accepted_extensions=excluded.accepted_extensions,
            accepted_utis=excluded.accepted_utis, trigger_expression=excluded.trigger_expression,
            executable_path=excluded.executable_path, arguments_template=excluded.arguments_template,
            working_directory_template=excluded.working_directory_template, output_path_template=excluded.output_path_template,
            success_message=excluded.success_message, requires_confirmation=excluded.requires_confirmation,
            timeout_seconds=excluded.timeout_seconds, updated_at=excluded.updated_at, recipe_path=excluded.recipe_path,
            recipe_hash=excluded.recipe_hash, available=excluded.available, category=excluded.category,
            parent_external_id=excluded.parent_external_id, child_action_id=excluded.child_action_id,
            parent_name=excluded.parent_name, local_enabled_override=excluded.local_enabled_override,
            local_order_override=excluded.local_order_override, minimum_input_count=excluded.minimum_input_count,
            maximum_input_count=excluded.maximum_input_count
        """)
        bindAction(derived, to: stmt)
        stmt.bindText(externalID, at: 20)
        stmt.bindText(path, at: 21)
        stmt.bindText(hash, at: 22)
        stmt.bindInt(available ? 1 : 0, at: 23)
        if let category { stmt.bindText(category, at: 24) } else { stmt.bindNull(at: 24) }
        if let parentExternalID { stmt.bindText(parentExternalID, at: 25) } else { stmt.bindNull(at: 25) }
        if let childActionID { stmt.bindText(childActionID, at: 26) } else { stmt.bindNull(at: 26) }
        if let parentName { stmt.bindText(parentName, at: 27) } else { stmt.bindNull(at: 27) }
        if let localEnabledOverride { stmt.bindInt(localEnabledOverride ? 1 : 0, at: 28) } else { stmt.bindNull(at: 28) }
        if let localOrderOverride { stmt.bindInt(localOrderOverride, at: 29) } else { stmt.bindNull(at: 29) }
        stmt.bindInt(derived.minimumInputCount, at: 30)
        if let maximum = derived.maximumInputCount { stmt.bindInt(maximum, at: 31) } else { stmt.bindNull(at: 31) }
        _ = stmt.step()
    }

    public func createAction(_ action: Action) throws {
        let stmt = try db.prepare("""
            INSERT INTO actions (id, name, description, icon_name, enabled, accepted_extensions,
            accepted_utis, trigger_expression, executable_path, arguments_template, working_directory_template,
            output_path_template, success_message, requires_confirmation, timeout_seconds, is_favorite, display_order, created_at, updated_at, minimum_input_count, maximum_input_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                triggerExpression: action.triggerExpression,
                minimumInputCount: action.minimumInputCount,
                maximumInputCount: action.maximumInputCount,
                executablePath: action.executablePath,
                argumentsTemplate: action.argumentsTemplate,
                workingDirectoryTemplate: action.workingDirectoryTemplate,
                outputPathTemplate: action.outputPathTemplate,
                successMessage: action.successMessage,
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
            accepted_utis=?, trigger_expression=?, executable_path=?, arguments_template=?, working_directory_template=?,
            output_path_template=?, success_message=?, requires_confirmation=?, timeout_seconds=?, is_favorite=?,
            display_order=?, created_at=?, updated_at=?, minimum_input_count=?, maximum_input_count=? WHERE id=?
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

    public func metadata(for actionID: UUID) throws -> RecipeActionMetadata? {
        let stmt = try db.prepare("""
            SELECT \(actionColumns), external_id, parent_external_id, child_action_id, parent_name,
                   usage_count, last_used_at, local_enabled_override, local_order_override
            FROM actions WHERE id=?
        """)
        stmt.bindText(actionID.uuidString, at: 1)
        guard stmt.step() else { return nil }
        let action = try rowToAction(stmt)
        return RecipeActionMetadata(
            action: action,
            externalID: stmt.columnIsNull(at: 22) ? nil : stmt.columnText(at: 22),
            parentExternalID: stmt.columnIsNull(at: 23) ? nil : stmt.columnText(at: 23),
            childActionID: stmt.columnIsNull(at: 24) ? nil : stmt.columnText(at: 24),
            parentName: stmt.columnIsNull(at: 25) ? nil : stmt.columnText(at: 25),
            usageCount: stmt.columnInt(at: 26),
            lastUsedAt: stmt.columnIsNull(at: 27) ? nil : dateFormatter.date(from: stmt.columnText(at: 27)),
            localEnabledOverride: stmt.columnIsNull(at: 28) ? nil : stmt.columnInt(at: 28) != 0,
            localOrderOverride: stmt.columnIsNull(at: 29) ? nil : stmt.columnInt(at: 29)
        )
    }

    public func metadata(for actionIDs: [UUID]) throws -> [UUID: RecipeActionMetadata] {
        Dictionary(uniqueKeysWithValues: try actionIDs.compactMap { id in
            try metadata(for: id).map { (id, $0) }
        })
    }

    public func listActions(forParentID parentID: String, includeUnavailable: Bool = false) throws -> [RecipeActionMetadata] {
        let availability = includeUnavailable ? "" : " AND available=1"
        let stmt = try db.prepare("SELECT id FROM actions WHERE parent_external_id=?\(availability) ORDER BY COALESCE(local_order_override, display_order), name")
        stmt.bindText(parentID, at: 1)
        var result: [RecipeActionMetadata] = []
        while stmt.step(), let id = UUID(uuidString: stmt.columnText(at: 0)), let value = try metadata(for: id) { result.append(value) }
        return result
    }

    public func setLocalEnabledOverride(actionID: UUID, value: Bool) throws {
        let stmt = try db.prepare("UPDATE actions SET local_enabled_override=?, enabled=?, updated_at=? WHERE id=?")
        stmt.bindInt(value ? 1 : 0, at: 1)
        stmt.bindInt(value ? 1 : 0, at: 2)
        stmt.bindText(dateFormatter.string(from: Date()), at: 3)
        stmt.bindText(actionID.uuidString, at: 4)
        _ = stmt.step()
    }

    public func clearLocalEnabledOverride(actionID: UUID) throws {
        let stmt = try db.prepare("UPDATE actions SET local_enabled_override=NULL, updated_at=? WHERE id=?")
        stmt.bindText(dateFormatter.string(from: Date()), at: 1)
        stmt.bindText(actionID.uuidString, at: 2)
        _ = stmt.step()
    }

    public func setLocalOrder(parentID: String, orderedActionIDs: [UUID]) throws {
        try db.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let clear = try db.prepare("UPDATE actions SET local_order_override=NULL WHERE parent_external_id=?")
            clear.bindText(parentID, at: 1)
            _ = clear.step()
            for (index, id) in orderedActionIDs.enumerated() {
                let stmt = try db.prepare("UPDATE actions SET local_order_override=?, display_order=?, updated_at=? WHERE id=? AND parent_external_id=?")
                stmt.bindInt(index, at: 1)
                stmt.bindInt(index, at: 2)
                stmt.bindText(dateFormatter.string(from: Date()), at: 3)
                stmt.bindText(id.uuidString, at: 4)
                stmt.bindText(parentID, at: 5)
                _ = stmt.step()
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    public func clearLocalOrder(parentID: String) throws {
        let stmt = try db.prepare("UPDATE actions SET local_order_override=NULL, updated_at=? WHERE parent_external_id=?")
        stmt.bindText(dateFormatter.string(from: Date()), at: 1)
        stmt.bindText(parentID, at: 2)
        _ = stmt.step()
    }

    public func incrementUsage(actionID: UUID, at date: Date = Date()) throws {
        let stmt = try db.prepare("UPDATE actions SET usage_count=usage_count+1, last_used_at=?, updated_at=? WHERE id=?")
        let timestamp = dateFormatter.string(from: date)
        stmt.bindText(timestamp, at: 1)
        stmt.bindText(timestamp, at: 2)
        stmt.bindText(actionID.uuidString, at: 3)
        _ = stmt.step()
    }

    public func count() throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM actions")
        if stmt.step() {
            return stmt.columnInt(at: 0)
        }
        return 0
    }

    public func listNeedingSetup() throws -> [Action] {
        let stmt = try db.prepare("SELECT \(actionColumns) FROM actions WHERE source_kind='recipe' AND available=0 AND enabled=1 ORDER BY name ASC")
        var actions: [Action] = []
        while stmt.step() {
            actions.append(try rowToAction(stmt))
        }
        return actions
    }

    public func setAvailable(id: UUID, available: Bool) throws {
        let stmt = try db.prepare("UPDATE actions SET available=?, updated_at=? WHERE id=?")
        stmt.bindInt(available ? 1 : 0, at: 1)
        stmt.bindText(dateFormatter.string(from: Date()), at: 2)
        stmt.bindText(id.uuidString, at: 3)
        _ = stmt.step()
    }

    private func rowToAction(_ stmt: Statement) throws -> Action {
        let extsStr = stmt.columnText(at: 5)
        let utisStr = stmt.columnText(at: 6)
        let argsStr = stmt.columnText(at: 9)

        return Action(
            id: UUID(uuidString: stmt.columnText(at: 0)) ?? UUID(),
            name: stmt.columnText(at: 1),
            description: stmt.columnText(at: 2),
            category: stmt.columnIsNull(at: 19) ? nil : stmt.columnText(at: 19),
            iconName: stmt.columnIsNull(at: 3) ? nil : stmt.columnText(at: 3),
            enabled: stmt.columnInt(at: 4) != 0,
            acceptedExtensions: extsStr.isEmpty ? [] : extsStr.components(separatedBy: ","),
            acceptedUTIs: utisStr.isEmpty ? [] : utisStr.components(separatedBy: ","),
            triggerExpression: stmt.columnIsNull(at: 7) ? nil : stmt.columnText(at: 7),
            minimumInputCount: stmt.columnInt(at: 20),
            maximumInputCount: stmt.columnIsNull(at: 21) ? nil : stmt.columnInt(at: 21),
            executablePath: stmt.columnText(at: 8),
            argumentsTemplate: decodeArgumentsTemplate(argsStr, executablePath: stmt.columnText(at: 8)),
            workingDirectoryTemplate: stmt.columnIsNull(at: 10) ? nil : stmt.columnText(at: 10),
            outputPathTemplate: stmt.columnIsNull(at: 11) ? nil : stmt.columnText(at: 11),
            successMessage: stmt.columnIsNull(at: 12) ? nil : stmt.columnText(at: 12),
            requiresConfirmation: stmt.columnInt(at: 13) != 0,
            timeoutSeconds: stmt.columnInt(at: 14),
            isFavorite: stmt.columnInt(at: 15) != 0,
            displayOrder: stmt.columnInt(at: 16),
            createdAt: dateFormatter.date(from: stmt.columnText(at: 17)) ?? Date(),
            updatedAt: dateFormatter.date(from: stmt.columnText(at: 18)) ?? Date()
        )
    }

    private func bindAction(_ action: Action, to stmt: Statement) {
        stmt.bindText(action.id.uuidString, at: 1)
        bindActionFields(action, to: stmt, startingAt: 2)
    }

    private func bindActionForUpdate(_ action: Action, to stmt: Statement) {
        bindActionFields(action, to: stmt, startingAt: 1)
        stmt.bindText(action.id.uuidString, at: 21)
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
        if let trigger = action.triggerExpression { stmt.bindText(trigger, at: start + 6) } else { stmt.bindNull(at: start + 6) }
        stmt.bindText(action.executablePath, at: start + 7)
        stmt.bindText(encodeArgumentsTemplate(action.argumentsTemplate), at: start + 8)
        if let wd = action.workingDirectoryTemplate {
            stmt.bindText(wd, at: start + 9)
        } else {
            stmt.bindNull(at: start + 9)
        }
        if let out = action.outputPathTemplate {
            stmt.bindText(out, at: start + 10)
        } else {
            stmt.bindNull(at: start + 10)
        }
        if let message = action.successMessage {
            stmt.bindText(message, at: start + 11)
        } else {
            stmt.bindNull(at: start + 11)
        }
        stmt.bindInt(action.requiresConfirmation ? 1 : 0, at: start + 12)
        stmt.bindInt(action.timeoutSeconds, at: start + 13)
        stmt.bindInt(action.isFavorite ? 1 : 0, at: start + 14)
        stmt.bindInt(action.displayOrder, at: start + 15)
        stmt.bindText(dateFormatter.string(from: action.createdAt), at: start + 16)
        stmt.bindText(dateFormatter.string(from: action.updatedAt), at: start + 17)
        stmt.bindInt(action.minimumInputCount, at: start + 18)
        if let maximum = action.maximumInputCount { stmt.bindInt(maximum, at: start + 19) } else { stmt.bindNull(at: start + 19) }
    }
}
