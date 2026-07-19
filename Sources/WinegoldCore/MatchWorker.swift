import Foundation

public struct MatchWorkerRequest: Codable {
    public let action: Action
    public let files: [URL]
    public let includeInside: Bool

    public init(action: Action, files: [URL], includeInside: Bool) {
        self.action = action
        self.files = files
        self.includeInside = includeInside
    }
}

public enum MatchWorker {
    public static let argument = "--winegold-match-worker"

    public static func runStandardInput() -> Int32 {
        do {
            let request = try JSONDecoder().decode(MatchWorkerRequest.self, from: FileHandle.standardInput.readDataToEndOfFile())
            let compiled = CompiledActionSet(actions: [request.action])
            guard let trigger = compiled.triggers.first else {
                try FileHandle.standardOutput.write(contentsOf: Data("0".utf8))
                return 0
            }
            let items = request.files.map { DraggedItem(executionURL: $0) }
            let values = items.map { $0.values(includeInside: request.includeInside) }
            let matched: Bool
            if let expression = trigger.expression {
                matched = values.allSatisfy { TriggerEvaluator().evaluate(expression, values: $0) }
            } else if trigger.normalizedExtensions.contains("*") {
                matched = true
            } else {
                matched = items.allSatisfy { trigger.normalizedExtensions.contains($0.executionURL.pathExtension.lowercased()) }
            }
            try FileHandle.standardOutput.write(contentsOf: Data(matched ? "1".utf8 : "0".utf8))
            return 0
        } catch {
            return 1
        }
    }
}
