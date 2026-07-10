import Foundation

public struct ActionTemplateResolver {
    public init() {}

    public func resolve(template: String, for inputFile: URL) -> String {
        resolvePlaceholders(in: template, for: inputFile)
    }

    public func resolve(argumentsTemplate: [String], for inputFile: URL) -> [String] {
        argumentsTemplate.map { resolvePlaceholders(in: $0, for: inputFile) }
    }

    public func resolve(workingDirectoryTemplate: String?, for inputFile: URL) -> String? {
        guard let template = workingDirectoryTemplate else { return nil }
        return resolvePlaceholders(in: template, for: inputFile)
    }

    public func resolve(outputPathTemplate: String?, for inputFile: URL) -> String? {
        guard let template = outputPathTemplate else { return nil }
        return resolvePlaceholders(in: template, for: inputFile)
    }

    private func resolvePlaceholders(in template: String, for inputFile: URL) -> String {
        let path = inputFile.path
        let filename = inputFile.lastPathComponent
        let basename = filename.contains(".") ? String(filename.prefix(upTo: filename.lastIndex(of: ".") ?? filename.endIndex)) : filename
        let ext = inputFile.pathExtension
        let dotExtension = ext.isEmpty ? "" : ".\(ext)"
        let parent = inputFile.deletingLastPathComponent().path
        let inside = (try? String(contentsOf: inputFile, encoding: .utf8)) ?? ""

        var result = template
        result = result.replacingOccurrences(of: "{input}", with: path)
        result = result.replacingOccurrences(of: "{inputPath}", with: path)
        result = result.replacingOccurrences(of: "{filename}", with: filename)
        result = result.replacingOccurrences(of: "{basename}", with: basename)
        result = result.replacingOccurrences(of: "{extension}", with: ext)
        result = result.replacingOccurrences(of: "{dotExtension}", with: dotExtension)
        result = result.replacingOccurrences(of: "{parent}", with: parent)
        result = result.replacingOccurrences(of: "{inside}", with: inside)
        result = result.replacingOccurrences(of: "{desktop}", with: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
        result = result.replacingOccurrences(of: "{downloads}", with: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        result = result.replacingOccurrences(of: "{timestamp}", with: timestamp)

        return result
    }
}
