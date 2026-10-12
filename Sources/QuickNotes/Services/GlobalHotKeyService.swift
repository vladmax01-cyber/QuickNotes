import AppKit
import Carbon.HIToolbox
import QuickNotesCore

enum GlobalHotKeyError: LocalizedError {
    case invalidShortcut
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            return "Use Control, Option, or Command with another key."
        case .registrationFailed(let status):
            if status == eventHotKeyExistsErr {
                return "That shortcut is already used by another app. Choose a different combination."
            }
            return "The shortcut could not be registered (error \(status))."
        }
    }
}

private func quickNotesHotKeyHandler(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        service.handlePress()
    }
    return noErr
}

final class GlobalHotKeyService {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (() -> Void)?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            quickNotesHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(_ shortcut: ShortcutDefinition, action: @escaping () -> Void) throws {
        guard shortcut.hasPrimaryModifier else {
            throw GlobalHotKeyError.invalidShortcut
        }
        unregister()
        self.action = action
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x514E4F54, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            self.action = nil
            throw GlobalHotKeyError.registrationFailed(status)
        }
        hotKey = reference
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
    }

    fileprivate func handlePress() {
        action?()
    }
}

enum ShortcutFactory {
    static func definition(from event: NSEvent) -> ShortcutDefinition? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.function) { carbonModifiers |= UInt32(kEventKeyModifierFnMask) }

        let label = keyLabel(for: event)
        let definition = ShortcutDefinition(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbonModifiers,
            keyLabel: label
        )
        return definition.hasPrimaryModifier ? definition : nil
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "Return",
            48: "Tab",
            49: "Space",
            51: "Delete",
            53: "Escape",
            64: "F17",
            79: "F18",
            80: "F19",
            90: "F20",
            96: "F5",
            97: "F6",
            98: "F7",
            99: "F3",
            100: "F8",
            101: "F9",
            103: "F11",
            105: "F13",
            106: "F16",
            107: "F14",
            109: "F10",
            111: "F12",
            113: "F15",
            118: "F4",
            120: "F2",
            122: "F1",
            115: "Home",
            116: "Page Up",
            117: "Forward Delete",
            119: "End",
            121: "Page Down",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑"
        ]
        if let label = special[event.keyCode] { return label }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }
        return "Key \(event.keyCode)"
    }
}
