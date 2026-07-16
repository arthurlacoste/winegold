import Foundation

public enum RecipeInputRequirement: Equatable {
    case none
    case files(allowedExtensions: [String])
    case directories
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
        guard let source = action.triggerExpression?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty,
              let expression = try? TriggerParser().parse(source) else {
            let extensions = normalized(action.acceptedExtensions)
            return extensions.isEmpty ? .none : .files(allowedExtensions: extensions.filter { $0 != "*" })
        }
        return requirement(from: expression)
    }

    private func requirement(from expression: TriggerExpression) -> RecipeInputRequirement {
        switch expression {
        case let .condition(field, op, literal):
            if field == "isDirectory" || (field == "kind" && string(literal) == "directory") { return .directories }
            if field == "isFile" || (field == "kind" && string(literal) == "file") { return .files(allowedExtensions: []) }
            if field == "extension" {
                if op == .in, case let .collection(values) = literal { return .files(allowedExtensions: normalized(values).filter { $0 != "*" }.sorted()) }
                if op == .equals, let value = string(literal) { return .files(allowedExtensions: normalized([value])) }
            }
            return .items
        case let .and(children):
            let requirements = children.map(requirement(from:))
            if requirements.contains(.directories) { return .directories }
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
        if items.isEmpty {
            return requirement == .none ? .valid : .missingInput(requirement)
        }
        guard requirement != .none else {
            return .incompatible([RecipeValidationIssue("This recipe does not accept input.")])
        }
        if ActionMatcher().matches(action, forItems: items) { return .valid }
        return .incompatible([RecipeValidationIssue(incompatibilityMessage(for: requirement))])
    }

    private func incompatibilityMessage(for requirement: RecipeInputRequirement) -> String {
        switch requirement {
        case let .files(extensions) where !extensions.isEmpty:
            return "This recipe expects: " + extensions.map { ".\($0)" }.joined(separator: ", ")
        case .files: return "This recipe expects files."
        case .directories: return "This recipe expects a folder."
        case .items, .unresolved: return "The selected input does not match this recipe trigger."
        case .none: return "This recipe does not accept input."
        }
    }
}
