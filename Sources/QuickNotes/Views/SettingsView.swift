import AppKit
import SwiftUI
import QuickNotesCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case shortcut = "Shortcut"
    case window = "Window"
    case appearance = "Appearance"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcut: return "keyboard"
        case .window: return "macwindow"
        case .appearance: return "paintpalette"
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
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var shortcutRecorder: ShortcutRecorderState
    let onShortcutRecorded: (ShortcutDefinition) -> Void

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
        .environment(\.locale, Locale(identifier: "en_US"))
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
                Text("The shortcut works from any app and does not require Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }

            if let error = viewModel.shortcutError {
                ErrorRow(message: error)
            }
        }
    }

    private var windowSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup("Remember") {
                Toggle("Remember window position", isOn: $preferences.rememberPosition)
                Toggle("Remember window size", isOn: $preferences.rememberSize)
            }

            SettingsGroup("Behavior") {
                Toggle("Pin by default", isOn: $preferences.defaultPinned)
                Toggle("Hide when focus is lost", isOn: $preferences.hideOnFocusLoss)
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
                        .fill(Color(hue: preferences.customAccentHue, saturation: 0.82, brightness: 0.96))
                        .frame(width: 18, height: 18)
                }
                HueSlider(value: Binding(
                    get: { preferences.customAccentHue },
                    set: { hue in
                        preferences.customAccentHue = hue
                        preferences.useCustomAccent = true
                    }
                ))
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
        }
    }
}

private struct HueSlider: View {
    @Binding var value: Double

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
                    .fill(Color(hue: value, saturation: 0.82, brightness: 0.96))
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
