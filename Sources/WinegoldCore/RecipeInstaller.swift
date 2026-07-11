import Foundation

public struct RecipeInstallationSummary: Equatable {
    public let destination: URL
    public let recipeNames: [String]
    public let copiedFiles: [String]
    public let warnings: [String]

    public init(destination: URL, recipeNames: [String], copiedFiles: [String], warnings: [String]) {
        self.destination = destination
        self.recipeNames = recipeNames
        self.copiedFiles = copiedFiles
        self.warnings = warnings
    }
}

public enum RecipeInstallationError: LocalizedError {
    case noRecipes
    case unsupportedSource(String)
    case symlink(String)

    public var errorDescription: String? {
        switch self {
        case .noRecipes: return "No .wg.yml recipes were found."
        case .unsupportedSource(let name): return "Unsupported recipe source: \(name)"
        case .symlink(let name): return "Symlinks are not installed: \(name)"
        }
    }
}

public struct RecipeInstaller {
    private let root: URL
    private let parser = RecipeParser()
    private let serializer = RecipeSerializer()
    private let legacyImporter = LegacyActionImporter()

    public init(root: URL) { self.root = root }

    public func inspect(_ source: URL) throws -> RecipeInstallationSummary {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true { throw RecipeInstallationError.symlink(source.lastPathComponent) }
        if values.isDirectory == true { return try inspectDirectory(source) }
        if source.lastPathComponent.lowercased().hasSuffix(".wg.yml") { return try inspectStandaloneRecipe(source) }
        if source.lastPathComponent.lowercased().hasSuffix(".add.yml") { return try inspectLegacyRecipe(source) }
        throw RecipeInstallationError.unsupportedSource(source.lastPathComponent)
    }

    public func install(_ source: URL) throws -> RecipeInstallationSummary {
        let summary = try inspect(source)
        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if values.isDirectory == true {
            try copyDirectory(source, to: summary.destination)
        } else if source.lastPathComponent.lowercased().hasSuffix(".add.yml") {
            try FileManager.default.createDirectory(at: summary.destination, withIntermediateDirectories: true)
            let action = try legacyImporter.importActions(from: source).first
            guard let action else { throw RecipeInstallationError.noRecipes }
            let document = RecipeDocument(
                id: action.id.uuidString,
                name: action.name,
                description: action.description,
                enabled: action.enabled,
                trigger: action.triggerExpression ?? "extension in {\"*\"}",
                command: action.argumentsTemplate.count > 1 ? action.argumentsTemplate[1] : action.argumentsTemplate.joined(separator: " "),
                successMessage: action.successMessage
            )
            let destination = summary.destination.appendingPathComponent("\(RecipeFileStore.slug(action.name)).wg.yml")
            try Data(serializer.serialize(document).utf8).write(to: destination, options: .atomic)
        } else {
            try FileManager.default.createDirectory(at: summary.destination, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: summary.destination.appendingPathComponent(source.lastPathComponent))
            for helper in helperURLs(for: try parser.parse(url: source), source: source) where FileManager.default.fileExists(atPath: helper.path) {
                try FileManager.default.copyItem(at: helper, to: summary.destination.appendingPathComponent(helper.lastPathComponent))
            }
        }
        return summary
    }

    private func inspectDirectory(_ source: URL) throws -> RecipeInstallationSummary {
        let snapshots = try RecipeScanner().scan(root: source)
        guard !snapshots.isEmpty else { throw RecipeInstallationError.noRecipes }
        let records = try snapshots.map { try parser.parse(url: $0.url) }
        let destination = uniqueDestination(named: source.lastPathComponent)
        var files: [String] = []
        let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants])
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { if values.isDirectory == true { enumerator?.skipDescendants() }; continue }
            if values.isDirectory == true {
                let name = url.lastPathComponent.lowercased()
                if name.hasPrefix(".") || RecipeScanner.ignoredDirectories.contains(name) { enumerator?.skipDescendants() }
            } else if values.isRegularFile == true {
                files.append(relativePath(url, from: source))
            }
        }
        return RecipeInstallationSummary(destination: destination, recipeNames: records.map { $0.document.name }, copiedFiles: files.sorted(), warnings: [])
    }

    private func inspectStandaloneRecipe(_ source: URL) throws -> RecipeInstallationSummary {
        let record = try parser.parse(url: source)
        let helpers = helperURLs(for: record, source: source)
        let missing = helpers.filter { !FileManager.default.fileExists(atPath: $0.path) }
        let warnings = missing.map { "Likely missing helper: \($0.lastPathComponent)" }
        return RecipeInstallationSummary(
            destination: uniqueDestination(named: RecipeFileStore.slug(record.document.name)),
            recipeNames: [record.document.name],
            copiedFiles: [source.lastPathComponent] + helpers.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.lastPathComponent),
            warnings: warnings
        )
    }

    private func inspectLegacyRecipe(_ source: URL) throws -> RecipeInstallationSummary {
        guard let action = try legacyImporter.importActions(from: source).first else { throw RecipeInstallationError.noRecipes }
        return RecipeInstallationSummary(destination: uniqueDestination(named: RecipeFileStore.slug(action.name)), recipeNames: [action.name], copiedFiles: ["\(RecipeFileStore.slug(action.name)).wg.yml"], warnings: ["Legacy .add.yml will be converted to .wg.yml."])
    }

    private func helperURLs(for record: RecipeRecord, source: URL) -> [URL] {
        let command = record.document.command
        let pattern = #"(?<![/A-Za-z0-9_.-])([A-Za-z0-9_.-]+\.(?:py|sh|js|mjs|cjs|rb|pl|php|lua|swift))(?![A-Za-z0-9_.-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(command.startIndex..., in: command)
        let names = regex.matches(in: command, range: range).compactMap { match -> String? in
            guard let swiftRange = Range(match.range(at: 1), in: command) else { return nil }
            return String(command[swiftRange])
        }
        return Array(Set(names)).sorted().map { source.deletingLastPathComponent().appendingPathComponent($0) }
    }

    private func copyDirectory(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants])
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { if values.isDirectory == true { enumerator?.skipDescendants() }; continue }
            if values.isDirectory == true {
                let name = url.lastPathComponent.lowercased()
                if name.hasPrefix(".") || RecipeScanner.ignoredDirectories.contains(name) { enumerator?.skipDescendants(); continue }
            }
            let target = destination.appendingPathComponent(relativePath(url, from: source))
            if values.isDirectory == true { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else if values.isRegularFile == true {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
    }

    private func uniqueDestination(named name: String) -> URL {
        let base = root.appendingPathComponent(RecipeFileStore.slug(name))
        var destination = base
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = root.appendingPathComponent("\(base.lastPathComponent)-\(index)")
            index += 1
        }
        return destination
    }

    private func relativePath(_ url: URL, from root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
