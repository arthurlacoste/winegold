import Foundation

struct RecipeChildActionParser {
    func parse(lines: [String]) throws -> [RecipeChildAction] {
        guard let start = lines.firstIndex(where: { $0.indent == 0 && $0.trimmed == "actions:" }) else { return [] }
        var ranges: [Range<Int>] = []
        var itemStart: Int?
        var index = start + 1
        while index < lines.count {
            let line = lines[index]
            if !line.trimmed.isEmpty && line.indent == 0 { break }
            if line.indent == 2 && line.trimmed.hasPrefix("-") {
                if let itemStart { ranges.append(itemStart..<index) }
                itemStart = index
            }
            index += 1
        }
        if let itemStart { ranges.append(itemStart..<index) }

        var seen = Set<String>()
        return try ranges.map { range in
            let childLines = Array(lines[range])
            let id = value("id", lines: childLines, firstItem: true) ?? ""
            guard isValidID(id) else { throw RecipeError.invalidChildActionID(id) }
            guard seen.insert(id).inserted else { throw RecipeError.duplicateChildActionID(id) }
            guard let name = value("name", lines: childLines), !name.isEmpty else { throw RecipeError.missingField("actions[].name") }
            guard let command = nestedValue(section: "cmd", key: "exec", lines: childLines), !command.isEmpty else { throw RecipeError.missingField("actions[\(id)].cmd.exec") }
            return RecipeChildAction(
                id: id,
                name: name,
                description: value("description", lines: childLines) ?? "",
                iconName: value("icon", lines: childLines),
                command: command,
                successMessage: value("successMessage", lines: childLines),
                requiresConfirmation: try optionalBool("requiresConfirmation", lines: childLines),
                timeoutSeconds: value("timeout", lines: childLines).flatMap(Int.init),
                requirements: nestedList(section: "requires", key: "commands", lines: childLines),
                enabled: try optionalBool("enabled", lines: childLines) ?? true
            )
        }
    }

    private func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, !id.contains("/") else { return false }
        return id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]*$", options: .regularExpression) != nil
    }

    private func optionalBool(_ key: String, lines: [String]) throws -> Bool? {
        guard let raw = value(key, lines: lines) else { return nil }
        switch raw.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: throw RecipeError.invalidBoolean(raw)
        }
    }

    private func value(_ key: String, lines: [String], firstItem: Bool = false) -> String? {
        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmed
            let prefix = firstItem && index == 0 ? "- \(key):" : "\(key):"
            guard trimmed == prefix || trimmed.hasPrefix(prefix + " ") else { continue }
            let value = trimmed.afterColon
            if value.isBlockMarker { return block(after: index, indent: raw.indent, lines: lines) }
            return value.unquoted
        }
        return nil
    }

    private func nestedValue(section: String, key: String, lines: [String]) -> String? {
        guard let sectionIndex = lines.firstIndex(where: { $0.trimmed == "\(section):" }) else { return nil }
        let sectionIndent = lines[sectionIndex].indent
        for index in (sectionIndex + 1)..<lines.count {
            let raw = lines[index]
            if !raw.trimmed.isEmpty && raw.indent <= sectionIndent { break }
            guard raw.trimmed.hasPrefix("\(key):") else { continue }
            let value = raw.trimmed.afterColon
            if value.isBlockMarker { return block(after: index, indent: raw.indent, lines: lines) }
            return value.unquoted
        }
        return nil
    }

    private func nestedList(section: String, key: String, lines: [String]) -> [String] {
        guard let sectionIndex = lines.firstIndex(where: { $0.trimmed == "\(section):" }) else { return [] }
        let sectionIndent = lines[sectionIndex].indent
        var collecting = false
        var values: [String] = []
        for raw in lines.dropFirst(sectionIndex + 1) {
            if !raw.trimmed.isEmpty && raw.indent <= sectionIndent { break }
            if raw.trimmed.hasPrefix("\(key):") { collecting = true; continue }
            if collecting, raw.trimmed.hasPrefix("-") {
                let value = String(raw.trimmed.dropFirst()).unquoted
                if !value.isEmpty { values.append(value) }
            }
        }
        return values
    }

    private func block(after index: Int, indent: Int, lines: [String]) -> String {
        let candidates = lines.dropFirst(index + 1).prefix { $0.trimmed.isEmpty || $0.indent > indent }
        let minIndent = candidates.filter { !$0.trimmed.isEmpty }.map(\.indent).min() ?? 0
        return candidates.map { $0.count >= minIndent ? String($0.dropFirst(minIndent)) : "" }
            .joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

extension RecipeDocument {
    var actionExternalIDs: [String] {
        guard let id else { return [] }
        return actions.isEmpty ? [id] : actions.map { "\(id)/\($0.id)" }
    }

    func resolvedActions(recipeURL: URL, triggerNode: TriggerExpression?) -> [Action] {
        let normalizedTrigger = triggerNode.map { TriggerSerializer().serialize($0) }
        let acceptedExtensions = triggerNode.map { RecipeParser.extensions(from: $0) } ?? []
        let minimumInputCount = minimumInputCount ?? (triggerNode == nil ? 0 : 1)
        let maximumInputCount = maximumInputCount
        let definitions = actions.isEmpty
            ? [RecipeChildAction(id: "", name: name, description: description, iconName: "terminal", command: command, successMessage: successMessage, requiresConfirmation: false, timeoutSeconds: 120, requirements: [], enabled: enabled)]
            : actions
        let parentID = id ?? ""
        return definitions.enumerated().map { index, child in
            let externalID = actions.isEmpty ? parentID : "\(parentID)/\(child.id)"
            return Action(
                id: RecipeParser.runtimeUUID(for: externalID),
                name: child.name,
                description: child.description,
                category: category,
                iconName: child.iconName ?? "terminal",
                enabled: enabled && child.enabled,
                acceptedExtensions: acceptedExtensions,
                triggerExpression: normalizedTrigger,
                minimumInputCount: minimumInputCount,
                maximumInputCount: maximumInputCount,
                executablePath: "/bin/zsh",
                argumentsTemplate: ["-lc", child.command],
                workingDirectoryTemplate: recipeURL.deletingLastPathComponent().path,
                successMessage: child.successMessage,
                requiresConfirmation: child.requiresConfirmation ?? false,
                timeoutSeconds: child.timeoutSeconds ?? 120,
                displayOrder: index
            )
        }
    }

    func requirements(forActionExternalID externalID: String) -> [String] {
        guard let childID = externalID.split(separator: "/").last.map(String.init),
              let child = actions.first(where: { $0.id == childID }) else { return requirements }
        var merged = requirements
        for requirement in child.requirements where !merged.contains(requirement) { merged.append(requirement) }
        return merged
    }
}
