import Cocoa
import WinegoldCore

if CommandLine.arguments.contains(MatchWorker.argument) {
    exit(MatchWorker.runStandardInput())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
