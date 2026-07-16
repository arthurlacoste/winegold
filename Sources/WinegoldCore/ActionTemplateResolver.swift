import Foundation

public struct ActionTemplateResolver {
    public init() {}

    public func resolve(template: String, for inputFile: URL) -> String {
        resolve(template: template, for: DraggedItem(executionURL: inputFile))
    }

    public func resolve(template: String, for item: DraggedItem) -> String { resolvePlaceholders(in: template, for: item) }

    public func resolve(argumentsTemplate: [String], for inputFile: URL) -> [String] {
        let item = DraggedItem(executionURL: inputFile)
        return argumentsTemplate.map { resolvePlaceholders(in: $0, for: item) }
    }

    public func resolve(workingDirectoryTemplate: String?, for inputFile: URL) -> String? {
        guard let template = workingDirectoryTemplate else { return nil }
        return resolvePlaceholders(in: template, for: DraggedItem(executionURL: inputFile))
    }

    public func resolve(outputPathTemplate: String?, for inputFile: URL) -> String? {
        guard let template = outputPathTemplate else { return nil }
        return resolvePlaceholders(in: template, for: DraggedItem(executionURL: inputFile))
    }

    private func resolvePlaceholders(in template: String, for item: DraggedItem) -> String {
        let values = item.values(includeInside: template.contains("{inside}"))
        var result = template
        for (field, value) in values {
            let text: String
            switch value { case let .string(v): text = v; case let .number(v): text = String(Int(v)); case let .bool(v): text = String(v); case let .collection(v): text = v.joined(separator: ",") }
            result = result.replacingOccurrences(of: "{\(field)}", with: text)
        }
        result = result.replacingOccurrences(of: "{inputPath}", with: item.executionURL.path)
        return result
    }
}
