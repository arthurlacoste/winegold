import Foundation

public enum PanelFileSelection {
    public static func signature(for files: [URL]) -> String {
        files.map(\.path).joined(separator: "\n")
    }

    public static func shouldIgnore(
        files: [URL],
        currentFiles: [URL],
        lastSignature: String,
        hasResult: Bool,
        isRunning: Bool
    ) -> Bool {
        let signature = signature(for: files)
        guard !signature.isEmpty else { return true }
        return signature == lastSignature
            && signature == self.signature(for: currentFiles)
            && !hasResult
            && !isRunning
    }
}
