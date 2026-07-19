import Cocoa
import CryptoKit
import WinegoldCore

final class AppUpdateController {
    var onUpdateAvailable: ((String) -> Void)?
    var onInstallationFailed: (() -> Void)?
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/arthurlacoste/winegold/releases/latest")!
    private let session: URLSession
    private let defaults: UserDefaults
    private let checkInterval: TimeInterval = 24 * 60 * 60

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    func checkAutomatically() {
        let lastCheck = defaults.object(forKey: "appUpdateLastCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= checkInterval else { return }
        defaults.set(Date(), forKey: "appUpdateLastCheck")
        Task { @MainActor in try? await checkForUpdates(showNoUpdateAlert: false) }
    }

    func checkManually() {
        Task { @MainActor in
            do {
                try await checkForUpdates(showNoUpdateAlert: true)
            } catch {
                onInstallationFailed?()
                showAlert(title: "Update check failed", message: error.localizedDescription)
            }
        }
    }

    func installAvailableUpdate() {
        Task { @MainActor in
            do {
                let release = try await fetchLatestRelease()
                try await downloadAndInstall(release)
            } catch {
                onInstallationFailed?()
                showAlert(title: "Update failed", message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func fetchLatestRelease() async throws -> AppRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Winegold", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppReleaseError.invalidResponse
        }
        return try AppReleaseParser.parseLatestRelease(data: data)
    }

    @MainActor
    private func checkForUpdates(showNoUpdateAlert: Bool) async throws {
        let release = try await fetchLatestRelease()
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard VersionComparator.isNewer(release.version, than: installed) else {
            if showNoUpdateAlert {
                showAlert(title: "Winegold is up to date", message: "Version \(installed) is the latest release.")
            }
            return
        }

        onUpdateAvailable?(release.version)

        guard showNoUpdateAlert else { return }
        let alert = makeAppAlert()
        alert.messageText = "Winegold \(release.version) is available"
        alert.informativeText = release.notes.isEmpty ? "Download and install the update now?" : release.notes
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "View Release")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            try await downloadAndInstall(release)
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.releasePageURL)
        default:
            break
        }
    }

    @MainActor
    private func downloadAndInstall(_ release: AppRelease) async throws {
        let (archiveTemporaryURL, archiveResponse) = try await session.download(from: release.archiveURL)
        guard (archiveResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppReleaseError.invalidResponse
        }
        let (checksumData, checksumResponse) = try await session.data(from: release.checksumURL)
        guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw AppReleaseError.invalidResponse
        }

        let expected = String(decoding: checksumData, as: UTF8.self)
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .first.map(String.init)?.lowercased() ?? ""
        let archiveData = try Data(contentsOf: archiveTemporaryURL)
        let actual = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard expected.count == 64, expected == actual else {
            throw NSError(domain: "WinegoldUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "The downloaded update failed SHA-256 verification."])
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("winegold-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("Winegold.zip")
        try FileManager.default.moveItem(at: archiveTemporaryURL, to: archive)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, work.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "WinegoldUpdate", code: 3, userInfo: [NSLocalizedDescriptionKey: "The update archive could not be extracted."])
        }

        let newApp = work.appendingPathComponent("Winegold.app")
        guard FileManager.default.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/WinegoldNative").path) else {
            throw NSError(domain: "WinegoldUpdate", code: 4, userInfo: [NSLocalizedDescriptionKey: "The update archive does not contain Winegold.app."])
        }

        try launchInstaller(newApp: newApp, destination: Bundle.main.bundleURL)
        NSApp.terminate(nil)
    }

    private func launchInstaller(newApp: URL, destination: URL) throws {
        guard destination.pathExtension == "app" else {
            throw NSError(domain: "WinegoldUpdate", code: 5, userInfo: [NSLocalizedDescriptionKey: "Winegold must be running from an application bundle to install an update."])
        }

        let destinationParent = destination.deletingLastPathComponent()
        let installID = UUID().uuidString
        let stagedApp = destinationParent.appendingPathComponent(".winegold-update-\(installID).app")
        let backupApp = destinationParent.appendingPathComponent(".winegold-backup-\(installID).app")
        try copyAppForAtomicInstall(from: newApp, to: stagedApp)

        let script = FileManager.default.temporaryDirectory.appendingPathComponent("winegold-install-\(UUID().uuidString).sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        let body = """
        #!/bin/bash
        set -euo pipefail
        cleanup() { rm -f "$0"; }
        restore_backup() {
          if [[ -e \(shellQuote(backupApp.path)) ]]; then
            rm -rf \(shellQuote(destination.path))
            mv \(shellQuote(backupApp.path)) \(shellQuote(destination.path))
          fi
        }
        trap cleanup EXIT
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        if [[ -e \(shellQuote(destination.path)) ]]; then
          mv \(shellQuote(destination.path)) \(shellQuote(backupApp.path))
        fi
        if ! mv \(shellQuote(stagedApp.path)) \(shellQuote(destination.path)); then
          restore_backup
          exit 1
        fi
        xattr -dr com.apple.quarantine \(shellQuote(destination.path)) 2>/dev/null || true
        if ! open \(shellQuote(destination.path)); then
          restore_backup
          exit 1
        fi
        rm -rf \(shellQuote(backupApp.path))
        rm -rf \(shellQuote(newApp.deletingLastPathComponent().path))
        """
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: stagedApp)
            try? FileManager.default.removeItem(at: script)
            throw error
        }
    }

    private func copyAppForAtomicInstall(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw NSError(domain: "WinegoldUpdate", code: 6, userInfo: [NSLocalizedDescriptionKey: "The update could not be prepared next to the installed application."])
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func showAlert(title: String, message: String) {
        let alert = makeAppAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
