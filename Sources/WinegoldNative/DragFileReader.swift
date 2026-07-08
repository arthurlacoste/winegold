import Cocoa

enum DragFileReader {
    static let supportedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        .html,
        NSPasteboard.PasteboardType("NSFilenamesPboardType")
    ]

    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: filenamesType) as? [String], !paths.isEmpty {
            return paths.map { URL(fileURLWithPath: $0) }
        }

        let itemURLs = urlsFromPasteboardItems(pasteboard)
        if !itemURLs.isEmpty { return itemURLs }

        let generated = generatedFilesFromTextPasteboard(pasteboard)
        if !generated.isEmpty { return generated }

        return []
    }

    static func urls(from info: NSDraggingInfo) -> [URL] {
        urls(from: info.draggingPasteboard)
    }

    private static func urlsFromPasteboardItems(_ pasteboard: NSPasteboard) -> [URL] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        var generated: [URL] = []
        var fileURLs: [URL] = []

        for item in items {
            if let raw = item.string(forType: .fileURL), let url = urlFromRaw(raw), url.isFileURL {
                fileURLs.append(url)
                continue
            }

            if let raw = item.string(forType: .URL) ?? item.string(forType: .string) {
                if raw.hasPrefix("/") {
                    fileURLs.append(URL(fileURLWithPath: raw))
                } else if let url = URL(string: raw), url.isFileURL {
                    fileURLs.append(url)
                } else if looksLikeWebURL(raw) {
                    if let generatedURL = createTemporaryDragFile(contents: raw, preferredExtension: "url", prefix: "dragged-url") {
                        generated.append(generatedURL)
                    }
                }
            }

            if let html = item.string(forType: .html), !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let generatedURL = createTemporaryDragFile(contents: html, preferredExtension: "html", prefix: "dragged-html") {
                    generated.append(generatedURL)
                }
            }
        }

        return fileURLs.isEmpty ? generated.compactMap { $0 } : fileURLs
    }

    private static func generatedFilesFromTextPasteboard(_ pasteboard: NSPasteboard) -> [URL] {
        if let html = pasteboard.string(forType: .html), !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [createTemporaryDragFile(contents: html, preferredExtension: "html", prefix: "dragged-html")].compactMap { $0 }
        }

        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return []
        }

        let ext = looksLikeWebURL(text) ? "url" : "txt"
        let prefix = looksLikeWebURL(text) ? "dragged-url" : "dragged-text"
        return [createTemporaryDragFile(contents: text, preferredExtension: ext, prefix: prefix)].compactMap { $0 }
    }

    private static func urlFromRaw(_ raw: String) -> URL? {
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        return URL(string: raw)
    }

    private static func looksLikeWebURL(_ raw: String) -> Bool {
        let lowered = raw.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    private static func createTemporaryDragFile(contents: String, preferredExtension: String, prefix: String) -> URL? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("WinegoldNative/DraggedPayloads", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let filename = "\(prefix)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).\(preferredExtension)"
            let url = appSupport.appendingPathComponent(filename)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            logMsg("[DragFileReader] generated file from pasteboard: \(url.lastPathComponent)")
            return url
        } catch {
            logMsg("[DragFileReader] failed to generate pasteboard file: \(error.localizedDescription)")
            return nil
        }
    }
}
