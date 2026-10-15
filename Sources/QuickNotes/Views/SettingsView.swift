import AppKit
import SwiftUI
import QuickNotesCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case shortcut = "Shortcut"
    case window = "Window"
    case appearance = "Appearance"
    case trash = "Trash"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcut: return "keyboard"
        case .window: return "macwindow"
        case .appearance: return "paintpalette"
        case .trash: return "trash"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selection: SettingsSection = .general
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var launchAtLogin: LaunchAtLoginService
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var store: NotesStore
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var shortcutRecorder: ShortcutRecorderState
    @ObservedObject var newNoteShortcutRecorder: ShortcutRecorderState
    @ObservedObject var updateChecker: UpdateChecker
    let onShortcutRecorded: (ShortcutDefinition) -> Void
    let onNewNoteShortcutRecorded: (ShortcutDefinition) -> Void
    @State private var confirmEmptyTrash = false

    var body: some View {
        ZStack {
            GlassWindowBackground(
                transparency: preferences.windowTransparency,
                glassEnabled: preferences.useGlass
            )

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    List(SettingsSection.allCases, selection: $navigation.selection) { section in
                        Label(section.rawValue, systemImage: section.symbol)
                            .tag(section)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(sidebarTint)
                    .frame(width: 152)
                    .accessibilityLabel("Settings Sections")

                    Divider().opacity(0.55)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(navigation.selection.rawValue)
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 24)
                            .padding(.top, 22)
                            .padding(.bottom, 16)

                        ScrollView {
                            Group {
                                switch navigation.selection {
                                case .general:
                                    generalSettings
                                case .shortcut:
                                    shortcutSettings
                                case .window:
                                    windowSettings
                                case .appearance:
                                    appearanceSettings
                                case .trash:
                                    trashSettings
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(contentTint)
                }

                Divider().opacity(0.55)
                Label("Notes stay on this Mac.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .center)
                    .accessibilityLabel("Notes stay on this Mac")
                    .background(contentTint)
            }
        }
        .frame(width: 610, height: 452)
        .tint(preferences.accentColor)
        .onChange(of: preferences.automaticallyCheckForUpdates) { _, enabled in
            if enabled { updateChecker.checkIfNeeded() }
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .alert("Empty Trash?", isPresented: $confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) { _ = store.emptyTrash() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Permanently delete \(store.deletedNotes.count) "
                 + (store.deletedNotes.count == 1 ? "note" : "notes") + " from this Mac?")
        }
    }

    private var sidebarTint: Color {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            return Color(nsColor: .controlBackgroundColor)
        }
        let amount = sqrt(min(1, max(0, preferences.windowTransparency)))
        let minimum = colorScheme == .dark ? 0.04 : 0.03
        let maximum = colorScheme == .dark ? 0.28 : 0.18
        return Color(nsColor: .controlBackgroundColor)
            .opacity(maximum - ((maximum - minimum) * amount))
    }

    private var contentTint: Color {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            return Color(nsColor: .windowBackgroundColor)
        }
        let amount = sqrt(min(1, max(0, preferences.windowTransparency)))
        let minimum = colorScheme == .dark ? 0.01 : 0.02
        let maximum = colorScheme == .dark ? 0.22 : 0.14
        return Color(nsColor: .windowBackgroundColor)
            .opacity(maximum - ((maximum - minimum) * amount))
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: launchAtLogin.setEnabled
                ))
                Toggle("Open Quick Note when the app starts", isOn: $preferences.openAtStartup)
            }

            SettingsGroup("App Visibility") {
                Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
                Toggle("Show Dock icon", isOn: $preferences.showDockIcon)
            }

            SettingsGroup("Notes") {
                Toggle("Confirm before moving notes to Trash", isOn: $preferences.confirmNoteDeletion)
                Text("Deleted notes can be restored from Trash.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }

            SettingsGroup("Updates") {
                Toggle("Check for updates automatically", isOn: $preferences.automaticallyCheckForUpdates)
                Text("Checks the public GitHub release once a day. Notes stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
                HStack(spacing: 8) {
                    Button("Check Now") { updateChecker.checkNow() }
                        .disabled(updateChecker.isChecking)
                    if updateChecker.isChecking {
                        ProgressView().controlSize(.small)
                    } else if let release = updateChecker.availableRelease {
                        Button("Version \(release.version) is available") {
                            updateChecker.openRelease()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    } else if let message = updateChecker.checkMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Color.quickNotesSecondaryText)
                    }
                }
            }

            if let error = launchAtLogin.errorMessage {
                ErrorRow(message: error)
            }
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup("Show or Hide Quick Note") {
                ShortcutRecorderView(
                    shortcut: preferences.shortcut,
                    state: shortcutRecorder,
                    onRecorded: onShortcutRecorded
                )
                Text("Use your shortcut from any app.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }

            SettingsGroup("New Note") {
                Toggle("Use a New Note shortcut", isOn: $preferences.newNoteShortcutEnabled)
                if preferences.newNoteShortcutEnabled {
                    ShortcutRecorderView(
                        shortcut: preferences.newNoteShortcut,
                        state: newNoteShortcutRecorder,
                        onRecorded: onNewNoteShortcutRecorded,
                        accessibilityName: "New Note Shortcut"
                    )
                    Text("Works while Quick Notes is active. Command + N is the default.")
                        .font(.caption)
                        .foregroundStyle(Color.quickNotesSecondaryText)
                }
            }

            if let error = viewModel.shortcutError {
                ErrorRow(message: error)
            }
        }
    }

    private var trashSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Deleted Notes")
                        .font(.headline)
                    Text("Restore a note or remove everything permanently.")
                        .font(.caption)
                        .foregroundStyle(Color.quickNotesSecondaryText)
                }
                Spacer()
                Button("Empty Trash…", role: .destructive) { confirmEmptyTrash = true }
                    .disabled(store.deletedNotes.isEmpty)
            }
            if store.deletedNotes.isEmpty {
                ContentUnavailableView(
                    "Trash Is Empty",
                    systemImage: "trash",
                    description: Text("Deleted notes will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                let sorted = store.deletedNotes.sorted { $0.modifiedAt > $1.modifiedAt }
                LazyVStack(spacing: 0) {
                    ForEach(sorted) { note in
                        HStack(spacing: 12) {
                            Image(systemName: "note.text")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).lineLimit(1)
                                Text(note.preview)
                                    .font(.caption)
                                    .foregroundStyle(Color.quickNotesSecondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Button("Restore") { _ = store.restoreDeletedNote(note.id) }
                                .accessibilityLabel("Restore \(note.title)")
                        }
                        .padding(.vertical, 9)
                        if note.id != sorted.last?.id { Divider() }
                    }
                }
            }
            if let error = store.storageError { ErrorRow(message: error) }
        }
    }

    private var windowSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup("Remember") {
                Toggle("Remember window position", isOn: $preferences.rememberPosition)
                Toggle("Remember window size", isOn: $preferences.rememberSize)
            }

            SettingsGroup("Behavior") {
                HStack(spacing: 11) {
                    Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(preferences.accentColor)
                        .frame(width: 32, height: 32)
                        .background(preferences.accentColor.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pin Quick Note")
                        Text("Keep it visible while you switch apps.")
                            .font(.caption)
                            .foregroundStyle(Color.quickNotesSecondaryText)
                    }
                    Spacer(minLength: 8)
                    Toggle("Pin Quick Note", isOn: Binding(
                        get: { viewModel.isPinned },
                        set: { pinned in
                            viewModel.isPinned = pinned
                            preferences.defaultPinned = pinned
                        }
                    ))
                        .labelsHidden()
                }
                .accessibilityElement(children: .contain)
                Toggle("Hide when focus is lost", isOn: $preferences.hideOnFocusLoss)
                Toggle("Remember where I left each note", isOn: $preferences.rememberReadingPosition)
                Text("Turn off to open notes at the top.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
                Toggle("Translucent collapsed bar", isOn: $preferences.translucentCollapsedBar)
                Text("Pinned notes stay visible until you hide them explicitly.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup("Theme") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Appearance")
            }

            SettingsGroup("Accent") {
                HStack(spacing: 12) {
                    ForEach(AccentChoice.allCases) { accent in
                        Button {
                            preferences.accent = accent
                            preferences.useCustomAccent = false
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 24, height: 24)
                                if preferences.accent == accent && !preferences.useCustomAccent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .overlay(
                                Circle().stroke(
                                    preferences.accent == accent && !preferences.useCustomAccent
                                        ? Color.primary.opacity(0.55) : Color.clear,
                                    lineWidth: 2
                                )
                                .padding(-3)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(accent.rawValue)
                        .accessibilityLabel("\(accent.rawValue) accent")
                        .accessibilityValue(
                            preferences.accent == accent && !preferences.useCustomAccent
                                ? "Selected" : "Not selected"
                        )
                    }
                }
                HStack(spacing: 8) {
                    Text("Custom color")
                        .font(.caption)
                    Spacer()
                    Circle()
                        .fill(Color(hue: preferences.customAccentHue, saturation: 0.82,
                                    brightness: preferences.customAccentBrightness))
                        .frame(width: 18, height: 18)
                }
                HueSlider(value: Binding(
                    get: { preferences.customAccentHue },
                    set: { hue in
                        preferences.customAccentHue = hue
                        preferences.useCustomAccent = true
                    }
                ), brightness: preferences.customAccentBrightness)
                HStack(spacing: 9) {
                    Text("Shade")
                        .font(.caption)
                        .foregroundStyle(Color.quickNotesSecondaryText)
                    Image(systemName: "moon.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.quickNotesSecondaryText)
                        .accessibilityHidden(true)
                    Slider(value: Binding(
                        get: { preferences.customAccentBrightness },
                        set: { brightness in
                            preferences.customAccentBrightness = brightness
                            preferences.useCustomAccent = true
                        }
                    ), in: 0.45...0.96)
                    .tint(Color(hue: preferences.customAccentHue, saturation: 0.82,
                                brightness: preferences.customAccentBrightness))
                    .accessibilityLabel("Custom color shade")
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.quickNotesSecondaryText)
                        .accessibilityHidden(true)
                }
                .help("Move left for a darker custom color")
                Button("Use custom color") {
                    preferences.useCustomAccent = true
                }
                .font(.caption)
                .disabled(preferences.useCustomAccent)
                Toggle("Use accent color on toolbar icons", isOn: $preferences.toolbarUsesAccent)
            }

            SettingsGroup("Liquid Glass") {
                Toggle("Use Liquid Glass", isOn: $preferences.useGlass)
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Slider(
                        value: $preferences.windowTransparency,
                        in: 0...1
                    )
                    Text("\(Int((preferences.windowTransparency * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.quickNotesSecondaryText)
                        .frame(width: 40, alignment: .trailing)
                }
                .disabled(!preferences.useGlass)
                Text("Applies to Quick Note and Settings. Text remains fully opaque for readability.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }

            SettingsGroup("Formatting Toolbar") {
                Toggle(
                    "Show formatting controls when the note is wide",
                    isOn: $preferences.showFormattingToolbarWhenWide
                )
                Toggle(
                    "Use accent color for format controls",
                    isOn: $preferences.formatControlsUseAccent
                )
                .help(
                    "Colors the format buttons in the wide toolbar and Aa menu. Selected buttons stay highlighted."
                )
                Text("Command-click a toolbar icon to move it right. Command-Shift-click moves it left.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
                Picker("Font size controls", selection: $preferences.fontSizeControlStyle) {
                    ForEach(FontSizeControlStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingsGroup("Interaction") {
                Toggle("Haptic feedback", isOn: $preferences.hapticFeedbackEnabled)
                Text("Light taps for the wide toolbar, firmer taps for formatting and folding. Resizing stays quiet.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }
        }
    }
}

private struct HueSlider: View {
    @Binding var value: Double
    let brightness: Double

    var body: some View {
        GeometryReader { geometry in
            let thumbSize: CGFloat = 18
            let travel = max(0, geometry.size.width - thumbSize)

            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 7)
                .clipShape(Capsule())

                Circle()
                    .fill(Color(hue: value, saturation: 0.82, brightness: brightness))
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: travel * value)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                value = min(1, max(0, (gesture.location.x - thumbSize / 2) / max(travel, 1)))
            })
        }
        .frame(height: 24)
        .focusable()
        .onKeyPress(.leftArrow) {
            value = max(0, value - 1.0 / 36)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            value = min(1, value + 1.0 / 36)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Custom accent color")
        .accessibilityValue("\(Int((value * 360).rounded())) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 1.0 / 36)
            case .decrement: value = max(0, value - 1.0 / 36)
            @unknown default: break
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

private struct ErrorRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .foregroundStyle(.primary)
        }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Error: \(message)")
    }
}
