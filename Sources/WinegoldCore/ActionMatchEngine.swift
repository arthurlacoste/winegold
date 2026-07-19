import Foundation

public enum PanelPerformanceBudget {
    public static let closeLatency: TimeInterval = 0.25
    public static let partialPublicationRefresh: TimeInterval = 0.016
    public static let recipeSoftTimeout: TimeInterval = 0.1
}

public final class ActionMatchEngine: @unchecked Sendable {
    public static let shared = ActionMatchEngine()

    public typealias EvaluationHook = @Sendable (Action) -> Void

    private struct CacheKey: Hashable {
        let draggedItems: String
        let recipeGeneration: String
    }

    private let lock = NSLock()
    private let perRecipeSoftTimeout: TimeInterval
    private let evaluationHook: EvaluationHook?
    private let workerExecutableURL: URL?
    private let forcesWorkerIsolation: Bool
    private let evaluationQueue: OperationQueue
    private let cacheCapacity = 32
    private var cache: [CacheKey: [ProgressiveMatchBatch]] = [:]
    private var cacheOrder: [CacheKey] = []
    private var inFlight: [CacheKey: DispatchGroup] = [:]
    private var _evaluationCount = 0
    private var _cacheHitCount = 0
    private var _timedOutRecipeCount = 0

    public var evaluationCount: Int { locked { _evaluationCount } }
    public var cacheHitCount: Int { locked { _cacheHitCount } }
    public var timedOutRecipeCount: Int { locked { _timedOutRecipeCount } }

    public init(
        perRecipeSoftTimeout: TimeInterval = PanelPerformanceBudget.recipeSoftTimeout,
        workerExecutableURL: URL? = nil,
        evaluationHook: EvaluationHook? = nil
    ) {
        self.perRecipeSoftTimeout = perRecipeSoftTimeout
        self.workerExecutableURL = workerExecutableURL ?? Self.defaultWorkerExecutableURL
        self.forcesWorkerIsolation = workerExecutableURL != nil
        self.evaluationHook = evaluationHook
        let queue = OperationQueue()
        queue.name = "com.winegold.recipe-matching"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 32
        self.evaluationQueue = queue
    }

    public func match(
        files: [URL],
        actions: [Action],
        shouldContinueAfterPublication: ((ProgressiveMatchBatch) -> Bool)? = nil
    ) -> [ProgressiveMatchBatch] {
        match(
            items: files.map { DraggedItem(executionURL: $0) },
            actions: actions,
            shouldContinueAfterPublication: shouldContinueAfterPublication
        )
    }

    public func match(
        items: [DraggedItem],
        actions: [Action],
        shouldContinueAfterPublication: ((ProgressiveMatchBatch) -> Bool)? = nil
    ) -> [ProgressiveMatchBatch] {
        guard !items.isEmpty else { return [] }
        let key = CacheKey(
            draggedItems: Self.draggedItemSignature(items),
            recipeGeneration: Self.recipeGeneration(actions)
        )
        if let cached = locked({ cache[key] }) {
            locked { _cacheHitCount += 1 }
            return acceptedBatches(cached, callback: shouldContinueAfterPublication)
        }
        let pending: DispatchGroup? = locked {
            if let pending = inFlight[key] { return pending }
            let group = DispatchGroup()
            group.enter()
            inFlight[key] = group
            return nil
        }
        if let pending {
            pending.wait()
            if let cached = locked({ cache[key] }) {
                locked { _cacheHitCount += 1 }
                return acceptedBatches(cached, callback: shouldContinueAfterPublication)
            }
        }
        defer {
            locked {
                inFlight.removeValue(forKey: key)?.leave()
            }
        }

        let compiled = CompiledActionSet(actions: actions)
        let grouped = Dictionary(grouping: compiled.triggers, by: \.cost)
        var resolved: [Action] = []
        var batches: [ProgressiveMatchBatch] = []
        var completedAllTiers = true
        let initialTimeoutCount = timedOutRecipeCount

        for cost in TriggerCost.allCases {
            let candidates = grouped[cost] ?? []
            guard !candidates.isEmpty else { continue }
            let matches = evaluate(candidates, items: items, includeInside: cost == .content)
            resolved.append(contentsOf: matches)
            let remaining = compiled.triggers.filter { $0.cost > cost }.count
            let batch = ProgressiveMatchBatch(cost: cost, actions: resolved, remaining: remaining)
            batches.append(batch)
            if shouldContinueAfterPublication?(batch) == false {
                completedAllTiers = false
                break
            }
        }

        if completedAllTiers, timedOutRecipeCount == initialTimeoutCount { store(batches, for: key) }
        return batches
    }

    public func invalidate() {
        locked {
            cache.removeAll()
            cacheOrder.removeAll()
        }
    }

    public var cachedResultCount: Int { locked { cache.count } }

    public static var defaultWorkerExecutableURL: URL? {
        let url = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        guard url.lastPathComponent == "WinegoldNative" else { return nil }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    public static func draggedItemSignature(_ items: [DraggedItem]) -> String {
        items.map { item in
            let values = try? item.executionURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return [
                item.kind.rawValue,
                item.executionURL.standardizedFileURL.path,
                item.rawURL ?? "",
                item.rawText ?? "",
                values?.contentModificationDate?.timeIntervalSinceReferenceDate.description ?? "",
                values?.fileSize.map(String.init) ?? ""
            ].joined(separator: "|")
        }.joined(separator: "\n")
    }

    public static func recipeGeneration(_ actions: [Action]) -> String {
        actions.map { action in
            [
                action.id.uuidString,
                String(action.enabled),
                action.triggerExpression ?? "",
                action.acceptedExtensions.joined(separator: ","),
                action.updatedAt.timeIntervalSinceReferenceDate.description
            ].joined(separator: "|")
        }.joined(separator: "\n")
    }

    private func evaluate(
        _ candidates: [CompiledActionTrigger],
        items: [DraggedItem],
        includeInside: Bool
    ) -> [Action] {
        final class Result: @unchecked Sendable {
            let lock = NSLock()
            var isSealed = false
            var completed = false
            var matched = false
        }
        let results = candidates.map { _ in Result() }

        let group = DispatchGroup()
        for (index, trigger) in candidates.enumerated() {
            group.enter()
            evaluationQueue.addOperation { [evaluationHook, workerExecutableURL, forcesWorkerIsolation] in
                defer { group.leave() }
                evaluationHook?(trigger.action)
                let matched: Bool?
                if (forcesWorkerIsolation || workerExecutableURL != nil),
                   evaluationHook == nil,
                   let workerExecutableURL {
                    matched = Self.evaluateInWorker(
                        action: trigger.action,
                        files: items.map(\.executionURL),
                        includeInside: includeInside,
                        executableURL: workerExecutableURL,
                        timeout: self.perRecipeSoftTimeout
                    )
                } else {
                    let values = items.map { $0.values(includeInside: includeInside) }
                    if let expression = trigger.expression {
                        matched = values.allSatisfy { TriggerEvaluator().evaluate(expression, values: $0) }
                    } else if trigger.normalizedExtensions.contains("*") {
                        matched = true
                    } else {
                        matched = items.allSatisfy {
                            trigger.normalizedExtensions.contains($0.executionURL.pathExtension.lowercased())
                        }
                    }
                }
                guard let matched else { return }
                let result = results[index]
                result.lock.lock()
                if !result.isSealed {
                    result.completed = true
                    result.matched = matched
                }
                result.lock.unlock()
            }
        }
        let waves = max(1, Int(ceil(Double(candidates.count) / 32.0)))
        _ = group.wait(timeout: .now() + (perRecipeSoftTimeout + 0.05) * Double(waves))

        let snapshots = results.map { result -> (Bool, Bool) in
            result.lock.lock()
            defer { result.lock.unlock() }
            result.isSealed = true
            return (result.completed, result.matched)
        }
        locked {
            _evaluationCount += snapshots.filter(\.0).count
            _timedOutRecipeCount += snapshots.filter { !$0.0 }.count
        }
        return candidates.enumerated().compactMap { snapshots[$0.offset].1 ? $0.element.action : nil }
    }

    private static func evaluateInWorker(
        action: Action,
        files: [URL],
        includeInside: Bool,
        executableURL: URL,
        timeout: TimeInterval
    ) -> Bool? {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = [MatchWorker.argument]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            let data = try JSONEncoder().encode(MatchWorkerRequest(action: action, files: files, includeInside: includeInside))
            try process.run()
            input.fileHandleForWriting.write(data)
            try input.fileHandleForWriting.close()
        } catch {
            if process.isRunning { process.terminate() }
            return nil
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        if process.isRunning {
            process.terminate()
            let killDeadline = ProcessInfo.processInfo.systemUptime + 0.02
            while process.isRunning, ProcessInfo.processInfo.systemUptime < killDeadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return nil
        }
        let value = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 ? value == "1" : nil
    }

    private func store(_ batches: [ProgressiveMatchBatch], for key: CacheKey) {
        locked {
            cache[key] = batches
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            while cacheOrder.count > cacheCapacity {
                cache.removeValue(forKey: cacheOrder.removeFirst())
            }
        }
    }

    private func acceptedBatches(
        _ batches: [ProgressiveMatchBatch],
        callback: ((ProgressiveMatchBatch) -> Bool)?
    ) -> [ProgressiveMatchBatch] {
        guard let callback else { return batches }
        var accepted: [ProgressiveMatchBatch] = []
        for batch in batches {
            accepted.append(batch)
            if !callback(batch) { break }
        }
        return accepted
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
