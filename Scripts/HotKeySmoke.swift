import AppKit
import QuickNotesCore

enum HotKeySmokeFailure: Error {
    case failed(String)
}

@main
enum HotKeySmoke {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let service = GlobalHotKeyService()
        let fnOnly = ShortcutDefinition(
            keyCode: 45,
            carbonModifiers: 131072,
            keyLabel: "N"
        )
        do {
            try service.register(fnOnly) {}
            throw HotKeySmokeFailure.failed("The service accepted an fn-only shortcut")
        } catch GlobalHotKeyError.invalidShortcut {
        }
        try service.register(.defaultShortcut) {}
        service.unregister()
        print("Global shortcut registration passed for Control + N")
    }
}
