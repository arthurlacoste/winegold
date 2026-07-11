import Foundation
import CryptoKit

public struct RemoteRecipeResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol RemoteRecipeFetching: Sendable {
    func fetch(_ url: URL) async throws -> RemoteRecipeResponse
}

public struct URLSessionRecipeFetcher: RemoteRecipeFetching {
    public init() {}
    public func fetch(_ url: URL) async throws -> RemoteRecipeResponse {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw RemoteRecipeError.invalidResponse }
        return RemoteRecipeResponse(data: data, statusCode: http.statusCode)
    }
}

public enum RemoteRecipeError: LocalizedError, Equatable {
    case httpsRequired
    case invalidFilename
    case invalidResponse
    case httpStatus(Int, String)
    case missingPublishedID
    case missingPublishedVersion
    case unsafeSupportPath(String)
    case crossOrigin(String)
    case missingSupportFile(String)
    case destinationExists
    case modified

    public var errorDescription: String? {
        switch self {
        case .httpsRequired: return "Remote recipes must use HTTPS."
        case .invalidFilename: return "Remote recipe URL must end in .wg.yml."
        case .invalidResponse: return "The recipe server returned an invalid response."
        case .httpStatus(let code, let path): return "Recipe download failed (HTTP \(code)): \(path)"
        case .missingPublishedID: return "Published recipes require a stable id."
        case .missingPublishedVersion: return "Published recipes require a version."
        case .unsafeSupportPath(let path): return "Support file must be a safe relative path: \(path)"
        case .crossOrigin(let path): return "Support file escaped the recipe origin: \(path)"
        case .missingSupportFile(let path): return "Missing required support file: \(path)"
        case .destinationExists: return "A recipe with this ID is already installed."
        case .modified: return "The installed recipe has local modifications."
        }
    }
}

public struct RemoteRecipeInspection: Equatable {
    public let document: RecipeDocument
    public let sourceURL: URL
    public let files: [String]
    public let missingCommands: [String]
    public let readmeAvailable: Bool
}

public struct RecipeProvenance: Equatable {
    public let recipeID: String
    public let sourceURL: String
    public let installedVersion: String
    public let installedAt: String
    public let yamlHash: String
    public let fileHashes: [String: String]
    public let lastUpdateCheck: String?
    public let latestKnownVersion: String?
}

public enum RecipeUpdateConflictChoice {
    case keepCurrent
    case replace
    case duplicateCurrent
}

public struct RecipeUpdateResult: Equatable {
    public let updated: Bool
    public let conflict: Bool
    public let diff: String?
    public let destination: URL
}

public struct RecipeProvenanceStore {
    private let db: Database
    public init(db: Database) { self.db = db }

    public func save(_ provenance: RecipeProvenance) throws {
        let encoded = try JSONEncoder().encode(provenance.fileHashes)
        let stmt = try db.prepare("""
            INSERT INTO recipe_provenance
            (recipe_id, source_url, installed_version, installed_at, yaml_hash, file_hashes, last_update_check, latest_known_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(recipe_id) DO UPDATE SET source_url=excluded.source_url,
            installed_version=excluded.installed_version, installed_at=excluded.installed_at,
            yaml_hash=excluded.yaml_hash, file_hashes=excluded.file_hashes,
            last_update_check=excluded.last_update_check, latest_known_version=excluded.latest_known_version
        """)
        [provenance.recipeID, provenance.sourceURL, provenance.installedVersion, provenance.installedAt, provenance.yamlHash, String(decoding: encoded, as: UTF8.self)].enumerated().forEach { stmt.bindText($0.element, at: Int32($0.offset + 1)) }
        if let value = provenance.lastUpdateCheck { stmt.bindText(value, at: 7) } else { stmt.bindNull(at: 7) }
        if let value = provenance.latestKnownVersion { stmt.bindText(value, at: 8) } else { stmt.bindNull(at: 8) }
        _ = stmt.step()
    }

    public func load(recipeID: String) throws -> RecipeProvenance? {
        let stmt = try db.prepare("SELECT source_url, installed_version, installed_at, yaml_hash, file_hashes, last_update_check, latest_known_version FROM recipe_provenance WHERE recipe_id=?")
        stmt.bindText(recipeID, at: 1)
        guard stmt.step() else { return nil }
        let hashes = (try? JSONDecoder().decode([String: String].self, from: Data(stmt.columnText(at: 4).utf8))) ?? [:]
        return RecipeProvenance(recipeID: recipeID, sourceURL: stmt.columnText(at: 0), installedVersion: stmt.columnText(at: 1), installedAt: stmt.columnText(at: 2), yamlHash: stmt.columnText(at: 3), fileHashes: hashes, lastUpdateCheck: stmt.columnIsNull(at: 5) ? nil : stmt.columnText(at: 5), latestKnownVersion: stmt.columnIsNull(at: 6) ? nil : stmt.columnText(at: 6))
    }
}

public struct RecipeRequirementChecker {
    public init() {}

    public func missingCommands(_ commands: [String]) -> [String] {
        commands.filter { command in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["sh", "-lc", "command -v \"$1\" >/dev/null 2>&1", "winegold", command]
            try? process.run()
            process.waitUntilExit()
            return process.terminationStatus != 0
        }
    }
}

public final class RemoteRecipeInstaller {
    private let root: URL
    private let db: Database
    private let fetcher: RemoteRecipeFetching
    private let parser = RecipeParser()
    private let provenanceStore: RecipeProvenanceStore
    private let fileManager: FileManager

    public init(root: URL, db: Database, fetcher: RemoteRecipeFetching = URLSessionRecipeFetcher(), fileManager: FileManager = .default) {
        self.root = root
        self.db = db
        self.fetcher = fetcher
        self.fileManager = fileManager
        self.provenanceStore = RecipeProvenanceStore(db: db)
    }

    public func inspect(url: URL) async throws -> RemoteRecipeInspection {
        let package = try await download(url: url)
        return RemoteRecipeInspection(document: package.document, sourceURL: url, files: package.files.keys.sorted(), missingCommands: RecipeRequirementChecker().missingCommands(package.document.requirements), readmeAvailable: package.readme != nil)
    }

    @discardableResult
    public func install(url: URL) async throws -> URL {
        let package = try await download(url: url)
        guard let id = package.document.id else { throw RemoteRecipeError.missingPublishedID }
        guard let version = package.document.version, !version.isEmpty else { throw RemoteRecipeError.missingPublishedVersion }
        let destination = root.appendingPathComponent(RecipeFileStore.slug(id), isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else { throw RemoteRecipeError.destinationExists }
        let staged = try stage(package: package)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.moveItem(at: staged, to: destination)
        try saveProvenance(package: package, destination: destination, version: version)
        return destination
    }

    public func update(recipeID: String, choice: RecipeUpdateConflictChoice = .keepCurrent) async throws -> RecipeUpdateResult {
        guard let provenance = try provenanceStore.load(recipeID: recipeID), let source = URL(string: provenance.sourceURL) else { throw RemoteRecipeError.invalidResponse }
        let destination = root.appendingPathComponent(RecipeFileStore.slug(recipeID), isDirectory: true)
        let modified = localModificationDiff(destination: destination, provenance: provenance)
        if let diff = modified, choice == .keepCurrent {
            return RecipeUpdateResult(updated: false, conflict: true, diff: diff, destination: destination)
        }
        let package = try await download(url: source)
        guard let version = package.document.version else { throw RemoteRecipeError.missingPublishedVersion }
        let oldEnabled = try currentEnabled(in: destination)
        let staged = try stage(package: package, enabledOverride: oldEnabled)
        if modified != nil, choice == .duplicateCurrent {
            let duplicate = uniqueDuplicateURL(for: destination)
            try fileManager.copyItem(at: destination, to: duplicate)
        }
        let backup = root.appendingPathComponent(".update-\(UUID().uuidString)")
        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: staged, to: destination)
            try fileManager.removeItem(at: backup)
            try saveProvenance(package: package, destination: destination, version: version)
            return RecipeUpdateResult(updated: true, conflict: modified != nil, diff: modified, destination: destination)
        } catch {
            try? fileManager.moveItem(at: backup, to: destination)
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    private struct DownloadedPackage {
        var document: RecipeDocument
        let recipeFilename: String
        let yaml: Data
        let files: [String: Data]
        let readme: Data?
        let sourceURL: URL
    }

    private func download(url: URL) async throws -> DownloadedPackage {
        guard url.scheme?.lowercased() == "https" else { throw RemoteRecipeError.httpsRequired }
        guard url.lastPathComponent.lowercased().hasSuffix(".wg.yml") else { throw RemoteRecipeError.invalidFilename }
        let response = try await fetcher.fetch(url)
        guard response.statusCode == 200 else { throw RemoteRecipeError.httpStatus(response.statusCode, url.lastPathComponent) }
        let text = String(decoding: response.data, as: UTF8.self)
        let parsed = try parser.parse(text: text)
        guard parsed.id != nil else { throw RemoteRecipeError.missingPublishedID }
        guard parsed.version != nil else { throw RemoteRecipeError.missingPublishedVersion }
        var files: [String: Data] = [:]
        for relative in parsed.supportFiles {
            let fileURL = try resolvedSupportURL(relative, recipeURL: url)
            let result = try await fetcher.fetch(fileURL)
            guard result.statusCode == 200 else { throw RemoteRecipeError.missingSupportFile(relative) }
            files[relative] = result.data
        }
        let readmeURL = url.deletingLastPathComponent().appendingPathComponent("README.md")
        let readmeResult = try? await fetcher.fetch(readmeURL)
        let readme = readmeResult?.statusCode == 200 ? readmeResult?.data : nil
        return DownloadedPackage(document: parsed, recipeFilename: url.lastPathComponent, yaml: response.data, files: files, readme: readme, sourceURL: url)
    }

    private func resolvedSupportURL(_ relative: String, recipeURL: URL) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { throw RemoteRecipeError.unsafeSupportPath(relative) }
        let base = recipeURL.deletingLastPathComponent()
        guard let resolved = URL(string: relative, relativeTo: base)?.absoluteURL.standardized else { throw RemoteRecipeError.unsafeSupportPath(relative) }
        guard resolved.scheme == recipeURL.scheme, resolved.host == recipeURL.host, resolved.port == recipeURL.port else { throw RemoteRecipeError.crossOrigin(relative) }
        let basePath = base.standardized.path.hasSuffix("/") ? base.standardized.path : base.standardized.path + "/"
        guard resolved.path.hasPrefix(basePath) else { throw RemoteRecipeError.unsafeSupportPath(relative) }
        return resolved
    }

    private func stage(package: DownloadedPackage, enabledOverride: Bool? = nil) throws -> URL {
        let tempRoot = root.deletingLastPathComponent().appendingPathComponent(".winegold-stage-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        do {
            var yaml = package.yaml
            if let enabledOverride {
                var document = package.document
                document.enabled = enabledOverride
                yaml = Data(RecipeSerializer().serialize(document).utf8)
            }
            try yaml.write(to: tempRoot.appendingPathComponent(package.recipeFilename), options: .atomic)
            for (relative, data) in package.files {
                let target = tempRoot.appendingPathComponent(relative)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
            }
            if let readme = package.readme { try readme.write(to: tempRoot.appendingPathComponent("README.md"), options: .atomic) }
            return tempRoot
        } catch {
            try? fileManager.removeItem(at: tempRoot)
            throw error
        }
    }

    private func saveProvenance(package: DownloadedPackage, destination: URL, version: String) throws {
        guard let id = package.document.id else { throw RemoteRecipeError.missingPublishedID }
        var hashes: [String: String] = [:]
        hashes[package.recipeFilename] = hash(try Data(contentsOf: destination.appendingPathComponent(package.recipeFilename)))
        for path in package.files.keys { hashes[path] = hash(try Data(contentsOf: destination.appendingPathComponent(path))) }
        if package.readme != nil { hashes["README.md"] = hash(try Data(contentsOf: destination.appendingPathComponent("README.md"))) }
        try provenanceStore.save(RecipeProvenance(recipeID: id, sourceURL: package.sourceURL.absoluteString, installedVersion: version, installedAt: ISO8601DateFormatter().string(from: Date()), yamlHash: hashes[package.recipeFilename] ?? "", fileHashes: hashes, lastUpdateCheck: nil, latestKnownVersion: version))
    }

    private func localModificationDiff(destination: URL, provenance: RecipeProvenance) -> String? {
        var changes: [String] = []
        for (relative, installedHash) in provenance.fileHashes.sorted(by: { $0.key < $1.key }) {
            let url = destination.appendingPathComponent(relative)
            guard fileManager.fileExists(atPath: url.path), let data = try? Data(contentsOf: url) else { changes.append("- missing: \(relative)"); continue }
            if hash(data) != installedHash { changes.append("- modified: \(relative)") }
        }
        return changes.isEmpty ? nil : changes.joined(separator: "\n")
    }

    private func currentEnabled(in destination: URL) throws -> Bool {
        let recipes = try fileManager.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.lowercased().hasSuffix(".wg.yml") }
        guard let recipe = recipes.first else { return true }
        return try parser.parse(url: recipe).document.enabled
    }

    private func uniqueDuplicateURL(for destination: URL) -> URL {
        var index = 1
        var candidate = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + "-local")
        while fileManager.fileExists(atPath: candidate.path) {
            index += 1
            candidate = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + "-local-\(index)")
        }
        return candidate
    }


    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
