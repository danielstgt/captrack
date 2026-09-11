import AppKit
import Testing
@testable import CapTrack

struct SettingsWindowTests {
    @Test func windowFollowsContentSizeAndKeepsItsTopEdge() throws {
        let suite = "captrack-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let home = FileManager.default.temporaryDirectory.appending(path: "captrack-tests-\(UUID().uuidString)")
        let monitor = IntegrationMonitor(integration: ClaudeCodeIntegration(home: home))
        let controller = SettingsWindowController(preferences: preferences, updateChecker: UpdateChecker(preferences: preferences), monitor: monitor)
        let window = try #require(controller.window)

        // Sized to the content right away, not to AppKit's placeholder frame.
        let initial = window.contentRect(forFrameRect: window.frame).size
        #expect(initial.width == SettingsView.width)
        #expect(initial.height > 300)

        let top = window.frame.maxY
        controller.contentSizeChanged(CGSize(width: SettingsView.width, height: initial.height + 120))
        let grown = window.contentRect(forFrameRect: window.frame).size
        #expect(abs(grown.height - (initial.height + 120)) < 0.5)
        #expect(abs(window.frame.maxY - top) < 0.5)

        controller.contentSizeChanged(CGSize(width: SettingsView.width, height: initial.height))
        #expect(abs(window.contentRect(forFrameRect: window.frame).height - initial.height) < 0.5)
        #expect(abs(window.frame.maxY - top) < 0.5)
    }
}
