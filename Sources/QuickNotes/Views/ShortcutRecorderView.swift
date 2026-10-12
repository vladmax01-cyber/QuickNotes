import AppKit
import SwiftUI
import QuickNotesCore

final class ShortcutRecorderState: ObservableObject {
    @Published var isRecording = false
    @Published var validationMessage: String?
    private var eventMonitor: Any?
    var onRecordingChanged: (Bool) -> Void = { _ in }

    func toggle(onRecorded: @escaping (ShortcutDefinition) -> Void) {
        isRecording ? stop() : start(onRecorded: onRecorded)
    }

    func start(onRecorded: @escaping (ShortcutDefinition) -> Void) {
        validationMessage = nil
        isRecording = true
        onRecordingChanged(true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stop()
                return nil
            }
            guard let definition = ShortcutFactory.definition(from: event) else {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers.contains(.function) {
                    self.validationMessage = "macOS reserves fn-only shortcuts such as fn + N. Use Control, Option, or Command."
                } else {
                    self.validationMessage = "Add Control, Option, or Command to the shortcut."
                }
                NSSound.beep()
                return nil
            }
            self.stop()
            onRecorded(definition)
            return nil
        }
    }

    func stop() {
        let wasRecording = isRecording
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        if wasRecording {
            onRecordingChanged(false)
        }
    }
}

struct ShortcutRecorderView: View {
    let shortcut: ShortcutDefinition
    @ObservedObject var state: ShortcutRecorderState
    let onRecorded: (ShortcutDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                state.toggle(onRecorded: onRecorded)
            } label: {
                HStack {
                    Text(state.isRecording ? "Type a shortcut…" : shortcut.displayString)
                        .font(.body.weight(.medium).monospaced())
                        .foregroundStyle(
                            state.isRecording
                                ? AnyShapeStyle(Color.quickNotesSecondaryText)
                                : AnyShapeStyle(.primary)
                        )
                    Spacer()
                    Image(systemName: state.isRecording ? "keyboard.badge.ellipsis" : "record.circle")
                        .foregroundStyle(state.isRecording ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            state.isRecording
                                ? Color.primary.opacity(0.72)
                                : Color(nsColor: .separatorColor),
                            lineWidth: state.isRecording ? 2 : 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Global Shortcut")
            .accessibilityValue(state.isRecording ? "Recording" : shortcut.displayString)
            .accessibilityHint("Press to record a new shortcut")

            if let validationMessage = state.validationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(validationMessage)
                        .foregroundStyle(.primary)
                }
                    .font(.caption)
            } else {
                Text(state.isRecording
                     ? "Press Escape to cancel."
                     : "Use Control, Option, or Command with another key. macOS uses fn + N for Notification Center.")
                    .font(.caption)
                    .foregroundStyle(Color.quickNotesSecondaryText)
            }
        }
        .onDisappear(perform: state.stop)
    }
}
