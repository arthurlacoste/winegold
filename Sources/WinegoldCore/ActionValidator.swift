import Foundation

public enum ActionValidationStatus {
    case available
    case missingDependency(reason: String)
    case configError(reason: String)
}

public struct ActionValidator {
    public init() {}

    public func validate(_ action: Action) -> ActionValidationStatus {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: action.executablePath, isDirectory: &isDir) else {
            return .missingDependency(reason: "\(action.executablePath) introuvable")
        }
        guard !isDir.boolValue else {
            return .configError(reason: "\(action.executablePath) est un dossier")
        }
        guard fm.isExecutableFile(atPath: action.executablePath) else {
            return .configError(reason: "\(action.executablePath) n'est pas exécutable")
        }
        guard action.timeoutSeconds > 0 else {
            return .configError(reason: "timeoutSeconds doit être > 0")
        }
        return .available
    }
}
