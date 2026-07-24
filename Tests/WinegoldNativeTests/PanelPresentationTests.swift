import XCTest
@testable import WinegoldCore

final class PanelPresentationTests: XCTestCase {
    func testActionsAreHiddenOnlyForShortcutNoFileMode() {
        XCTAssertFalse(PanelPresentation.make(mode: .idleNoFiles).actionsVisible)
        XCTAssertTrue(PanelPresentation.make(mode: .empty).actionsVisible)
        XCTAssertTrue(PanelPresentation.make(mode: .dragging).actionsVisible)
        XCTAssertTrue(PanelPresentation.make(mode: .dropped).actionsVisible)
        XCTAssertTrue(PanelPresentation.make(mode: .running).actionsVisible)
        XCTAssertTrue(PanelPresentation.make(mode: .done).actionsVisible)
    }

    func testShortcutNoFileModeCollapsesWindowImmediately() {
        XCTAssertTrue(PanelPresentation.make(mode: .idleNoFiles).shouldCollapseWindow)
        XCTAssertFalse(PanelPresentation.make(mode: .dragging).shouldCollapseWindow)
        XCTAssertFalse(PanelPresentation.make(mode: .dropped).shouldCollapseWindow)
        XCTAssertFalse(PanelPresentation.make(mode: .running).shouldCollapseWindow)
        XCTAssertFalse(PanelPresentation.make(mode: .done).shouldCollapseWindow)
    }

    func testTechnicalDetailsAreOnlyShownForRunningAndDoneModes() {
        XCTAssertFalse(PanelPresentation.make(mode: .empty, showsTechnicalDetails: true).technicalDetailsVisible)
        XCTAssertFalse(PanelPresentation.make(mode: .dragging, showsTechnicalDetails: true).technicalDetailsVisible)
        XCTAssertFalse(PanelPresentation.make(mode: .dropped, showsTechnicalDetails: true).technicalDetailsVisible)
        XCTAssertTrue(PanelPresentation.make(mode: .running, showsTechnicalDetails: true).technicalDetailsVisible)
        XCTAssertTrue(PanelPresentation.make(mode: .done, showsTechnicalDetails: true).technicalDetailsVisible)
    }

    func testDragPreviewDoesNotCommitButShowsCompatibleActionsAndBlocksAutohide() {
        let dragging = PanelPresentation.make(mode: .dragging)
        XCTAssertTrue(dragging.actionsVisible)
        XCTAssertTrue(dragging.usesCompatibleActions)
        XCTAssertFalse(dragging.commitsFileOnDrop)
        XCTAssertFalse(dragging.keepsFileForNextAction)
        XCTAssertTrue(dragging.blocksAutoHideDuringDrag)
    }

    func testDropAndChooseFilesCommitTheFileForMultipleActions() {
        let dropped = PanelPresentation.make(mode: .dropped)
        XCTAssertTrue(dropped.actionsVisible)
        XCTAssertTrue(dropped.usesCompatibleActions)
        XCTAssertTrue(dropped.commitsFileOnDrop)
        XCTAssertTrue(dropped.keepsFileForNextAction)
        XCTAssertTrue(dropped.canLaunchAnotherAction)
    }

    func testDoneStateIsStickyAndAllowsNextAction() {
        let done = PanelPresentation.make(mode: .done)
        XCTAssertTrue(done.actionsVisible)
        XCTAssertTrue(done.keepsDoneStateUntilNextAction)
        XCTAssertTrue(done.keepsFileForNextAction)
        XCTAssertTrue(done.canLaunchAnotherAction)
        XCTAssertFalse(done.shouldCollapseWindow)
    }

    func testFooterToolsAreAlwaysPinned() {
        for mode in PanelPresentationMode.allCases {
            XCTAssertTrue(PanelPresentation.make(mode: mode).bottomToolsPinned)
        }
    }

    func testFinderStyleSnapshots() {
        XCTAssertEqual(
            PanelPresentation.make(mode: .idleNoFiles).snapshot,
            """
            mode=idleNoFiles
            drop=Drop files here
            actions=false
            collapsed=true
            recent=centered:true
            tools=bottom-left:true
            technical=false
            compatible=false
            commit=false
            keepFile=false
            doneSticky=false
            canRunNext=false
            dragBlocksAutohide=false
            """
        )
        XCTAssertEqual(
            PanelPresentation.make(mode: .dragging).snapshot,
            """
            mode=dragging
            drop=Drop to show compatible actions
            actions=true
            collapsed=false
            recent=centered:true
            tools=bottom-left:true
            technical=false
            compatible=true
            commit=false
            keepFile=false
            doneSticky=false
            canRunNext=false
            dragBlocksAutohide=true
            """
        )
        XCTAssertEqual(
            PanelPresentation.make(mode: .dropped).snapshot,
            """
            mode=dropped
            drop=Drop files here
            actions=true
            collapsed=false
            recent=centered:true
            tools=bottom-left:true
            technical=false
            compatible=true
            commit=true
            keepFile=true
            doneSticky=false
            canRunNext=true
            dragBlocksAutohide=false
            """
        )
        XCTAssertEqual(
            PanelPresentation.make(mode: .running, showsTechnicalDetails: true).snapshot,
            """
            mode=running
            drop=Running
            actions=true
            collapsed=false
            recent=centered:true
            tools=bottom-left:true
            technical=true
            compatible=true
            commit=true
            keepFile=true
            doneSticky=false
            canRunNext=false
            dragBlocksAutohide=false
            """
        )
        XCTAssertEqual(
            PanelPresentation.make(mode: .done, showsTechnicalDetails: true).snapshot,
            """
            mode=done
            drop=Done
            actions=true
            collapsed=false
            recent=centered:true
            tools=bottom-left:true
            technical=true
            compatible=true
            commit=true
            keepFile=true
            doneSticky=true
            canRunNext=true
            dragBlocksAutohide=false
            """
        )
    }
}

final class PanelAutoHideStateTests: XCTestCase {
    func testDoesNotDismissBeforePointerHasEnteredPanel() {
        var state = PanelAutoHideState()
        XCTAssertFalse(state.update(isPointerInside: false))
        XCTAssertFalse(state.hasEnteredPanel)
    }

    func testDismissesOnlyAfterPointerEntersThenLeaves() {
        var state = PanelAutoHideState()
        XCTAssertFalse(state.update(isPointerInside: true))
        XCTAssertTrue(state.hasEnteredPanel)
        XCTAssertTrue(state.update(isPointerInside: false))
    }

    func testResetRequiresAnewEntry() {
        var state = PanelAutoHideState()
        _ = state.update(isPointerInside: true)
        state.reset()
        XCTAssertFalse(state.update(isPointerInside: false))
    }

    func testRepeatedInsideUpdatesRemainNonDismissing() {
        var state = PanelAutoHideState()
        XCTAssertFalse(state.update(isPointerInside: true))
        XCTAssertFalse(state.update(isPointerInside: true))
        XCTAssertTrue(state.hasEnteredPanel)
    }

    func testRepeatedOutsideUpdatesAfterEntryRemainDismissing() {
        var state = PanelAutoHideState()
        _ = state.update(isPointerInside: true)
        XCTAssertTrue(state.update(isPointerInside: false))
        XCTAssertTrue(state.update(isPointerInside: false))
    }
}
