import Foundation

enum Formatting {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }

    /// Countdown in the style of the Claude Code status line: "2h 05m", "3d 04h", "12m".
    /// The compact form drops the spaces for the menu bar: "2h05m", "3d04h", "<1m".
    static func countdown(to date: Date, from now: Date, compact: Bool = false) -> String {
        let total = max(0, Int(date.timeIntervalSince(now)))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let space = compact ? "" : " "
        if days > 0 { return "\(days)d\(space)\(String(format: "%02d", hours))h" }
        if hours > 0 { return "\(hours)h\(space)\(String(format: "%02d", minutes))m" }
        if minutes > 0 { return "\(minutes)m" }
        return compact ? "<1m" : "less than a minute"
    }

    /// Localised clock time, e.g. "16:12" or "4:12 PM".
    static func clockTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Localised weekday + clock time, e.g. "Sun 14:00".
    static func weekdayTime(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    /// "just now", "2 min. ago", "3 hr. ago".
    static func updatedAgo(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE jm")
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
