import AppKit

@main
struct HapticSmoke {
    @MainActor
    static func main() {
        var now: TimeInterval = 1
        var pulses: [(NSHapticFeedbackManager.FeedbackPattern, NSHapticFeedbackManager.PerformanceTime)] = []
        let haptics = InteractionHaptics(
            perform: { pattern, time in pulses.append((pattern, time)) },
            clock: { now }
        )

        haptics.play(.formatApplied, enabled: false)
        precondition(pulses.isEmpty, "Disabled haptics produced a pulse")

        haptics.play(.paletteOpened, enabled: true)
        now += 0.05
        haptics.play(.formatApplied, enabled: true)
        precondition(pulses.count == 1, "Adjacent menu and format taps were not grouped")
        precondition(pulses[0].0 == .alignment, "Opening Format lost its snap feedback")

        now += 0.15
        haptics.play(.formatApplied, enabled: true)
        now += 0.15
        haptics.play(.noteFolded, enabled: true)
        now += 0.15
        haptics.play(.pinChanged, enabled: true)
        now += 0.08
        haptics.play(.inlineFormatApplied, enabled: true)
        now += 0.08
        haptics.play(.inlineFormatApplied, enabled: true)
        precondition(pulses.count == 6, "Visible format controls lost individual light taps")
        precondition(pulses[1].0 == .levelChange && pulses[2].0 == .levelChange,
                     "Formatting and folding lost their firmer feedback")
        precondition(pulses[3].0 == .alignment, "Pinning lost its snap feedback")
        precondition(pulses[4].0 == .alignment && pulses[5].0 == .alignment,
                     "Visible format controls did not use the lighter feedback")
        precondition(pulses.allSatisfy { $0.1 == .drawCompleted },
                     "Haptics did not follow the visual update")
        print("Haptic event, timing, and disabled-setting smoke tests passed")
    }
}
