import Foundation

public enum NoteTimestampFormatter {
    public static func relativeLabel(for date: Date, relativeTo now: Date = Date()) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))

        switch elapsed {
        case 0..<60:
            return "Just now"
        case 60..<3_600:
            let minutes = max(1, elapsed / 60)
            return "\(minutes) min ago"
        case 3_600..<86_400:
            let hours = elapsed / 3_600
            return hours == 1 ? "1 hr ago" : "\(hours) hrs ago"
        case 86_400..<604_800:
            let days = elapsed / 86_400
            return days == 1 ? "1 day ago" : "\(days) days ago"
        default:
            return date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .omitted)
                    .locale(Locale(identifier: "en_US"))
            )
        }
    }
}
