import Foundation

/// One rate-limit window as reported by Claude Code (`rate_limits.five_hour` / `seven_day`).
nonisolated struct RateWindow: Sendable, Equatable {
    /// 0...100, may carry decimals.
    var usedPercentage: Double
    /// Moment the window resets.
    var resetsAt: Date

    var fraction: Double { min(max(usedPercentage, 0), 100) / 100 }

    func hasReset(at now: Date) -> Bool { now >= resetsAt }
}

/// What CapTrack knows about the account's usage, parsed from the status line JSON.
nonisolated struct UsageSnapshot: Sendable, Equatable {
    /// `rate_limits` was present at all. Absent for API-key sessions or before the first response.
    var hasRateLimits: Bool
    var fiveHour: RateWindow?
    var sevenDay: RateWindow?
    /// When Claude Code produced this data (file modification time).
    var receivedAt: Date

    nonisolated enum ParseError: Error { case notAnObject }

    /// Parses the JSON Claude Code hands to status line commands. Tolerates missing or
    /// partially filled `rate_limits` objects, integer or float timestamps, and ISO strings.
    static func parse(_ data: Data, receivedAt: Date) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notAnObject
        }
        let limits = root["rate_limits"] as? [String: Any]
        return UsageSnapshot(
            hasRateLimits: limits != nil,
            fiveHour: window(limits?["five_hour"]),
            sevenDay: window(limits?["seven_day"]),
            receivedAt: receivedAt
        )
    }

    private static func window(_ value: Any?) -> RateWindow? {
        guard let object = value as? [String: Any],
              let percentage = (object["used_percentage"] as? NSNumber)?.doubleValue,
              let resetsAt = date(object["resets_at"]) else { return nil }
        return RateWindow(usedPercentage: percentage.isFinite ? percentage : 0, resetsAt: resetsAt)
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, number.doubleValue > 0 {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let string = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: string) { return date }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: string)
        }
        return nil
    }
}

/// Display state of a single window, derived from a snapshot and the current time.
nonisolated enum WindowState: Equatable, Sendable {
    /// Window is running: percentage used and when it resets.
    case active(RateWindow)
    /// The reset time passed while no newer data arrived. Usage is 0 until the next message.
    case reset(at: Date)
    /// Claude Code reports rate limits but no window right now (fresh after a reset).
    case idle
    /// Claude Code reported no rate limits at all (API key, or no response yet).
    case unavailable

    init(window: RateWindow?, hasRateLimits: Bool, now: Date) {
        guard hasRateLimits else { self = .unavailable; return }
        guard let window else { self = .idle; return }
        self = window.hasReset(at: now) ? .reset(at: window.resetsAt) : .active(window)
    }

    var percentage: Double? {
        switch self {
        case .active(let window): window.usedPercentage
        case .reset, .idle: 0
        case .unavailable: nil
        }
    }
}
