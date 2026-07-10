import CryptoKit
import Foundation

public struct ContentAddressedFileStore {
    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func store(
        contents: String,
        prefix: String,
        fileExtension: String
    ) throws -> URL {
        let data = Data(contents.utf8)
        let hash = Self.contentHash(for: data)
        let filename = "\(prefix)-\(hash).\(fileExtension)"
        let destination = directory.appendingPathComponent(filename)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            return destination
        }

        try data.write(to: destination, options: .atomic)
        return destination
    }

    public static func contentHash(for data: Data) -> String {
        SHA256.hash(data: data)
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
