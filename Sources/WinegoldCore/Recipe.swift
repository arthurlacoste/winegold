import Foundation
import CryptoKit

public struct RecipeChildAction: Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var iconName: String?
    public var command: String
    public var successMessage: String?
    public var requiresConfirmation: Bool?
    public var timeoutSeconds: Int?
    public var requirements: [String]
    public var enabled: Bool

    public init(id: String, name: String, description: String = "", iconName: String? = nil, command: String, successMessage: String? = nil, requiresConfirmation: Bool? = nil, timeoutSeconds: Int? = nil, requirements: [String] = [], enabled: Bool = true) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.command = command
        self.successMessage = successMessage
        self.requiresConfirmation = requiresConfirmation
        self.timeoutSeconds = timeoutSeconds
        self.requirements = requirements
        self.enabled = enabled
    }
}

public struct RecipeDocument: Equatable {
    public var id: String?
    public var name: String
    public var description: String
    public var version: String?
    public var author: String?
    public var category: String?
    public var homepage: String?
    public var enabled: Bool
    public var trigger: String
    public var command: String
    public var actions: [RecipeChildAction]
    public var successMessage: String?
    public var supportFiles: [String]
    public var requirements: [String]
    public var variables: [RecipeVariable]?

    public init(id: String? = nil, name: String, description: String = "", version: String? = nil, author: String? = nil, category: String? = nil, homepage: String? = nil, enabled: Bool = true, trigger: String, command: String, successMessage: String? = nil, supportFiles: [String] = [], requirements: [String] = [], variables: [RecipeVariable]? = nil, actions: [RecipeChildAction] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.category = category
        self.homepage = homepage
        self.enabled = enabled
        self.trigger = trigger
        self.command = command
        self.actions = actions
        self.successMessage = successMessage
        self.supportFiles = supportFiles
        self.requirements = requirements
        self.variables = variables
    }
}

public struct RecipeRecord: Equatable {
    public let document: RecipeDocument
    public let actions: [Action]
    public let warnings: [String]
    public var action: Action { actions[0] }
    public let url: URL
    public let contentHash: String
}

public enum RecipeError: LocalizedError, Equatable {
    case missingField(String)
    case invalidBoolean(String)
    case invalidTrigger(String)
    case invalidFilename(String)
    case invalidChildActionID(String)
    case duplicateChildActionID(String)
    case outsideRoot

    public var errorDescription: String? {
        switch self {
        case .missingField(let field): return "Missing required recipe field: \(field)"
        case .invalidBoolean(let value): return "Invalid boolean value: \(value)"
        case .invalidTrigger(let value): return "Invalid trigger: \(value)"
        case .invalidFilename(let value): return "Recipe filename must end in .wg.yml: \(value)"
        case .invalidChildActionID(let value): return "Invalid child action id: \(value)"
        case .duplicateChildActionID(let value): return "Duplicate child action id: \(value)"
        case .outsideRoot: return "Recipe path is outside the recipe root"
        }
    }
}

public struct RecipeParser {
    public init() {}

    public func parse(url: URL) throws -> RecipeRecord {
        guard url.lastPathComponent.lowercased().hasSuffix(".wg.yml") else {
            throw RecipeError.invalidFilename(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var document = try parse(text: text)
        let externalID = document.id ?? Self.generatedID()
        document.id = externalID
        let triggerNode: TriggerExpression
        do { triggerNode = try TriggerParser().parse(document.trigger) }
        catch { throw RecipeError.invalidTrigger(document.trigger) }
        let normalizedTrigger = TriggerSerializer().serialize(triggerNode)
        let actions = document.resolvedActions(recipeURL: url, triggerNode: triggerNode)
        let warnings = (!document.actions.isEmpty && !document.command.isEmpty)
            ? ["Recipe \"\(document.name)\" defines both cmd and actions. The top-level cmd was ignored."]
            : []
        return RecipeRecord(document: document, actions: actions, warnings: warnings, url: url, contentHash: Self.hash(data))
    }

    public func repairDraft(url: URL) throws -> RecipeDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        return repairDraft(text: text)
    }

    public func repairDraft(text: String) -> RecipeDocument {
        let lines = text.components(separatedBy: .newlines)
        let name = scalar("name", lines: lines) ?? URL(fileURLWithPath: "recipe").deletingPathExtension().lastPathComponent
        let trigger: String
        if let direct = scalar("trigger", lines: lines), !direct.isEmpty {
            trigger = direct
        } else {
            let extensions = nestedList(section: "trigger", key: "fileExtension", lines: lines)
            trigger = extensions.isEmpty
                ? "extension in {\"*\"}"
                : TriggerSerializer().serialize(.condition(field: "extension", operator: .in, value: .collection(extensions)))
        }
        let command = nestedScalar(section: "cmd", key: "exec", lines: lines) ?? ""
        return RecipeDocument(
            id: scalar("id", lines: lines),
            name: name,
            description: scalar("description", lines: lines) ?? "",
            version: scalar("version", lines: lines),
            author: scalar("author", lines: lines),
            category: scalar("category", lines: lines),
            homepage: scalar("homepage", lines: lines) ?? scalar("source", lines: lines),
            enabled: (scalar("enabled", lines: lines) ?? "true").lowercased() != "false",
            trigger: trigger,
            command: command,
            successMessage: scalar("successMessage", lines: lines),
            supportFiles: topLevelList("files", lines: lines),
            requirements: requirementCommands(lines: lines),
            variables: (try? RecipeVariableParser().parseVariables(lines: lines)).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    public func parse(text: String) throws -> RecipeDocument {
        let lines = text.components(separatedBy: .newlines)
        guard let name = scalar("name", lines: lines), !name.isEmpty else { throw RecipeError.missingField("name") }
        let trigger = try triggerValue(lines: lines)
        let command = nestedScalar(section: "cmd", key: "exec", lines: lines) ?? ""
        let actions = try RecipeChildActionParser().parse(lines: lines)
        guard !command.isEmpty || !actions.isEmpty else { throw RecipeError.missingField("cmd.exec or actions") }
        let enabledText = scalar("enabled", lines: lines) ?? "true"
        let enabled: Bool
        switch enabledText.lowercased() {
        case "true", "yes", "1": enabled = true
        case "false", "no", "0": enabled = false
        default: throw RecipeError.invalidBoolean(enabledText)
        }
        _ = try TriggerParser().parse(trigger)
        let variables = try RecipeVariableParser().parseVariables(lines: lines)
        return RecipeDocument(
            id: scalar("id", lines: lines),
            name: name,
            description: scalar("description", lines: lines) ?? "",
            version: scalar("version", lines: lines),
            author: scalar("author", lines: lines),
            category: scalar("category", lines: lines),
            homepage: scalar("homepage", lines: lines) ?? scalar("source", lines: lines),
            enabled: enabled,
            trigger: trigger,
            command: command,
            successMessage: scalar("successMessage", lines: lines),
            supportFiles: topLevelList("files", lines: lines),
            requirements: requirementCommands(lines: lines),
            variables: variables.isEmpty ? nil : variables,
            actions: actions
        )
    }

    private func triggerValue(lines: [String]) throws -> String {
        if let direct = scalar("trigger", lines: lines), !direct.isEmpty { return direct }
        let extensions = nestedList(section: "trigger", key: "fileExtension", lines: lines)
        guard !extensions.isEmpty else { throw RecipeError.missingField("trigger") }
        return TriggerSerializer().serialize(.condition(field: "extension", operator: .in, value: .collection(extensions)))
    }

    private func scalar(_ key: String, lines: [String]) -> String? {
        for (index, raw) in lines.enumerated() where raw.indent == 0 {
            let trimmed = raw.trimmed
            guard trimmed == "\(key):" || trimmed.hasPrefix("\(key): ") else { continue }
            let value = trimmed.afterColon
            if value.isBlockMarker { return block(after: index, indent: raw.indent, lines: lines) }
            return value.unquoted
        }
        return nil
    }

    private func nestedScalar(section: String, key: String, lines: [String]) -> String? {
        guard let sectionIndex = lines.firstIndex(where: { $0.indent == 0 && $0.trimmed == "\(section):" }) else { return nil }
        for index in (sectionIndex + 1)..<lines.count {
            let raw = lines[index]
            if !raw.trimmed.isEmpty && raw.indent == 0 { break }
            guard raw.trimmed.hasPrefix("\(key):") else { continue }
            let value = raw.trimmed.afterColon
            if value.isBlockMarker { return block(after: index, indent: raw.indent, lines: lines) }
            return value.unquoted
        }
        return nil
    }

    private func nestedList(section: String, key: String, lines: [String]) -> [String] {
        guard let sectionIndex = lines.firstIndex(where: { $0.indent == 0 && $0.trimmed == "\(section):" }) else { return [] }
        var collecting = false
        var values: [String] = []
        for raw in lines.dropFirst(sectionIndex + 1) {
            if !raw.trimmed.isEmpty && raw.indent == 0 { break }
            if raw.trimmed.hasPrefix("\(key):") { collecting = true; continue }
            if collecting, raw.trimmed.hasPrefix("-") {
                values.append(String(raw.trimmed.dropFirst()).unquoted.lowercased())
            }
        }
        return values
    }


    private func requirementCommands(lines: [String]) -> [String] {
        let nested = nestedList(section: "requires", key: "commands", lines: lines)
        return nested.isEmpty ? topLevelList("requirements", lines: lines) : nested
    }

    private func topLevelList(_ key: String, lines: [String]) -> [String] {
        guard let start = lines.firstIndex(where: { $0.indent == 0 && $0.trimmed == "\(key):" }) else { return [] }
        var values: [String] = []
        for raw in lines.dropFirst(start + 1) {
            if !raw.trimmed.isEmpty && raw.indent == 0 { break }
            if raw.trimmed.hasPrefix("-") {
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

    static func generatedID() -> String { "local.\(UUID().uuidString.lowercased())" }

    public static func runtimeUUID(for id: String) -> UUID {
        if let uuid = UUID(uuidString: id) { return uuid }
        let digest = SHA256.hash(data: Data(id.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let tuple: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: tuple)
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func extensions(from node: TriggerExpression) -> [String] {
        guard case let .condition(field, op, value) = node, field == "extension", op == .in,
              case let .collection(values) = value else { return [] }
        return values
    }
}

public struct RecipeSerializer {
    public init() {}

    public func serialize(_ document: RecipeDocument) -> String {
        var lines: [String] = []
        if let id = document.id { lines.append("id: \(quote(id))") }
        lines.append("name: \(quote(document.name))")
        if !document.description.isEmpty { lines.append("description: \(quote(document.description))") }
        if let version = document.version { lines.append("version: \(quote(version))") }
        if let author = document.author { lines.append("author: \(quote(author))") }
        if let category = document.category { lines.append("category: \(quote(category))") }
        if let homepage = document.homepage { lines.append("homepage: \(quote(homepage))") }
        lines.append("enabled: \(document.enabled ? "true" : "false")")
        if let variables = document.variables, !variables.isEmpty {
            let varText = RecipeVariableSerializer().serialize(variables)
            lines.append("")
            lines.append(varText.trimmingCharacters(in: .newlines))
        }
        if !document.supportFiles.isEmpty {
            lines.append("")
            lines.append("files:")
            lines.append(contentsOf: document.supportFiles.map { "  - \(quote($0))" })
        }
        if !document.requirements.isEmpty {
            lines.append("")
            lines.append("requires:")
            lines.append("  commands:")
            lines.append(contentsOf: document.requirements.map { "    - \(quote($0))" })
        }
        lines.append("")
        lines.append("trigger: \(quote(document.trigger))")
        if !document.actions.isEmpty {
            lines.append("")
            lines.append("actions:")
            for action in document.actions {
                lines.append("  - id: \(quote(action.id))")
                lines.append("    name: \(quote(action.name))")
                if !action.description.isEmpty { lines.append("    description: \(quote(action.description))") }
                if let iconName = action.iconName { lines.append("    icon: \(quote(iconName))") }
                lines.append("    enabled: \(action.enabled ? "true" : "false")")
                if !action.requirements.isEmpty {
                    lines.append("    requires:")
                    lines.append("      commands:")
                    lines.append(contentsOf: action.requirements.map { "        - \(quote($0))" })
                }
                lines.append("    cmd:")
                if action.command.contains("\n") {
                    lines.append("      exec: |")
                    lines.append(contentsOf: action.command.components(separatedBy: .newlines).map { "        \($0)" })
                } else {
                    lines.append("      exec: \(quote(action.command))")
                }
                if let message = action.successMessage { lines.append("    successMessage: \(quote(message))") }
                if let confirmation = action.requiresConfirmation { lines.append("    requiresConfirmation: \(confirmation ? "true" : "false")") }
                if let timeout = action.timeoutSeconds { lines.append("    timeout: \(timeout)") }
            }
        } else {
            lines.append("")
            lines.append("cmd:")
            if document.command.contains("\n") {
                lines.append("  exec: |")
                lines.append(contentsOf: document.command.components(separatedBy: .newlines).map { "    \($0)" })
            } else {
                lines.append("  exec: \(quote(document.command))")
            }
        }
        if let message = document.successMessage { lines.append("successMessage: \(quote(message))") }
        appendList("files", values: document.supportFiles, to: &lines)
        appendList("requirements", values: document.requirements, to: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    public func updating(_ existing: String, with document: RecipeDocument) -> String {
        RecipeTextEditor().update(existing: existing, document: document)
    }

    private func appendList(_ key: String, values: [String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append("")
        lines.append("\(key):")
        lines.append(contentsOf: values.map { "  - \(quote($0))" })
    }

    fileprivate func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
}

public struct RecipeFileSnapshot: Equatable {
    public let url: URL
    public let modificationDate: Date
    public let fileSize: Int64
}

public struct RecipeScanner {
    public static let ignoredDirectories: Set<String> = ["node_modules", ".git", ".svn", "vendor", "build", ".build", "dist", "cache", "caches", "__pycache__"]
    public init() {}

    public func scan(root: URL) throws -> [RecipeFileSnapshot] {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsPackageDescendants]) else { return [] }
        var result: [RecipeFileSnapshot] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey])
            if values.isSymbolicLink == true { if values.isDirectory == true { enumerator.skipDescendants() }; continue }
            if values.isDirectory == true {
                let name = url.lastPathComponent.lowercased()
                if name.hasPrefix(".") || Self.ignoredDirectories.contains(name) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, url.lastPathComponent.lowercased().hasSuffix(".wg.yml") else { continue }
            result.append(RecipeFileSnapshot(url: url, modificationDate: values.contentModificationDate ?? .distantPast, fileSize: Int64(values.fileSize ?? 0)))
        }
        return result.sorted { $0.url.path < $1.url.path }
    }
}

public final class RecipeFileStore {
    public let root: URL
    private let parser = RecipeParser()
    private let serializer = RecipeSerializer()

    public init(root: URL) { self.root = root.standardizedFileURL }

    public func write(_ document: RecipeDocument, to url: URL) throws -> RecipeRecord {
        try ensureInsideRoot(url)
        var persisted = document
        if persisted.id == nil { persisted.id = RecipeParser.generatedID() }
        let fm = FileManager.default
        let existingText = fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : nil
        let text = existingText.map { serializer.updating($0, with: persisted) } ?? serializer.serialize(persisted)
        _ = try parser.parse(text: text)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try Data(text.utf8).write(to: temporary, options: .atomic)
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path) }
        _ = try parser.parse(text: String(decoding: Data(contentsOf: temporary), as: UTF8.self))
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: url)
        }
        return try parser.parse(url: url)
    }

    public func repair(_ document: RecipeDocument, at url: URL) throws -> RecipeRecord {
        try ensureInsideRoot(url)
        let fm = FileManager.default
        let existing = try String(contentsOf: url, encoding: .utf8)
        let text = RecipeRepairTextEditor().update(existing: existing, document: document)
        _ = try parser.parse(text: text)
        let permissions = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try Data(text.utf8).write(to: temporary, options: .atomic)
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path) }
        _ = try parser.parse(text: String(decoding: Data(contentsOf: temporary), as: UTF8.self))
        _ = try fm.replaceItemAt(url, withItemAt: temporary)
        return try parser.parse(url: url)
    }

    public func create(_ document: RecipeDocument, category: String = "local") throws -> RecipeRecord {
        let slug = Self.slug(document.name)
        let folder = root.appendingPathComponent(category).appendingPathComponent(slug)
        var destination = folder.appendingPathComponent("\(slug).wg.yml")
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(slug)-\(index).wg.yml"); index += 1
        }
        return try write(document, to: destination)
    }

    public func remove(_ url: URL) throws {
        try ensureInsideRoot(url)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private func ensureInsideRoot(_ url: URL) throws {
        let rootPath = root.resolvingSymlinksInPath().path + "/"
        let target = url.deletingLastPathComponent().resolvingSymlinksInPath().path + "/"
        guard target.hasPrefix(rootPath) || target == rootPath else { throw RecipeError.outsideRoot }
    }

    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let raw = value.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let slug = String(raw).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? "recipe" : slug
    }
}


private struct RecipeRepairTextEditor {
    private let editableKeys = ["name", "trigger", "cmd", "successMessage"]

    func update(existing: String, document: RecipeDocument) -> String {
        var lines = existing.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        let serializer = RecipeSerializer()
        let replacements: [String: [String]] = [
            "name": ["name: \(serializer.quote(document.name))"],
            "trigger": ["trigger: \(serializer.quote(document.trigger))"],
            "cmd": commandBlock(document.command),
            "successMessage": document.successMessage.map { ["successMessage: \(serializer.quote($0))"] } ?? []
        ]

        for key in editableKeys.reversed() {
            if let range = topLevelRange(for: key, in: lines) {
                let replacement = replacements[key] ?? []
                if replacement.isEmpty { lines.removeSubrange(range) }
                else { lines.replaceSubrange(range, with: replacement) }
            }
        }
        for key in editableKeys where topLevelRange(for: key, in: lines) == nil {
            guard let replacement = replacements[key], !replacement.isEmpty else { continue }
            if !lines.isEmpty, lines.last?.isEmpty == false { lines.append("") }
            lines.append(contentsOf: replacement)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    private func commandBlock(_ command: String) -> [String] {
        let serializer = RecipeSerializer()
        if command.contains("\n") {
            return ["cmd:", "  exec: |"] + command.components(separatedBy: .newlines).map { "    \($0)" }
        }
        return ["cmd:", "  exec: \(serializer.quote(command))"]
    }

    private func topLevelRange(for key: String, in lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: {
            $0.indent == 0 && ($0.trimmed == "\(key):" || $0.trimmed.hasPrefix("\(key): "))
        }) else { return nil }
        var end = start + 1
        while end < lines.count {
            if !lines[end].trimmed.isEmpty && lines[end].indent == 0 { break }
            end += 1
        }
        return start..<end
    }
}

private struct RecipeTextEditor {
    private let knownKeys = ["id", "name", "description", "version", "enabled", "variables", "trigger", "cmd", "successMessage", "files", "requirements"]

    func update(existing: String, document: RecipeDocument) -> String {
        var lines = existing.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        let replacements = blocks(for: document)

        for key in knownKeys.reversed() {
            if let range = topLevelRange(for: key, in: lines) {
                if let replacement = replacements[key] { lines.replaceSubrange(range, with: replacement) }
                else { lines.removeSubrange(range) }
            }
        }

        for key in knownKeys where topLevelRange(for: key, in: lines) == nil {
            guard let replacement = replacements[key] else { continue }
            if !lines.isEmpty, lines.last?.isEmpty == false { lines.append("") }
            lines.append(contentsOf: replacement)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    private func blocks(for document: RecipeDocument) -> [String: [String]] {
        let serializer = RecipeSerializer()
        var values: [String: [String]] = [
            "name": ["name: \(serializer.quote(document.name))"],
            "enabled": ["enabled: \(document.enabled ? "true" : "false")"],
            "trigger": ["trigger: \(serializer.quote(document.trigger))"],
            "cmd": commandBlock(document.command)
        ]
        if let id = document.id { values["id"] = ["id: \(serializer.quote(id))"] }
        if !document.description.isEmpty { values["description"] = ["description: \(serializer.quote(document.description))"] }
        if let version = document.version { values["version"] = ["version: \(serializer.quote(version))"] }
        if let message = document.successMessage { values["successMessage"] = ["successMessage: \(serializer.quote(message))"] }
        if !document.supportFiles.isEmpty { values["files"] = ["files:"] + document.supportFiles.map { "  - \(serializer.quote($0))" } }
        if !document.requirements.isEmpty { values["requirements"] = ["requirements:"] + document.requirements.map { "  - \(serializer.quote($0))" } }
        if let variables = document.variables, !variables.isEmpty {
            let varLines = RecipeVariableSerializer().serialize(variables).components(separatedBy: .newlines)
            values["variables"] = varLines
        }
        return values
    }

    private func commandBlock(_ command: String) -> [String] {
        let serializer = RecipeSerializer()
        if command.contains("\n") { return ["cmd:", "  exec: |"] + command.components(separatedBy: .newlines).map { "    \($0)" } }
        return ["cmd:", "  exec: \(serializer.quote(command))"]
    }

    private func topLevelRange(for key: String, in lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: {
            guard $0.indent == 0 else { return false }
            return $0.trimmed == "\(key):" || $0.trimmed.hasPrefix("\(key): ")
        }) else { return nil }
        var end = start + 1
        while end < lines.count {
            let line = lines[end]
            if !line.trimmed.isEmpty && line.indent == 0 { break }
            end += 1
        }
        return start..<end
    }
}

internal extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var indent: Int { prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
    var afterColon: String { guard let colon = firstIndex(of: ":") else { return "" }; return String(self[index(after: colon)...]).trimmed }
    var isBlockMarker: Bool { ["|", ">", "|-", "|+", ">-", ">+"].contains(trimmed) }
    var unquoted: String {
        var value = trimmed
        if value.count >= 2 && ((value.first == "'" && value.last == "'") || (value.first == "\"" && value.last == "\"")) {
            value.removeFirst(); value.removeLast()
            if trimmed.first == "'" { value = value.replacingOccurrences(of: "''", with: "'") }
        }
        return value
    }
}
