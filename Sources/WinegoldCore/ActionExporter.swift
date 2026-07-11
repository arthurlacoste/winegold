import Foundation

public struct ActionExporter {
    public init() {}

    public func exportJSON(_ actions: [Action]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(actions)
    }

    public func exportRecipeDocument(_ document: RecipeDocument) -> RecipeDocument {
        RecipeVariableExportFilter().filterForExport(document)
    }
}
