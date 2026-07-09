import Foundation

public struct DefaultActions {
    public static let installAddScriptName = "Install .add.yml script"
    public static let createScriptFromFileTypeName = "Create a new script from this type of file"

    public static let all: [Action] = [
        Action(
            name: "Print and clipboard",
            description: "Print the full file path and copy it to clipboard",
            iconName: "doc.on.clipboard",
            acceptedExtensions: ["*"],
            executablePath: "/bin/zsh",
            argumentsTemplate: ["-lc", "printf '%s\n' '{input}'; printf '%s' '{input}' | pbcopy"],
            outputPathTemplate: nil
        ),
        Action(
            name: "Ouvrir dossier",
            description: "Open parent folder in Finder",
            iconName: "folder",
            acceptedExtensions: ["*"],
            executablePath: "/usr/bin/open",
            argumentsTemplate: ["{parent}"],
            outputPathTemplate: nil
        ),
        Action(
            name: installAddScriptName,
            description: "Import a legacy Winegold .add.yml script as an action",
            iconName: "plus.square.dashed",
            acceptedExtensions: ["yml", "yaml"],
            executablePath: "/bin/echo",
            argumentsTemplate: ["Import {input}"],
            outputPathTemplate: nil
        ),
        Action(
            name: createScriptFromFileTypeName,
            description: "Open Settings with a new script prefilled for this file type",
            iconName: "plus.square.on.square",
            acceptedExtensions: ["*"],
            executablePath: "/bin/echo",
            argumentsTemplate: ["Create script for {input}"],
            outputPathTemplate: nil
        ),
    ]
}
