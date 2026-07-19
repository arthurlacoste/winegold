import Foundation

public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let archiveURL: URL
    public let checksumURL: URL
    public let releasePageURL: URL
    public let notes: String

    public init(version: String, archiveURL: URL, checksumURL: URL, releasePageURL: URL, notes: String) {
        self.version = version
        self.archiveURL = archiveURL
        self.checksumURL = checksumURL
        self.releasePageURL = releasePageURL
        self.notes = notes
    }
}

public enum AppReleaseError: LocalizedError, Equatable {
    case invalidResponse
    case invalidTag(String)
    case missingArchive
    case missingChecksum

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub returned an invalid release response."
        case .invalidTag(let tag): return "The release tag '\(tag)' is not a valid version."
        case .missingArchive: return "The release does not contain a Winegold macOS ZIP archive."
        case .missingChecksum: return "The release does not contain a SHA-256 checksum."
        }
    }
}

public enum AppReleaseParser {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, draft, prerelease, assets
        }
    }

    public static func parseLatestRelease(data: Data) throws -> AppRelease {
        let payload: GitHubRelease
        do {
            payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw AppReleaseError.invalidResponse
        }

        let version = normalizedVersion(payload.tagName)
        guard VersionComparator.isValid(version) else {
            throw AppReleaseError.invalidTag(payload.tagName)
        }

        guard let archive = payload.assets.first(where: {
            $0.name.hasPrefix("Winegold-") && $0.name.hasSuffix("-macOS.zip")
        }) else {
            throw AppReleaseError.missingArchive
        }
        guard let checksum = payload.assets.first(where: {
            $0.name == archive.name + ".sha256"
        }) else {
            throw AppReleaseError.missingChecksum
        }

        return AppRelease(
            version: version,
            archiveURL: archive.browserDownloadURL,
            checksumURL: checksum.browserDownloadURL,
            releasePageURL: payload.htmlURL,
            notes: payload.body ?? ""
        )
    }

    public static func normalizedVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}

public enum VersionComparator {
    public static func isValid(_ version: String) -> Bool {
        components(version) != nil
    }

    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let candidateParts = components(candidate), let installedParts = components(installed) else {
            return false
        }
        return candidateParts.lexicographicallyPrecedes(installedParts) == false && candidateParts != installedParts
    }

    private static func components(_ version: String) -> [Int]? {
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let pieces = core.split(separator: ".")
        guard pieces.count == 3 else { return nil }
        let values = pieces.compactMap { Int($0) }
        return values.count == 3 ? values : nil
    }
}
