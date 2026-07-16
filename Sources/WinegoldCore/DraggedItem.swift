import Foundation
import UniformTypeIdentifiers

public struct DraggedItem: Equatable {
    public enum Kind: String, Codable { case file, directory, url, text }

    public static let maximumContentBytes = 1_048_576

    public let executionURL: URL
    public let kind: Kind
    public let rawURL: String?
    public let rawText: String?

    public init(executionURL: URL, kind: Kind? = nil, rawURL: String? = nil, rawText: String? = nil) {
        self.executionURL = executionURL
        let inferred = kind ?? Self.inferKind(for: executionURL)
        self.kind = inferred
        self.rawURL = rawURL ?? (inferred == .url ? Self.smallUTF8Contents(of: executionURL) : nil)
        self.rawText = rawText ?? (inferred == .text ? Self.smallUTF8Contents(of: executionURL) : nil)
    }

    public var values: [String: TriggerValue] { values(includeInside: true) }

    public func values(includeInside: Bool) -> [String: TriggerValue] {
        var result: [String: TriggerValue] = [
            "kind": .string(kind.rawValue),
            "isFile": .bool(kind == .file),
            "isDirectory": .bool(kind == .directory),
            "isURL": .bool(kind == .url),
            "isText": .bool(kind == .text),
            "input": .string(input),
            "timestamp": .string(Self.timestamp())
        ]
        result["desktop"] = .string(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
        result["downloads"] = .string(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)

        if kind == .url, let rawURL, let components = URLComponents(string: rawURL) {
            result["url"] = .string(rawURL)
            result["scheme"] = components.scheme.map(TriggerValue.string)
            result["host"] = components.host.map(TriggerValue.string)
            result["urlPath"] = .string(components.path)
            result["query"] = components.query.map(TriggerValue.string)
            result["fragment"] = components.fragment.map(TriggerValue.string)
        } else if kind == .text, let rawText {
            result["text"] = .string(rawText)
        } else if kind == .file || kind == .directory {
            addFileValues(to: &result, includeInside: includeInside)
        }
        return result
    }

    public var input: String { kind == .url ? (rawURL ?? executionURL.path) : kind == .text ? (rawText ?? executionURL.path) : executionURL.path }

    private func addFileValues(to result: inout [String: TriggerValue], includeInside: Bool) {
        let filename = executionURL.lastPathComponent
        let ext = executionURL.pathExtension
        let basename = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        let parent = executionURL.deletingLastPathComponent()
        result["parent"] = .string(parent.path)
        result["parentName"] = .string(parent.lastPathComponent)
        result["filename"] = .string(filename)
        result["basename"] = .string(basename)
        result["extension"] = .string(ext)
        result["dotExtension"] = .string(ext.isEmpty ? "" : ".\(ext)")

        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentTypeKey, .tagNamesKey]
        var shouldReadTextContents = false
        if let values = try? executionURL.resourceValues(forKeys: keys) {
            if let size = values.fileSize { result["size"] = .number(Double(size)) }
            if let type = values.contentType {
                result["uti"] = .string(type.identifier)
                if let mime = type.preferredMIMEType { result["mimeType"] = .string(mime) }
                shouldReadTextContents = type.conforms(to: .text)
            }
            if let tags = values.tagNames { result["finderTags"] = .collection(tags) }
        }
        if includeInside, kind == .file, shouldReadTextContents,
           let inside = Self.smallUTF8Contents(of: executionURL) {
            result["inside"] = .string(inside)
        }
    }

    private static func inferKind(for url: URL) -> Kind {
        let name = url.lastPathComponent
        if name.hasPrefix("dragged-url-") && url.pathExtension == "url" { return .url }
        if name.hasPrefix("dragged-text-") && url.pathExtension == "txt" { return .text }
        if url.hasDirectoryPath || ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) { return .directory }
        return .file
    }

    private static func smallUTF8Contents(of url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumContentBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), data.count <= maximumContentBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}
