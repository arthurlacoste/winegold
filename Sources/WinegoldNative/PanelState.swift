import Foundation
import WinegoldCore

class PanelState {
    var files: [URL] = []
    var actions: [Action] = []
    var allActions: [Action] = []
    var actionMetadata: [UUID: RecipeActionMetadata] = [:]
    var setupRequirements: [UUID: RecipeSetupRequirements] = [:]
    var history: [RunHistoryItem] = []
    var savedHistory: [RunHistoryItem] = []
    var savedHistoryIds: Set<UUID> = []
    var lastResult: CommandResult?
    var batchResults: [CommandResult] = []
    var activeActionId: UUID?
    var runningActionName: String?
    var runningFiles: [URL] = []
    var runningCurrentFile: URL?
    var runningFileIndex: Int?
    var runningFileCount = 0
    var runningCommand: String?
    var runningWorkingDirectory: String?
    var runningStdout = ""
    var runningStderr = ""
    var isCompact = false
    var isMatchingActions = false

    func clearRunningDetails() {
        runningActionName = nil
        runningFiles = []
        runningCurrentFile = nil
        runningFileIndex = nil
        runningFileCount = 0
        runningCommand = nil
        runningWorkingDirectory = nil
        runningStdout = ""
        runningStderr = ""
    }
}
