import Foundation

public struct RecipeSetupRequirements: Equatable {
    public let missingCommands: [String]
    public let missingVariables: [RecipeVariable]

    public init(missingCommands: [String] = [], missingVariables: [RecipeVariable] = []) {
        self.missingCommands = missingCommands
        self.missingVariables = missingVariables
    }

    public var isReady: Bool { missingCommands.isEmpty && missingVariables.isEmpty }

    public var actionLabel: String {
        if missingCommands.count == 1, missingVariables.isEmpty {
            return "Install \(missingCommands[0])"
        }
        if missingCommands.isEmpty, !missingVariables.isEmpty {
            return missingVariables.count == 1 && missingVariables[0].secret
                ? "Configure secret"
                : "Configure variables"
        }
        return "Set up"
    }

    public var summary: String {
        var parts: [String] = []
        if !missingCommands.isEmpty {
            parts.append("Missing: \(missingCommands.joined(separator: ", "))")
        }
        if !missingVariables.isEmpty {
            parts.append("Configure: \(missingVariables.map(\.name).joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }
}
