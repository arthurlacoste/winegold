import Foundation

public enum PanelPresentationMode: String, CaseIterable {
    case empty
    case idleNoFiles
    case dragging
    case dropped
    case running
    case done
}

public struct PanelPresentation: Equatable {
    public let mode: PanelPresentationMode
    public let dropTitle: String
    public let actionsVisible: Bool
    public let shouldCollapseWindow: Bool
    public let recentRunsCentered: Bool
    public let bottomToolsPinned: Bool
    public let technicalDetailsVisible: Bool
    public let usesCompatibleActions: Bool
    public let commitsFileOnDrop: Bool
    public let keepsFileForNextAction: Bool
    public let keepsDoneStateUntilNextAction: Bool
    public let canLaunchAnotherAction: Bool
    public let blocksAutoHideDuringDrag: Bool

    public init(
        mode: PanelPresentationMode,
        dropTitle: String,
        actionsVisible: Bool = true,
        shouldCollapseWindow: Bool = false,
        recentRunsCentered: Bool = true,
        bottomToolsPinned: Bool = true,
        technicalDetailsVisible: Bool = false,
        usesCompatibleActions: Bool = true,
        commitsFileOnDrop: Bool = false,
        keepsFileForNextAction: Bool = false,
        keepsDoneStateUntilNextAction: Bool = false,
        canLaunchAnotherAction: Bool = false,
        blocksAutoHideDuringDrag: Bool = false
    ) {
        self.mode = mode
        self.dropTitle = dropTitle
        self.actionsVisible = actionsVisible
        self.shouldCollapseWindow = shouldCollapseWindow
        self.recentRunsCentered = recentRunsCentered
        self.bottomToolsPinned = bottomToolsPinned
        self.technicalDetailsVisible = technicalDetailsVisible
        self.usesCompatibleActions = usesCompatibleActions
        self.commitsFileOnDrop = commitsFileOnDrop
        self.keepsFileForNextAction = keepsFileForNextAction
        self.keepsDoneStateUntilNextAction = keepsDoneStateUntilNextAction
        self.canLaunchAnotherAction = canLaunchAnotherAction
        self.blocksAutoHideDuringDrag = blocksAutoHideDuringDrag
    }

    public static func make(mode: PanelPresentationMode, showsTechnicalDetails: Bool = false) -> PanelPresentation {
        let title: String
        switch mode {
        case .empty: title = "Drop files here"
        case .idleNoFiles: title = "Drop files here"
        case .dragging: title = "Drop to show compatible actions"
        case .dropped: title = "Drop files here"
        case .running: title = "Running"
        case .done: title = "Done"
        }

        return PanelPresentation(
            mode: mode,
            dropTitle: title,
            actionsVisible: mode != .idleNoFiles,
            shouldCollapseWindow: mode == .idleNoFiles,
            technicalDetailsVisible: (mode == .running || mode == .done) && showsTechnicalDetails,
            usesCompatibleActions: mode == .dragging || mode == .dropped || mode == .running || mode == .done,
            commitsFileOnDrop: mode == .dropped || mode == .running || mode == .done,
            keepsFileForNextAction: mode == .dropped || mode == .running || mode == .done,
            keepsDoneStateUntilNextAction: mode == .done,
            canLaunchAnotherAction: mode == .dropped || mode == .done,
            blocksAutoHideDuringDrag: mode == .dragging
        )
    }

    public var snapshot: String {
        [
            "mode=\(mode.rawValue)",
            "drop=\(dropTitle)",
            "actions=\(actionsVisible)",
            "collapsed=\(shouldCollapseWindow)",
            "recent=centered:\(recentRunsCentered)",
            "tools=bottom-left:\(bottomToolsPinned)",
            "technical=\(technicalDetailsVisible)",
            "compatible=\(usesCompatibleActions)",
            "commit=\(commitsFileOnDrop)",
            "keepFile=\(keepsFileForNextAction)",
            "doneSticky=\(keepsDoneStateUntilNextAction)",
            "canRunNext=\(canLaunchAnotherAction)",
            "dragBlocksAutohide=\(blocksAutoHideDuringDrag)"
        ].joined(separator: "\n")
    }
}

public struct PanelAutoHideState: Equatable {
    public private(set) var hasEnteredPanel = false

    public init() {}

    public mutating func update(isPointerInside: Bool) -> Bool {
        if isPointerInside {
            hasEnteredPanel = true
            return false
        }
        return hasEnteredPanel
    }

    public mutating func reset() {
        hasEnteredPanel = false
    }
}
