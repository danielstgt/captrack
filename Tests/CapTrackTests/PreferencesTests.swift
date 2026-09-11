import Foundation
import Testing
@testable import CapTrack

struct PreferencesTests {
    @Test func defaultsAndPersistence() {
        let suite = "captrack-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.automaticUpdateChecks)
        #expect(preferences.fiveHourDisplay == .all)
        #expect(preferences.sevenDayDisplay == .all)
        #expect(preferences.skippedVersion == nil)

        preferences.automaticUpdateChecks = false
        preferences.fiveHourDisplay.resetTime = false
        preferences.sevenDayDisplay = .none
        preferences.skippedVersion = "1.2.0"

        let reloaded = Preferences(defaults: UserDefaults(suiteName: suite)!)
        #expect(!reloaded.automaticUpdateChecks)
        #expect(reloaded.fiveHourDisplay == WindowDisplayOptions(label: true, ring: true, percentage: true, resetTime: false))
        #expect(reloaded.sevenDayDisplay == .none)
        #expect(reloaded.skippedVersion == "1.2.0")
    }
}
