import XCTest
@testable import WinegoldCore

final class ActionMatchEngineTests: XCTestCase {
    private func action(_ name: String, trigger: String) -> Action {
        var action = Action(name: name, acceptedExtensions: [], executablePath: "/bin/echo")
        action.triggerExpression = trigger
        return action
    }

    func testSameDragAndRecipeGenerationPerformsZeroRepeatedEvaluations() {
        let engine = ActionMatchEngine()
        let actions = [action("Text", trigger: "extension equals \"txt\"")]
        let files = [URL(fileURLWithPath: "/tmp/a.txt")]

        XCTAssertEqual(engine.match(files: files, actions: actions).last?.actions.map(\.name), ["Text"])
        let firstCount = engine.evaluationCount
        XCTAssertEqual(engine.match(files: files, actions: actions).last?.actions.map(\.name), ["Text"])

        XCTAssertEqual(engine.evaluationCount, firstCount)
        XCTAssertEqual(engine.cacheHitCount, 1)
    }

    func testRecipeGenerationChangeInvalidatesCachedResult() {
        let engine = ActionMatchEngine()
        var value = action("Text", trigger: "extension equals \"txt\"")
        let files = [URL(fileURLWithPath: "/tmp/a.txt")]
        _ = engine.match(files: files, actions: [value])
        let firstCount = engine.evaluationCount

        value.triggerExpression = "extension equals \"md\""
        XCTAssertTrue(engine.match(files: files, actions: [value]).last?.actions.isEmpty == true)

        XCTAssertGreaterThan(engine.evaluationCount, firstCount)
    }

    func testSlowRecipeTimesOutWithoutBlockingFastRecipe() {
        let slow = action("Slow", trigger: "extension equals \"txt\"")
        let fast = action("Fast", trigger: "extension equals \"txt\"")
        let engine = ActionMatchEngine(perRecipeSoftTimeout: 0.03) { action in
            if action.name == "Slow" { Thread.sleep(forTimeInterval: 0.25) }
        }
        let started = ProcessInfo.processInfo.systemUptime

        let result = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: [slow, fast])

        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.15)
        XCTAssertEqual(result.last?.actions.map(\.name), ["Fast"])
        XCTAssertEqual(engine.timedOutRecipeCount, 1)
    }

    func testConcurrentSameKeyRequestsShareOneEvaluation() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let engine = ActionMatchEngine { _ in
            started.signal()
            release.wait()
        }
        let actions = [action("Text", trigger: "extension equals \"txt\"")]
        let files = [URL(fileURLWithPath: "/tmp/a.txt")]
        let group = DispatchGroup()

        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                _ = engine.match(files: files, actions: actions)
                group.leave()
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
        release.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 1), .success)

        XCTAssertEqual(engine.evaluationCount, 1)
        XCTAssertEqual(engine.cacheHitCount, 1)
    }

    func testStaleGenerationCanStopProgressivePublication() {
        let engine = ActionMatchEngine()
        let actions = [
            action("Fast", trigger: "extension equals \"txt\""),
            action("Metadata", trigger: "size greaterThan 0")
        ]
        var publications = 0

        _ = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: actions) { _ in
            publications += 1
            return false
        }

        XCTAssertEqual(publications, 1)
    }

    func testTimedOutRecipesDoNotStarveLaterRecipe() {
        let engine = ActionMatchEngine(perRecipeSoftTimeout: 0.02) { action in
            if action.name.hasPrefix("Blocked") { Thread.sleep(forTimeInterval: 0.2) }
        }
        let blockedActions = (0..<32).map { action("Blocked \($0)", trigger: "extension equals \"txt\"") }
        _ = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: blockedActions)
        let started = ProcessInfo.processInfo.systemUptime

        let result = engine.match(
            files: [URL(fileURLWithPath: "/tmp/b.txt")],
            actions: [action("Fast", trigger: "extension equals \"txt\"")]
        )

        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.15)
        XCTAssertEqual(result.last?.actions.map(\.name), ["Fast"])
    }

    func testAsynchronousPanelGenerationRejectsStalePublication() {
        final class GenerationBox: @unchecked Sendable {
            let lock = NSLock()
            var value = PanelWorkGeneration()
        }
        let generations = GenerationBox()
        let pending = generations.value.begin()
        let staleExpectation = expectation(description: "stale work completed")
        var publications = 0
        DispatchQueue.global().async {
            let engine = ActionMatchEngine(perRecipeSoftTimeout: 0.05) { _ in Thread.sleep(forTimeInterval: 0.02) }
            _ = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: [self.action("Slow", trigger: "extension equals \"txt\"")]) { _ in
                generations.lock.lock()
                defer { generations.lock.unlock() }
                guard generations.value.accepts(pending) else { return false }
                publications += 1
                return true
            }
            staleExpectation.fulfill()
        }
        generations.lock.lock()
        generations.value.invalidate()
        generations.lock.unlock()
        wait(for: [staleExpectation], timeout: 1)

        XCTAssertEqual(publications, 0)
    }

    func testMoreThanEightFastRecipesAllReceiveAnEvaluationWindow() {
        let engine = ActionMatchEngine(perRecipeSoftTimeout: 0.02) { _ in }
        let actions = (0..<24).map { action("Fast \($0)", trigger: "extension equals \"txt\"") }

        let result = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: actions)

        XCTAssertEqual(result.last?.actions.count, 24)
        XCTAssertEqual(engine.evaluationCount, 24)
    }

    func testDefaultEngineEvaluatesThreeHundredRecipesWithoutWorkerIsolation() {
        let engine = ActionMatchEngine()
        let actions = (0..<300).map { action("Fast \($0)", trigger: "extension equals \"txt\"") }

        let result = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: actions)

        XCTAssertEqual(result.last?.actions.count, 300)
        XCTAssertEqual(engine.evaluationCount, 300)
        XCTAssertEqual(engine.timedOutRecipeCount, 0)
    }

    func testCacheIsBounded() {
        let engine = ActionMatchEngine()
        let actions = [action("Text", trigger: "extension equals \"txt\"")]
        for index in 0..<50 {
            _ = engine.match(files: [URL(fileURLWithPath: "/tmp/\(index).txt")], actions: actions)
        }
        XCTAssertLessThanOrEqual(engine.cachedResultCount, 32)
    }

    func testQueuedPanelPublicationIsRejectedAfterInvalidation() {
        let generations = PanelWorkGeneration()
        let generation = generations.begin()
        var queued: (() -> Void)?
        var published = false

        generations.enqueueIfCurrent(generation, enqueue: { queued = $0 }) { published = true }
        generations.invalidate()
        queued?()

        XCTAssertFalse(published)
    }

    func testFastRecipeInSameTierIsNotStarvedByBlockedRecipes() {
        let engine = ActionMatchEngine(perRecipeSoftTimeout: 0.02) { action in
            if action.name.hasPrefix("Blocked") { Thread.sleep(forTimeInterval: 0.2) }
        }
        let actions = (0..<32).map { action("Blocked \($0)", trigger: "extension equals \"txt\"") }
            + [action("Fast", trigger: "extension equals \"txt\"")]
        let started = ProcessInfo.processInfo.systemUptime

        let result = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: actions)

        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.18)
        XCTAssertEqual(result.last?.actions.map(\.name), ["Fast"])
    }

    func testMoreThanEightSlowRecipesStayWithinBoundedAggregateLatency() {
        let engine = ActionMatchEngine(perRecipeSoftTimeout: 0.02) { _ in Thread.sleep(forTimeInterval: 0.2) }
        let actions = (0..<24).map { action("Slow \($0)", trigger: "extension equals \"txt\"") }
        let started = ProcessInfo.processInfo.systemUptime

        _ = engine.match(files: [URL(fileURLWithPath: "/tmp/a.txt")], actions: actions)

        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.15)
        XCTAssertEqual(engine.timedOutRecipeCount, 24)
    }

    func testPerformanceBudgetsAreExplicit() {
        XCTAssertLessThanOrEqual(PanelPerformanceBudget.closeLatency, 0.25)
        XCTAssertLessThanOrEqual(PanelPerformanceBudget.partialPublicationRefresh, 0.016)
    }
}
