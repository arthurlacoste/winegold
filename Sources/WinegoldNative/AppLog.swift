import Foundation
import OSLog

let osLogger = Logger(subsystem: "com.winegold.native", category: "debug")

func logMsg(_ msg: String) {
    osLogger.info("\(msg, privacy: .public)")
    print(msg)

    do {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("WinegoldNative")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("winegold.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try line.write(to: file, atomically: true, encoding: .utf8)
        }
    } catch {
        print("[WinegoldLog] failed: \(error)")
    }
}
