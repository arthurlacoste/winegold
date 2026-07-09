import Foundation

public enum ScriptingGuide {
    public static var text: String {
        loadFromRepository() ?? "Winegold scripting documentation could not be loaded."
    }

    public static func loadFromRepository(sourceFilePath: String = #filePath) -> String? {
        let sourceFile = URL(fileURLWithPath: sourceFilePath)
        let repositoryRoot = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let docURL = repositoryRoot.appendingPathComponent("docs/scripting.md")
        return try? String(contentsOf: docURL, encoding: .utf8)
    }
}
