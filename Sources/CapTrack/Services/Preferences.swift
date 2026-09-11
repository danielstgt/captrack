import Foundation
import Observation

/// Which parts of one rate-limit window appear in the menu bar.
nonisolated struct WindowDisplayOptions: Equatable, Sendable {
    /// The "5h" / "7d" label.
    var label = true
    var ring = true
    var percentage = true
    /// Countdown to the reset, e.g. "2h05m".
    var resetTime = true

    var isEmpty: Bool { !label && !ring && !percentage && !resetTime }

    static let all = WindowDisplayOptions()
    static let none = WindowDisplayOptions(label: false, ring: false, percentage: false, resetTime: false)
}

/// User settings, persisted in UserDefaults.
@Observable
final class Preferences {
    var fiveHourDisplay: WindowDisplayOptions {
        didSet { store(fiveHourDisplay, prefix: Keys.fiveHour) }
    }
    var sevenDayDisplay: WindowDisplayOptions {
        didSet { store(sevenDayDisplay, prefix: Keys.sevenDay) }
    }
    var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: Keys.automaticUpdateChecks) }
    }
    var skippedVersion: String? {
        didSet { defaults.set(skippedVersion, forKey: Keys.skippedVersion) }
    }
    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Keys.lastUpdateCheck) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let fiveHour = "menuBar.fiveHour"
        static let sevenDay = "menuBar.sevenDay"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let skippedVersion = "skippedVersion"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let parts = ["label", "ring", "percentage", "resetTime"]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var registered: [String: Any] = [Keys.automaticUpdateChecks: true]
        for prefix in [Keys.fiveHour, Keys.sevenDay] {
            for part in Keys.parts { registered["\(prefix).\(part)"] = true }
        }
        defaults.register(defaults: registered)

        fiveHourDisplay = Self.load(prefix: Keys.fiveHour, from: defaults)
        sevenDayDisplay = Self.load(prefix: Keys.sevenDay, from: defaults)
        automaticUpdateChecks = defaults.bool(forKey: Keys.automaticUpdateChecks)
        skippedVersion = defaults.string(forKey: Keys.skippedVersion)
        lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
    }

    private static func load(prefix: String, from defaults: UserDefaults) -> WindowDisplayOptions {
        WindowDisplayOptions(
            label: defaults.bool(forKey: "\(prefix).label"),
            ring: defaults.bool(forKey: "\(prefix).ring"),
            percentage: defaults.bool(forKey: "\(prefix).percentage"),
            resetTime: defaults.bool(forKey: "\(prefix).resetTime")
        )
    }

    private func store(_ options: WindowDisplayOptions, prefix: String) {
        defaults.set(options.label, forKey: "\(prefix).label")
        defaults.set(options.ring, forKey: "\(prefix).ring")
        defaults.set(options.percentage, forKey: "\(prefix).percentage")
        defaults.set(options.resetTime, forKey: "\(prefix).resetTime")
    }
}
