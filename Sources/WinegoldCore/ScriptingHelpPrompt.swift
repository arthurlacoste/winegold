import Foundation

public enum ScriptingHelpPrompt {
    public static func make(
        scriptName: String,
        extensions: [String],
        command: String,
        documentation: String = ScriptingGuide.text
    ) -> String {
        let safeName = valueOrMissing(scriptName)
        let safeExtensions = extensions.isEmpty ? "(not provided)" : extensions.joined(separator: ", ")
        let safeCommand = valueOrMissing(command)

        return """
        Help me improve this Winegold Native script.

        Use this documentation as the single source of truth.
        Some current script fields may be empty. Use whatever context is present.

        \(documentation)

        Current script:
        Script name: \(safeName)
        Extensions: \(safeExtensions)
        Command:
        \(safeCommand)

        Return a corrected .wg.yml recipe and explain briefly what changed.
        Use only placeholders documented above.
        """
    }

    private static func valueOrMissing(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(not provided)" : trimmed
    }
}
