import Foundation

public struct RecipeVariable: Equatable, Hashable {
    public var name: String
    public var label: String
    public var secret: Bool
    public var required: Bool
    public var defaultValue: String?
    public var key: String?

    public init(
        name: String,
        label: String? = nil,
        secret: Bool = false,
        required: Bool = false,
        defaultValue: String? = nil,
        key: String? = nil
    ) {
        self.name = name
        self.label = label ?? Self.derivedLabel(from: name)
        self.secret = secret
        self.required = required
        self.defaultValue = defaultValue
        self.key = key
    }

    public static func derivedLabel(from name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { part in
                let s = String(part)
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

public enum RecipeVariableError: LocalizedError, Equatable {
    case invalidVariableYAML(String)
    case invalidBoolean(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVariableYAML(let msg): return "Invalid variable definition: \(msg)"
        case .invalidBoolean(let value): return "Invalid boolean: \(value)"
        }
    }
}

public struct RecipeVariableParser {
    public init() {}

    public func parseVariables(lines: [String]) throws -> [RecipeVariable] {
        guard let start = lines.firstIndex(where: { $0.indent == 0 && $0.trimmed == "variables:" }) else { return [] }
        var variables: [RecipeVariable] = []
        var currentName: String?
        var currentLabel: String?
        var currentSecret = false
        var currentRequired = false
        var currentDefault: String?
        var currentKey: String?
        var inVariable = false

        func flush() {
            if let name = currentName {
                variables.append(RecipeVariable(
                    name: name,
                    label: currentLabel,
                    secret: currentSecret,
                    required: currentRequired,
                    defaultValue: currentDefault,
                    key: currentKey
                ))
            }
            currentName = nil; currentLabel = nil; currentSecret = false; currentRequired = false; currentDefault = nil; currentKey = nil; inVariable = false
        }

        for raw in lines.dropFirst(start + 1) {
            if !raw.trimmed.isEmpty && raw.indent == 0 { break }
            if raw.indent == 2 && raw.trimmed.hasSuffix(":") {
                flush()
                currentName = String(raw.trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                inVariable = true
                continue
            }
            guard inVariable else { continue }
            let key = raw.trimmed
            if key.hasPrefix("label: ") {
                currentLabel = String(key.dropFirst(7)).unquoted
            } else if key == "label:" {
                currentLabel = ""
            } else if key.hasPrefix("secret: ") {
                currentSecret = try parseBool(String(key.dropFirst(8)))
            } else if key == "secret:" {
                currentSecret = false
            } else if key.hasPrefix("required: ") {
                currentRequired = try parseBool(String(key.dropFirst(10)))
            } else if key == "required:" {
                currentRequired = false
            } else if key.hasPrefix("default: ") {
                currentDefault = String(key.dropFirst(9)).unquoted
            } else if key == "default:" {
                currentDefault = ""
            } else if key.hasPrefix("key: ") {
                currentKey = String(key.dropFirst(5)).unquoted
            } else if key == "key:" {
                currentKey = ""
            }
        }
        flush()
        return variables
    }

    private func parseBool(_ value: String) throws -> Bool {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: throw RecipeVariableError.invalidBoolean(value)
        }
    }
}

public struct RecipeVariableSerializer {
    public init() {}

    public func serialize(_ variables: [RecipeVariable]) -> String {
        guard !variables.isEmpty else { return "" }
        var lines = ["variables:"]
        for v in variables {
            lines.append("  \(v.name):")
            lines.append("    label: '\(v.label.replacingOccurrences(of: "'", with: "''"))'")
            if v.secret { lines.append("    secret: true") }
            if v.required { lines.append("    required: true") }
            if let d = v.defaultValue { lines.append("    default: '\(d.replacingOccurrences(of: "'", with: "''"))'") }
            if let k = v.key { lines.append("    key: '\(k.replacingOccurrences(of: "'", with: "''"))'") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum RecipeSetupStatus: Equatable {
    case ready
    case needsSetup(missing: [RecipeVariable])
}

public struct RecipeVariableResolver {
    private let variableStore: RecipeVariableStoreProtocol
    private let keychainStore: KeychainSecretStoreProtocol

    public init(variableStore: RecipeVariableStoreProtocol, keychainStore: KeychainSecretStoreProtocol) {
        self.variableStore = variableStore
        self.keychainStore = keychainStore
    }

    public func resolve(variables: [RecipeVariable], externalID: String, appEnvironment: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for variable in variables {
            if let value = resolveOne(variable, externalID: externalID, appEnvironment: appEnvironment) {
                result[variable.name] = value
            }
        }
        return result
    }

    public func setupStatus(variables: [RecipeVariable], externalID: String, appEnvironment: [String: String]) -> RecipeSetupStatus {
        var missing: [RecipeVariable] = []
        for variable in variables where variable.required {
            if resolveOne(variable, externalID: externalID, appEnvironment: appEnvironment) == nil {
                missing.append(variable)
            }
        }
        if missing.isEmpty { return .ready }
        return .needsSetup(missing: missing)
    }

    public func secretValues(variables: [RecipeVariable], externalID: String, appEnvironment: [String: String]) -> [String] {
        variables.filter(\.secret).compactMap { variable in
            resolveOne(variable, externalID: externalID, appEnvironment: appEnvironment)
        }
    }

    private func resolveOne(_ variable: RecipeVariable, externalID: String, appEnvironment: [String: String]) -> String? {
        if variable.secret {
            let privateKey = Self.privateSecretStorageKey(variable: variable.name, externalID: externalID)
            if let privateValue = keychainStore.read(key: privateKey), !privateValue.isEmpty {
                return privateValue
            }
            if let sharedKey = variable.key,
               variableStore.consentStatus(key: sharedKey, externalID: externalID) {
                let storageKey = Self.sharedSecretStorageKey(sharedKey)
                if let sharedValue = keychainStore.read(key: storageKey), !sharedValue.isEmpty {
                    return sharedValue
                }
            } else if variable.key == nil,
                      let privateValue = keychainStore.read(key: privateKey), !privateValue.isEmpty {
                return privateValue
            }
            if let envValue = appEnvironment[variable.name], !envValue.isEmpty {
                return envValue
            }
            return nil
        } else {
            if let override = variableStore.readOverride(externalID: externalID, variableName: variable.name) {
                return override
            }
            if let envValue = appEnvironment[variable.name], !envValue.isEmpty {
                return envValue
            }
            return variable.defaultValue
        }
    }

    public static func privateSecretStorageKey(variable: String, externalID: String) -> String {
        "winegold.recipe.\(externalID).\(variable)"
    }

    public static func sharedSecretStorageKey(_ key: String) -> String {
        "winegold.shared.\(key)"
    }

    public static func secretStorageKey(variable: String, externalID: String, key: String? = nil) -> String {
        key.map(sharedSecretStorageKey) ?? privateSecretStorageKey(variable: variable, externalID: externalID)
    }
}

public struct SecretRedactor {
    public init() {}

    public func redact(_ text: String, secretValues: [String]) -> String {
        var result = text
        for value in secretValues.sorted(by: { $0.count > $1.count }) {
            guard !value.isEmpty, value.count >= 4 else { continue }
            result = result.replacingOccurrences(of: value, with: String(repeating: "*", count: min(value.count, 8)))
        }
        return result
    }

    public func redactCommand(_ request: CommandExecutionRequest, secretValues: [String]) -> CommandExecutionRequest {
        var copy = request
        copy.arguments = request.arguments.map { redact($0, secretValues: secretValues) }
        return copy
    }
}

public protocol RecipeVariableStoreProtocol {
    func readOverride(externalID: String, variableName: String) -> String?
    func writeOverride(externalID: String, variableName: String, value: String)
    func deleteOverride(externalID: String, variableName: String)
    func consentStatus(key: String, externalID: String) -> Bool
    func grantConsent(key: String, externalID: String)
    func revokeConsent(key: String, externalID: String)
    func needsConsentWarning(key: String, newExternalID: String) -> Bool
}

public protocol KeychainSecretStoreProtocol {
    func read(key: String) -> String?
    func write(key: String, value: String)
    func delete(key: String)
    func listKeys() -> [String]
}

public struct RecipeVariableExportFilter {
    public init() {}

    public func filterForExport(_ document: RecipeDocument) -> RecipeDocument {
        document
    }
}
