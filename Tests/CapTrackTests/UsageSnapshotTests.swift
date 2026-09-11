import Foundation
import Testing
@testable import CapTrack

struct UsageSnapshotTests {
    let received = Date(timeIntervalSince1970: 1_738_400_000)

    @Test func parsesDocumentedStatusLinePayload() throws {
        let json = """
        {
          "model": { "id": "claude-opus-5", "display_name": "Opus" },
          "rate_limits": {
            "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
            "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
          }
        }
        """
        let snapshot = try UsageSnapshot.parse(Data(json.utf8), receivedAt: received)
        #expect(snapshot.hasRateLimits)
        #expect(snapshot.fiveHour?.usedPercentage == 23.5)
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
        #expect(snapshot.sevenDay?.usedPercentage == 41.2)
        #expect(snapshot.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1_738_857_600))
        #expect(snapshot.receivedAt == received)
    }

    @Test func missingRateLimitsIsReported() throws {
        let snapshot = try UsageSnapshot.parse(Data(#"{"model":{"id":"x"}}"#.utf8), receivedAt: received)
        #expect(!snapshot.hasRateLimits)
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay == nil)
    }

    @Test func individualWindowsMayBeAbsent() throws {
        let json = #"{"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":1738857600}}}"#
        let snapshot = try UsageSnapshot.parse(Data(json.utf8), receivedAt: received)
        #expect(snapshot.hasRateLimits)
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay?.usedPercentage == 10)
    }

    @Test func acceptsISOTimestamps() throws {
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":5,"resets_at":"2025-02-01T16:00:00Z"}}}"#
        let snapshot = try UsageSnapshot.parse(Data(json.utf8), receivedAt: received)
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
    }

    @Test func rejectsNonObjects() {
        #expect(throws: (any Error).self) {
            try UsageSnapshot.parse(Data("[1,2]".utf8), receivedAt: received)
        }
        #expect(throws: (any Error).self) {
            try UsageSnapshot.parse(Data("{not json".utf8), receivedAt: received)
        }
    }

    @Test func windowStates() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let future = RateWindow(usedPercentage: 42, resetsAt: now.addingTimeInterval(60))
        let past = RateWindow(usedPercentage: 42, resetsAt: now.addingTimeInterval(-60))

        #expect(WindowState(window: future, hasRateLimits: true, now: now) == .active(future))
        #expect(WindowState(window: past, hasRateLimits: true, now: now) == .reset(at: past.resetsAt))
        #expect(WindowState(window: nil, hasRateLimits: true, now: now) == .idle)
        #expect(WindowState(window: future, hasRateLimits: false, now: now) == .unavailable)

        #expect(WindowState.active(future).percentage == 42)
        #expect(WindowState.reset(at: now).percentage == 0)
        #expect(WindowState.idle.percentage == 0)
        #expect(WindowState.unavailable.percentage == nil)
    }
}

struct FormattingTests {
    @Test func countdownMatchesStatusLineStyle() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(Formatting.countdown(to: now.addingTimeInterval(2 * 3600 + 5 * 60 + 30), from: now) == "2h 05m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(3 * 86_400 + 4 * 3600), from: now) == "3d 04h")
        #expect(Formatting.countdown(to: now.addingTimeInterval(12 * 60), from: now) == "12m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(20), from: now) == "less than a minute")
        #expect(Formatting.countdown(to: now.addingTimeInterval(-500), from: now) == "less than a minute")
    }

    @Test func compactCountdownForTheMenuBar() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(Formatting.countdown(to: now.addingTimeInterval(2 * 3600 + 5 * 60), from: now, compact: true) == "2h05m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(3 * 86_400 + 4 * 3600), from: now, compact: true) == "3d04h")
        #expect(Formatting.countdown(to: now.addingTimeInterval(12 * 60), from: now, compact: true) == "12m")
        #expect(Formatting.countdown(to: now.addingTimeInterval(20), from: now, compact: true) == "<1m")
    }

    @Test func percentRounds() {
        #expect(Formatting.percent(23.5) == "24%")
        #expect(Formatting.percent(0) == "0%")
        #expect(Formatting.percent(nil) == "–")
    }
}

struct UpdateCheckerTests {
    @Test func versionComparison() {
        #expect(UpdateChecker.isVersion("1.0.1", newerThan: "1.0.0"))
        #expect(UpdateChecker.isVersion("v1.1", newerThan: "1.0.9"))
        #expect(UpdateChecker.isVersion("2.0.0-beta", newerThan: "1.9.9"))
        #expect(!UpdateChecker.isVersion("1.0.0", newerThan: "1.0.0"))
        #expect(!UpdateChecker.isVersion("1.0", newerThan: "1.0.0"))
        #expect(!UpdateChecker.isVersion("0.9.9", newerThan: "1.0.0"))
        #expect(UpdateChecker.isVersion("1.0.0", newerThan: "dev"))
        #expect(!UpdateChecker.isVersion("garbage", newerThan: "1.0.0"))
    }

    @Test func normalizesTags() {
        #expect(UpdateChecker.normalize("v1.2.3") == "1.2.3")
        #expect(UpdateChecker.normalize(" 1.2.3-rc.1\n") == "1.2.3")
    }
}
