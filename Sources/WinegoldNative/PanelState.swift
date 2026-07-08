import Foundation
import WinegoldCore

class PanelState {
    var files: [URL] = []
    var actions: [Action] = []
    var allActions: [Action] = []
    var history: [RunHistoryItem] = []
    var savedHistory: [RunHistoryItem] = []
    var savedHistoryIds: Set<UUID> = []
    var lastResult: CommandResult?
    var activeActionId: UUID?
    var runningActionName: String?
    var runningFiles: [URL] = []
    var isCompact = false
}
