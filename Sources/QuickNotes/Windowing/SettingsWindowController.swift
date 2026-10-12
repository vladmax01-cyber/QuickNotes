import AppKit
import SwiftUI
import QuickNotesCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let shortcutRecorder: ShortcutRecorderState

    init(
        preferences: AppPreferences,
        launchAtLogin: LaunchAtLoginService,
        viewModel: AppViewModel,
        onShortcutRecordingChanged: @escaping (Bool) -> Void,
        onShortcutRecorded: @escaping (ShortcutDefinition) -> Void
    ) {
        let navigation = SettingsNavigationModel()
        let shortcutRecorder = ShortcutRecorderState()
        shortcutRecorder.onRecordingChanged = onShortcutRecordingChanged
        self.shortcutRecorder = shortcutRecorder
        let rootView = SettingsView(
            preferences: preferences,
            launchAtLogin: launchAtLogin,
            viewModel: viewModel,
            navigation: navigation,
            shortcutRecorder: shortcutRecorder,
            onShortcutRecorded: onShortcutRecorded
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Quick Notes Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.setContentSize(NSSize(width: 610, height: 480))
        window.minSize = NSSize(width: 610, height: 480)
        window.maxSize = NSSize(width: 610, height: 480)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isPresented: Bool { window?.isVisible == true }
    var isRecordingShortcut: Bool { shortcutRecorder.isRecording }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
