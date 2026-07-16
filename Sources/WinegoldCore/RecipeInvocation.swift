import Foundation

public enum RecipeInputRequirement: Equatable {
    case none
    case files(allowedExtensions: [String])
    case directories
    case url
    case text
    case items
    case unresolved
}

public struct RecipeValidationIssue: Equatable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum RecipeInvocationValidationResult: Equatable {
    case valid
    case missingInput(RecipeInputRequirement)
    case incompatible([RecipeValidationIssue])
}

public struct RecipeInputRequirementResolver {
    public init() {}

    public func requirement(for action: Action) -> RecipeInputRequirement {
        if action.minimumInputCount == 0,
           action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           action.acceptedExtensions.isEmpty {
            return .none
        }
        guard let source = action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty,
              let expression = try? TriggerParser().parse(source) else {
            let extensions = normalized(action.acceptedExtensions)
            return extensions.isEmpty ? .items : .files(allowedExtensions: extensions.filter { $0 != "*" })
        }
        return requirement(from: expression)
    }

    private func requirement(from expression: TriggerExpression) -> RecipeInputRequirement {
        switch expression {
        case let .condition(field, op, literal):
            if field == "isDirectory" || (field == "kind" && string(literal) == "directory") { return .directories }
            if field == "isFile" || (field == "kind" && string(literal) == "file") { return .files(allowedExtensions: []) }
            if field == "isURL" || field == "url" || field == "host" || field == "scheme" || (field == "kind" && string(literal) == "url") { return .url }
            if field == "isText" || field == "text" || (field == "kind" && string(literal) == "text") { return .text }
            if field == "extension" {
                if op == .in, case let .collection(values) = literal { return .files(allowedExtensions: normalized(values).filter { $0 != "*" }.sorted()) }
                if op == .equals, let value = string(literal) { return .files(allowedExtensions: normalized([value])) }
            }
            return .items
        case let .and(children):
            let requirements = children.map(requirement(from:))
            if requirements.contains(.directories) { return .directories }
            if requirements.contains(.url) { return .url }
            if requirements.contains(.text) { return .text }
            let extensions = requirements.compactMap { requirement -> [String]? in
                if case let .files(values) = requirement { return values }
                return nil
            }.flatMap { $0 }
            if requirements.contains(where: { if case .files = $0 { return true }; return false }) {
                return .files(allowedExtensions: Array(Set(extensions)).sorted())
            }
            return .items
        case .or, .not:
            return .unresolved
        }
    }

    private func string(_ literal: TriggerLiteral?) -> String? {
        guard case let .string(value) = literal else { return nil }
        return value.lowercased()
    }

    private func normalized(_ values: [String]) -> [String] {
        values.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }.filter { !$0.isEmpty }
    }
}

public struct RecipeInvocationValidator {
    public init() {}

    public func validate(_ action: Action, items: [DraggedItem]) -> RecipeInvocationValidationResult {
        let requirement = RecipeInputRequirementResolver().requirement(for: action)
        if items.count < action.minimumInputCount {
            return .missingInput(requirement)
        }
        if let maximum = action.maximumInputCount, items.count > maximum {
            return .incompatible([RecipeValidationIssue(countMessage(minimum: action.minimumInputCount, maximum: maximum))])
        }
        if items.isEmpty { return requirement == .none ? .valid : .missingInput(requirement) }
        guard requirement != .none else {
            return .incompatible([RecipeValidationIssue("This recipe does not accept input.")])
        }
        if ActionMatcher().matches(action, forItems: items) { return .valid }
        return .incompatible([RecipeValidationIssue(incompatibilityMessage(for: requirement))])
    }

    private func countMessage(minimum: Int, maximum: Int) -> String {
        if minimum == maximum { return "This recipe expects exactly \(minimum) item\(minimum == 1 ? "" : "s")." }
        return "This recipe accepts between \(minimum) and \(maximum) items."
    }

    private func incompatibilityMessage(for requirement: RecipeInputRequirement) -> String {
        switch requirement {
        case let .files(extensions) where !extensions.isEmpty:
            return "This recipe expects: " + extensions.map { ".\($0)" }.joined(separator: ", ")
        case .files: return "This recipe expects files."
        case .directories: return "This recipe expects a folder."
        case .url: return "This recipe expects a URL."
        case .text: return "This recipe expects text."
        case .items, .unresolved: return "The selected input does not match this recipe trigger."
        case .none: return "This recipe does not accept input."
        }
    }
}

public struct RecipeTemplateInputValidator {
    private static let inputPlaceholders = ["{input}", "{inputPath}", "{parent}", "{filename}", "{basename}", "{extension}", "{dotExtension}", "{inside}"]

    public init() {}

    public func missingInputPlaceholder(in action: Action) -> String? {
        guard action.minimumInputCount == 0 else { return nil }
        let templates = action.argumentsTemplate + [action.workingDirectoryTemplate, action.outputPathTemplate, action.successMessage].compactMap { $0 }
        return Self.inputPlaceholders.first { placeholder in templates.contains { $0.contains(placeholder) } }
    }
}
