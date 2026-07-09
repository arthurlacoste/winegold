import Foundation

public enum ScriptingHelpPrompt {
    public static func make(
        scriptName: String,
        extensions: [String],
        command: String,
        documentation: String = ScriptingGuide.text
    ) -> String {
        """
        Help me improve this Winegold Native script.

        Use this documentation as the single source of truth.

        \(documentation)

        Current script:
        Script name: \(scriptName)
        Extensions: \(extensions.joined(separator: ", "))
        Command:
        \(command)

        Return a corrected .add.yml script and explain briefly what changed.
        Use only placeholders documented above.
        """
    }
}
