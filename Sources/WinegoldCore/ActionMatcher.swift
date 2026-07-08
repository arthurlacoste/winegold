import Foundation

public struct ActionMatcher {
    public init() {}

    public func matchingActions(for files: [URL], actions: [Action]) -> [Action] {
        guard !files.isEmpty else { return [] }

        let enabled = actions.filter { $0.enabled }
        return enabled.filter { action in
            let acceptedExtensions = normalizedExtensions(action.acceptedExtensions)
            guard !acceptedExtensions.isEmpty else { return false }
            if acceptedExtensions.contains("*") { return true }

            return files.allSatisfy { file in
                let ext = file.pathExtension.lowercased()
                return acceptedExtensions.contains(ext)
            }
        }
    }

    private func normalizedExtensions(_ extensions: [String]) -> [String] {
        extensions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
