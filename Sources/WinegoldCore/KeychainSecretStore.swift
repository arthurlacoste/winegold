import Foundation

/// Local secret storage that avoids interactive macOS Keychain prompts.
public final class LocalSecretStore: KeychainSecretStoreProtocol {
    private static let lock = NSLock()
    private let fileURL: URL

    public init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".winegold", isDirectory: true)
        .appendingPathComponent("secrets.json")) {
        self.fileURL = fileURL
    }

    public func read(key: String) -> String? {
        withStorage { $0[key] }
    }

    public func write(key: String, value: String) {
        updateStorage { $0[key] = value }
    }

    public func delete(key: String) {
        updateStorage { $0.removeValue(forKey: key) }
    }

    public func listKeys() -> [String] {
        withStorage { Array($0.keys) }
    }

    private func withStorage<T>(_ body: ([String: String]) -> T) -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return body(load())
    }

    private func updateStorage(_ change: (inout [String: String]) -> Void) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var storage = load()
        change(&storage)
        save(storage)
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func save(_ storage: [String: String]) {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(storage)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Secret persistence must not crash command execution.
        }
    }
}
