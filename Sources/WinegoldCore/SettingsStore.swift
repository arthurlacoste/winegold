import Foundation

public enum PanelSide: String, CaseIterable, Codable {
    case left
    case right
}

public struct SettingsStore {
    private let defaults = UserDefaults.standard

    public init() {}

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    public var panelWidth: Int {
        get { defaults.integer(forKey: "panelWidth").nonzero ?? 360 }
        set { defaults.set(Self.clamp(newValue, min: 320, max: 900), forKey: "panelWidth") }
    }

    public var panelHeight: Int {
        get { defaults.integer(forKey: "panelHeight").nonzero ?? 0 }
        set { defaults.set(Self.clamp(newValue, min: 420, max: 1400), forKey: "panelHeight") }
    }

    public var showNotifications: Bool {
        get { defaults.bool(forKey: "showNotifications") }
        set { defaults.set(newValue, forKey: "showNotifications") }
    }

    public var historyLimit: Int {
        get { defaults.integer(forKey: "historyLimit").nonzero ?? 100 }
        set { defaults.set(newValue, forKey: "historyLimit") }
    }

    public var panelSide: PanelSide {
        get { PanelSide(rawValue: defaults.string(forKey: "panelSide") ?? "") ?? .right }
        set { defaults.set(newValue.rawValue, forKey: "panelSide") }
    }

    public var showPanelShortcut: String {
        get { defaults.string(forKey: "showPanelShortcut") ?? "cmd+shift+p" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), forKey: "showPanelShortcut") }
    }

    private static func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

private extension Int {
    var nonzero: Int? {
        self == 0 ? nil : self
    }
}
