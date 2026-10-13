import AppKit

@MainActor
final class InteractionHaptics {
    enum Event: Equatable {
        case paletteOpened
        case formatApplied
        case inlineFormatApplied
        case noteFolded
        case pinChanged

        var pattern: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .paletteOpened, .inlineFormatApplied, .pinChanged: return .alignment
            case .formatApplied, .noteFolded: return .levelChange
            }
        }

        var minimumInterval: TimeInterval {
            self == .inlineFormatApplied ? 0.06 : 0.14
        }
    }

    static let shared = InteractionHaptics()

    private let perform: (NSHapticFeedbackManager.FeedbackPattern, NSHapticFeedbackManager.PerformanceTime) -> Void
    private let clock: () -> TimeInterval
    private var lastFeedbackTime = -TimeInterval.greatestFiniteMagnitude

    init(
        perform: @escaping (NSHapticFeedbackManager.FeedbackPattern, NSHapticFeedbackManager.PerformanceTime) -> Void = {
            NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: $1)
        },
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.perform = perform
        self.clock = clock
    }

    func play(_ event: Event, enabled: Bool) {
        guard enabled else { return }
        let now = clock()
        guard now - lastFeedbackTime >= event.minimumInterval else { return }
        lastFeedbackTime = now
        perform(event.pattern, .drawCompleted)
    }
}
