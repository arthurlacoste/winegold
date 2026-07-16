import Foundation

public struct RecipeYAMLValidation: Equatable {
    public let document: RecipeDocument?
    public let errors: [String]
    public let warnings: [String]

    public init(document: RecipeDocument?, errors: [String] = [], warnings: [String] = []) {
        self.document = document
        self.errors = errors
        self.warnings = warnings
    }

    public var isValid: Bool { document != nil && errors.isEmpty }
}

public struct RecipeYAMLEditor {
    private let parser = RecipeParser()

    public init() {}

    public func validate(_ text: String) -> RecipeYAMLValidation {
        do {
            let document = try parser.parse(text: text)
            var warnings: [String] = []
            if !document.actions.isEmpty && !document.command.isEmpty {
                warnings.append("Both cmd and actions are present. actions wins.")
            }
            return RecipeYAMLValidation(document: document, warnings: warnings)
        } catch {
            return RecipeYAMLValidation(document: nil, errors: [error.localizedDescription])
        }
    }

    @discardableResult
    public func save(_ text: String, to url: URL, inside root: URL) throws -> RecipeDocument {
        let validation = validate(text)
        guard let document = validation.document, validation.errors.isEmpty else {
            throw RecipeYAMLEditorError.invalid(validation.errors.joined(separator: "\n"))
        }
        try ensureInsideRoot(url, root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let permissions = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try Data(normalized(text).utf8).write(to: temporary, options: .atomic)
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path) }
        _ = try parser.parse(text: String(decoding: Data(contentsOf: temporary), as: UTF8.self))
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: url)
        }
        return document
    }

    public func destination(for document: RecipeDocument, root: URL) -> URL {
        let slug = RecipeFileStore.slug(document.name)
        let folder = root.appendingPathComponent("local").appendingPathComponent(slug)
        var destination = folder.appendingPathComponent("\(slug).wg.yml")
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(slug)-\(index).wg.yml")
            index += 1
        }
        return destination
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .newlines) + "\n"
    }

    private func ensureInsideRoot(_ url: URL, root: URL) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let parentPath = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard parentPath.hasPrefix(rootPath) || parentPath == rootPath else { throw RecipeError.outsideRoot }
    }
}

public enum RecipeYAMLEditorError: LocalizedError, Equatable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message.isEmpty ? "Invalid recipe YAML" : message
        }
    }
}
