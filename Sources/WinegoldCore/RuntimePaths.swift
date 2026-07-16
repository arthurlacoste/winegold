import Foundation

public enum RuntimePaths {
    public static let appSupportEnvironmentKey = "WINEGOLD_APP_SUPPORT_DIR"
    public static let recipeRootEnvironmentKey = "WINEGOLD_RECIPE_ROOT"

    public static func applicationSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultBase: URL
    ) -> URL {
        guard let override = environment[appSupportEnvironmentKey], !override.isEmpty else {
            return defaultBase.appendingPathComponent("WinegoldNative", isDirectory: true)
        }
        return URL(fileURLWithPath: override, isDirectory: true)
    }

    public static func recipeRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let override = environment[recipeRootEnvironmentKey], !override.isEmpty else {
            return homeDirectory.appendingPathComponent(".winegold/recipes", isDirectory: true)
        }
        return URL(fileURLWithPath: override, isDirectory: true)
    }
}
