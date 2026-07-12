import AppKit

func makeAppAlert() -> NSAlert {
    let alert = NSAlert()
    alert.icon = roundedAppIcon()
    return alert
}

private func roundedAppIcon() -> NSImage {
    let source = bundledAppIcon() ?? NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 64, height: 64))
    let size = NSSize(width: 64, height: 64)
    let image = NSImage(size: size)
    image.lockFocus()
    NSBezierPath(
        roundedRect: NSRect(origin: .zero, size: size),
        xRadius: 14,
        yRadius: 14
    ).addClip()
    source.draw(in: NSRect(origin: .zero, size: size))
    image.unlockFocus()
    return image
}

private func bundledAppIcon() -> NSImage? {
    if let url = Bundle.main.url(forResource: "winegold-app-icon", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
        return NSImage(contentsOf: url)
    }
    return nil
}
