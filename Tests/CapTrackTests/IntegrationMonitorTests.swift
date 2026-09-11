import Foundation
import Testing
@testable import CapTrack

struct IntegrationMonitorTests {
    @Test func followsChangesToSettingsFile() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "captrack-tests-\(UUID().uuidString)")
        let integration = ClaudeCodeIntegration(home: home)
        try FileManager.default.createDirectory(at: integration.claudeDirectory, withIntermediateDirectories: true)

        let monitor = IntegrationMonitor(integration: integration)
        #expect(monitor.status == .notConfigured)
        #expect(monitor.snippet.contains("\"command\": \"~/.local/bin/captrack-statusline\""))
        monitor.start()

        // Written atomically, the way Claude Code and CapTrack write it.
        try #"{"statusLine":{"type":"command","command":"~/.local/bin/captrack-statusline 'python3 x.py'"}}"#
            .write(to: integration.settingsURL, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(800))
        #expect(monitor.status == .configured)
        #expect(monitor.snippet.contains("python3 x.py"))

        try FileManager.default.removeItem(at: integration.settingsURL)
        try await Task.sleep(for: .milliseconds(800))
        #expect(monitor.status == .notConfigured)

        // A manual refresh reads the file directly.
        try #"{"statusLine":{"type":"command","command":"~/.local/bin/captrack-statusline"}}"#
            .write(to: integration.settingsURL, atomically: true, encoding: .utf8)
        monitor.refresh()
        #expect(monitor.status == .configured)
    }
}
