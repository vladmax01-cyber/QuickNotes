import Foundation

public struct ShortcutDefinition: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var keyLabel: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    public var displayString: String {
        var components: [String] = []
        if carbonModifiers & 131072 != 0 { components.append("fn") }
        if carbonModifiers & 4096 != 0 { components.append("Control") }
        if carbonModifiers & 2048 != 0 { components.append("Option") }
        if carbonModifiers & 512 != 0 { components.append("Shift") }
        if carbonModifiers & 256 != 0 { components.append("Command") }
        components.append(keyLabel)
        return components.joined(separator: " + ")
    }

    public var hasPrimaryModifier: Bool {
        carbonModifiers & (4096 | 2048 | 256) != 0
    }

    public static let defaultShortcut = ShortcutDefinition(
        keyCode: 45,
        carbonModifiers: 4096,
        keyLabel: "N"
    )
}
