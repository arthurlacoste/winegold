import Foundation

public struct LegacyActionImporter {
    public init() {}

    public func importActions(from url: URL) throws -> [Action] {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return try JSONDecoder().decode([Action].self, from: data)
        case "yml", "yaml":
            let text = String(data: data, encoding: .utf8) ?? ""
            return [try importLegacyYAML(text, sourceName: url.lastPathComponent)]
        default:
            throw ImportError.unsupportedFormat(ext)
        }
    }

    public func importLegacyYAML(_ text: String, sourceName: String = "script.add.yml") throws -> Action {
        let name = scalarValue(for: "name", in: text)?.trimmedUnquoted
            ?? sourceName.replacingOccurrences(of: ".add.yml", with: "").replacingOccurrences(of: ".yml", with: "")
        let extensions = listValues(afterPath: ["trigger", "fileExtension"], in: text)
            .map { $0.trimmedUnquoted.lowercased() }
            .filter { !$0.isEmpty }
        guard !extensions.isEmpty else { throw ImportError.missingField("trigger.fileExtension") }

        guard let command = scalarValue(forPath: ["cmd", "exec"], in: text)?.trimmedUnquoted, !command.isEmpty else {
            throw ImportError.missingField("cmd.exec")
        }

        let translatedCommand = translateLegacyPlaceholders(command)
        return Action(
            name: name,
            description: "Imported legacy .add.yml script",
            iconName: "terminal",
            enabled: true,
            acceptedExtensions: extensions,
            executablePath: "/bin/zsh",
            argumentsTemplate: ["-lc", translatedCommand],
            workingDirectoryTemplate: nil,
            outputPathTemplate: nil,
            requiresConfirmation: false,
            timeoutSeconds: 120
        )
    }

    private func translateLegacyPlaceholders(_ command: String) -> String {
        var result = command
        let replacements = [
            "{{file}}": "{input}",
            "{{input}}": "{input}",
            "{{dir}}": "{parent}",
            "{{parent}}": "{parent}",
            "{{name}}": "{filename}",
            "{{filename}}": "{filename}",
            "{{namebase}}": "{basename}",
            "{{basename}}": "{basename}",
            "{{ext}}": "{dotExtension}",
            "{{extension}}": "{extension}",
            "{{inside}}": "{inside}",
            "{{desktop}}": "{desktop}",
            "{{downloads}}": "{downloads}",
            "{{timestamp}}": "{timestamp}"
        ]
        for (legacy, current) in replacements {
            result = result.replacingOccurrences(of: legacy, with: current)
        }
        return result
    }

    private func scalarValue(for key: String, in text: String) -> String? {
        let prefix = "\(key):"
        return text.lines.first { $0.trimmed.hasPrefix(prefix) }?.valueAfterColon
    }

    private func scalarValue(forPath path: [String], in text: String) -> String? {
        guard path.count == 2 else { return nil }
        let section = path[0]
        let key = path[1]
        var inSection = false
        for line in text.lines {
            let trimmed = line.trimmed
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if !line.hasIndent && trimmed == "\(section):" {
                inSection = true
                continue
            }
            if !line.hasIndent && !trimmed.hasPrefix("-") {
                inSection = false
            }
            if inSection && trimmed.hasPrefix("\(key):") {
                return trimmed.valueAfterColon
            }
        }
        return nil
    }

    private func listValues(afterPath path: [String], in text: String) -> [String] {
        guard path.count == 2 else { return [] }
        let section = path[0]
        let key = path[1]
        var inSection = false
        var inList = false
        var values: [String] = []

        for line in text.lines {
            let trimmed = line.trimmed
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if !line.hasIndent && trimmed == "\(section):" {
                inSection = true
                inList = false
                continue
            }

            if !line.hasIndent && !trimmed.hasPrefix("-") {
                inSection = false
                inList = false
            }

            guard inSection else { continue }
            if trimmed.hasPrefix("\(key):") {
                inList = true
                let inline = trimmed.valueAfterColon.trimmed
                if !inline.isEmpty { values.append(inline) }
                continue
            }

            if inList {
                if trimmed.hasPrefix("-") {
                    values.append(String(trimmed.dropFirst()).trimmed)
                } else if !line.hasIndent {
                    inList = false
                }
            }
        }

        return values
    }
}

public enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case missingField(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Format non supporté : \(ext)"
        case .missingField(let field): return "Champ manquant : \(field)"
        }
    }
}

private extension String {
    var lines: [String] { components(separatedBy: .newlines) }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasIndent: Bool { hasPrefix(" ") || hasPrefix("\t") }
    var valueAfterColon: String {
        guard let idx = firstIndex(of: ":") else { return "" }
        return String(self[index(after: idx)...]).trimmed
    }
    var trimmedUnquoted: String {
        var value = trimmed
        if (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
