import Cocoa
import WinegoldCore

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
        var urls: [URL] = []

        for item in items {
            if let url = existingFileURL(from: item) {
                urls.append(url)
                continue
            }

            let preferred = item.types.first { supportedTypes.contains($0) }
            if preferred == .URL,
               let raw = nonEmptyString(item.string(forType: .URL)),
               looksLikeWebURL(raw),
               let url = createTemporaryDragFile(contents: raw, preferredExtension: "url", prefix: "dragged-url") {
                urls.append(url)
                continue
            }

            if let text = nonEmptyString(item.string(forType: .string) ?? item.string(forType: .html)) {
                if let url = createTemporaryDragFile(
                    contents: text,
                    preferredExtension: "txt",
                    prefix: "dragged-text"
                ) {
                    urls.append(url)
                }
                continue
            }

            if let raw = nonEmptyString(item.string(forType: .URL) ?? item.string(forType: .string)),
               looksLikeWebURL(raw),
               let url = createTemporaryDragFile(
                   contents: raw,
                   preferredExtension: "url",
                   prefix: "dragged-url"
               ) {
                urls.append(url)
            }
        }

        return uniqueURLs(urls)
    }

    private static func existingFileURL(from item: NSPasteboardItem) -> URL? {
        if let raw = item.string(forType: .fileURL),
           let url = urlFromRaw(raw),
           url.isFileURL {
            return url
        }

        guard let raw = nonEmptyString(item.string(forType: .URL) ?? item.string(forType: .string)) else {
            return nil
        }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        guard let url = URL(string: raw), url.isFileURL else { return nil }
        return url
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func generatedFilesFromTextPasteboard(_ pasteboard: NSPasteboard) -> [URL] {
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            if let html = pasteboard.string(forType: .html)?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty {
                return [createTemporaryDragFile(contents: html, preferredExtension: "txt", prefix: "dragged-text")].compactMap { $0 }
            }
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
            let store = ContentAddressedFileStore(directory: appSupport)
            let url = try store.store(
                contents: contents,
                prefix: prefix,
                fileExtension: preferredExtension
            )
            logMsg("[DragFileReader] resolved pasteboard file: \(url.lastPathComponent)")
            return url
        } catch {
            logMsg("[DragFileReader] failed to generate pasteboard file: \(error.localizedDescription)")
            return nil
        }
    }
}
