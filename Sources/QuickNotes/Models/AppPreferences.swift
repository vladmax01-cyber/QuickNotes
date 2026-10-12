import AppKit
import SwiftUI
import QuickNotesCore

extension Color {
    static let quickNotesSecondaryText = Color(nsColor: .labelColor).opacity(0.98)
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case purple = "Purple"
    case green = "Green"
    case orange = "Orange"
    case pink = "Pink"
    case neutral = "Neutral"

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .pink: return .systemPink
        case .neutral: return .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

enum FontSizeControlStyle: String, CaseIterable, Identifiable {
    case numeric = "Number"
    case classic = "A− / A+"

    var id: String { rawValue }
}

enum ToolbarAction: String, CaseIterable, Codable, Identifiable {
    case newNote
    case search
    case format
    case delete
    case pin

    var id: String { rawValue }
}

extension Notification.Name {
    static let quickNotesPreferencesChanged = Notification.Name("QuickNotesPreferencesChanged")
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showDockIcon = "showDockIcon"
        static let openAtStartup = "openAtStartup"
        static let rememberPosition = "rememberPosition"
        static let rememberSize = "rememberSize"
        static let defaultPinned = "defaultPinned"
        static let hideOnFocusLoss = "hideOnFocusLoss"
        static let appearance = "appearance"
        static let accent = "accent"
        static let customAccentHue = "customAccentHue"
        static let useCustomAccent = "useCustomAccent"
        static let shortcut = "shortcut"
        static let windowTransparency = "windowTransparency"
        static let useGlass = "useGlass"
        static let translucentCollapsedBar = "translucentCollapsedBar"
        static let toolbarUsesAccent = "toolbarUsesAccent"
        static let fontSizeControlStyle = "fontSizeControlStyle"
        static let showFormattingToolbarWhenWide = "showFormattingToolbarWhenWide"
        static let toolbarOrder = "toolbarOrder"
    }

    private let defaults: UserDefaults

    @Published var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, key: Key.showMenuBarIcon) } }
    @Published var showDockIcon: Bool { didSet { save(showDockIcon, key: Key.showDockIcon) } }
    @Published var openAtStartup: Bool { didSet { save(openAtStartup, key: Key.openAtStartup) } }
    @Published var rememberPosition: Bool { didSet { save(rememberPosition, key: Key.rememberPosition) } }
    @Published var rememberSize: Bool { didSet { save(rememberSize, key: Key.rememberSize) } }
    @Published var defaultPinned: Bool { didSet { save(defaultPinned, key: Key.defaultPinned) } }
    @Published var hideOnFocusLoss: Bool { didSet { save(hideOnFocusLoss, key: Key.hideOnFocusLoss) } }
    @Published var appearance: AppearanceMode { didSet { save(appearance.rawValue, key: Key.appearance) } }
    @Published var accent: AccentChoice { didSet { save(accent.rawValue, key: Key.accent) } }
    @Published var customAccentHue: Double {
        didSet { save(customAccentHue, key: Key.customAccentHue) }
    }
    @Published var useCustomAccent: Bool {
        didSet { save(useCustomAccent, key: Key.useCustomAccent) }
    }
    @Published var windowTransparency: Double {
        didSet { save(windowTransparency, key: Key.windowTransparency) }
    }
    @Published var useGlass: Bool { didSet { save(useGlass, key: Key.useGlass) } }
    @Published var translucentCollapsedBar: Bool {
        didSet { save(translucentCollapsedBar, key: Key.translucentCollapsedBar) }
    }
    @Published var toolbarUsesAccent: Bool {
        didSet { save(toolbarUsesAccent, key: Key.toolbarUsesAccent) }
    }
    @Published var fontSizeControlStyle: FontSizeControlStyle {
        didSet { save(fontSizeControlStyle.rawValue, key: Key.fontSizeControlStyle) }
    }
    @Published var showFormattingToolbarWhenWide: Bool {
        didSet { save(showFormattingToolbarWhenWide, key: Key.showFormattingToolbarWhenWide) }
    }
    @Published var toolbarOrder: [ToolbarAction] {
        didSet {
            if let data = try? JSONEncoder().encode(toolbarOrder) {
                save(data, key: Key.toolbarOrder)
            }
        }
    }
    @Published private(set) var shortcut: ShortcutDefinition

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.showDockIcon: false,
            Key.openAtStartup: false,
            Key.rememberPosition: true,
            Key.rememberSize: true,
            Key.defaultPinned: false,
            Key.hideOnFocusLoss: true,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.accent: AccentChoice.blue.rawValue,
            Key.customAccentHue: 0.58,
            Key.useCustomAccent: false,
            Key.windowTransparency: 0.08,
            Key.useGlass: true,
            Key.translucentCollapsedBar: true,
            Key.toolbarUsesAccent: true,
            Key.fontSizeControlStyle: FontSizeControlStyle.numeric.rawValue,
            Key.showFormattingToolbarWhenWide: true
        ])

        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        showDockIcon = defaults.bool(forKey: Key.showDockIcon)
        openAtStartup = defaults.bool(forKey: Key.openAtStartup)
        rememberPosition = defaults.bool(forKey: Key.rememberPosition)
        rememberSize = defaults.bool(forKey: Key.rememberSize)
        defaultPinned = defaults.bool(forKey: Key.defaultPinned)
        hideOnFocusLoss = defaults.bool(forKey: Key.hideOnFocusLoss)
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        accent = AccentChoice(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .blue
        customAccentHue = min(1, max(0, defaults.double(forKey: Key.customAccentHue)))
        useCustomAccent = defaults.bool(forKey: Key.useCustomAccent)
        windowTransparency = min(1, max(0, defaults.double(forKey: Key.windowTransparency)))
        useGlass = defaults.bool(forKey: Key.useGlass)
        translucentCollapsedBar = defaults.bool(forKey: Key.translucentCollapsedBar)
        toolbarUsesAccent = defaults.bool(forKey: Key.toolbarUsesAccent)
        fontSizeControlStyle = FontSizeControlStyle(
            rawValue: defaults.string(forKey: Key.fontSizeControlStyle) ?? ""
        ) ?? .numeric
        showFormattingToolbarWhenWide = defaults.bool(forKey: Key.showFormattingToolbarWhenWide)

        let defaultOrder = ToolbarAction.allCases
        if let data = defaults.data(forKey: Key.toolbarOrder),
           let decoded = try? JSONDecoder().decode([ToolbarAction].self, from: data),
           decoded.count == defaultOrder.count,
           Set(decoded.map(\.rawValue)) == Set(defaultOrder.map(\.rawValue)) {
            toolbarOrder = decoded
        } else {
            toolbarOrder = defaultOrder
        }

        if let data = defaults.data(forKey: Key.shortcut),
           let decoded = try? JSONDecoder().decode(ShortcutDefinition.self, from: data),
           decoded.hasPrimaryModifier {
            shortcut = decoded
        } else {
            shortcut = .defaultShortcut
            if let data = try? JSONEncoder().encode(ShortcutDefinition.defaultShortcut) {
                defaults.set(data, forKey: Key.shortcut)
            }
        }
    }

    func setShortcut(_ shortcut: ShortcutDefinition) {
        self.shortcut = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Key.shortcut)
        }
        broadcastChange()
    }

    var accentColor: Color {
        useCustomAccent
            ? Color(hue: customAccentHue, saturation: 0.82, brightness: 0.96)
            : accent.color
    }

    func moveToolbarAction(_ action: ToolbarAction, offset: Int) {
        guard let source = toolbarOrder.firstIndex(of: action), toolbarOrder.count > 1 else { return }
        let destination = (source + offset + toolbarOrder.count) % toolbarOrder.count
        toolbarOrder.swapAt(source, destination)
    }

    private func save(_ value: Any, key: String) {
        defaults.set(value, forKey: key)
        broadcastChange()
    }

    private func broadcastChange() {
        NotificationCenter.default.post(name: .quickNotesPreferencesChanged, object: self)
    }
}
