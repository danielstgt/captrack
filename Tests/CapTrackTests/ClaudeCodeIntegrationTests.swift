import Foundation
import Testing
@testable import CapTrack

struct ClaudeCodeIntegrationTests {
    let home: URL
    let integration: ClaudeCodeIntegration

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appending(path: "captrack-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        integration = ClaudeCodeIntegration(home: home)
    }

    private func writeSettings(_ text: String) throws {
        try FileManager.default.createDirectory(at: integration.claudeDirectory, withIntermediateDirectories: true)
        try text.write(to: integration.settingsURL, atomically: true, encoding: .utf8)
    }

    @Test func statusReflectsSetup() throws {
        #expect(integration.status() == .claudeCodeNotFound)

        try FileManager.default.createDirectory(at: integration.claudeDirectory, withIntermediateDirectories: true)
        #expect(integration.status() == .notConfigured)

        try writeSettings(#"{"statusLine":{"type":"command","command":"python3 ~/.claude/statusline.py"}}"#)
        #expect(integration.status() == .notConfigured)

        try writeSettings(#"{"statusLine":{"type":"command","command":"~/.local/bin/captrack-statusline"}}"#)
        #expect(integration.status() == .configured)

        try writeSettings("{ broken")
        guard case .unreadable = integration.status() else {
            Issue.record("expected .unreadable")
            return
        }
    }

    @Test func wrapsExistingCommandAndKeepsOtherSettings() throws {
        try writeSettings("""
        {
          "model": "opus",
          "permissions": { "allow": ["Bash(ls:*)"] },
          "statusLine": {
            "type": "command",
            "command": "python3 ~/.claude/statusline.py --style 'hairline'",
            "padding": 2
          }
        }
        """)

        try integration.configureAutomatically()

        let settings = try integration.readSettings()
        let statusLine = try #require(settings["statusLine"] as? [String: Any])
        #expect(statusLine["command"] as? String
                == "~/.local/bin/captrack-statusline 'python3 ~/.claude/statusline.py --style '\\''hairline'\\'''")
        #expect(statusLine["padding"] as? Int == 2)
        #expect(settings["model"] as? String == "opus")
        #expect((settings["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"])
        #expect(integration.status() == .configured)

        // Written the way Claude Code writes it: 2-space indent, `"key": value`, unescaped slashes.
        let text = try String(contentsOf: integration.settingsURL, encoding: .utf8)
        #expect(text.contains("\"type\": \"command\""))
        #expect(!text.contains("\" : "))
        #expect(!text.contains("\\/"))

        let backups = try FileManager.default.contentsOfDirectory(atPath: integration.claudeDirectory.path)
            .filter { $0.hasPrefix("settings.json.captrack-backup-") }
        #expect(backups.count == 1)

        // Running it again is a no-op.
        try integration.configureAutomatically()
        let again = try integration.readSettings()
        #expect((again["statusLine"] as? [String: Any])?["command"] as? String == statusLine["command"] as? String)
    }

    @Test func createsStatusLineWhenMissing() throws {
        try writeSettings(#"{"model": "opus"}"#)
        try integration.configureAutomatically()
        let settings = try integration.readSettings()
        let statusLine = try #require(settings["statusLine"] as? [String: Any])
        #expect(statusLine["type"] as? String == "command")
        #expect(statusLine["command"] as? String == "~/.local/bin/captrack-statusline")
        #expect(FileManager.default.isExecutableFile(atPath: integration.bridgeURL.path))
    }

    @Test func refusesUnknownStatusLineTypes() throws {
        try writeSettings(#"{"statusLine":{"type":"something-else"}}"#)
        #expect(throws: ClaudeCodeIntegration.SetupError.self) {
            try integration.configureAutomatically()
        }
    }

    @Test func snippetIsValidJSONFragment() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"echo \"hi\""}}"#)
        let snippet = integration.suggestedSnippet()
        let object = try JSONSerialization.jsonObject(with: Data("{\(snippet)}".utf8)) as? [String: Any]
        let statusLine = try #require(object?["statusLine"] as? [String: Any])
        #expect(statusLine["command"] as? String == "~/.local/bin/captrack-statusline 'echo \"hi\"'")
    }

    @Test func normalizesFoundationFormatting() {
        let input = """
        {
          "a" : "x : y",
          "list" : [
            "item \\" : with colon"
          ]
        }
        """
        let expected = """
        {
          "a": "x : y",
          "list": [
            "item \\" : with colon"
          ]
        }
        """
        #expect(ClaudeCodeIntegration.normalizeFormatting(input) == expected)
    }

    @Test func bridgeScriptStoresAndPassesThrough() throws {
        try integration.installBridge()
        let payload = #"{"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1738425600}}}"#

        // Store only.
        var result = try run(bridge: [], input: payload)
        #expect(result.status == 0)
        #expect(result.output == "")
        #expect(try String(contentsOf: integration.dataFileURL, encoding: .utf8) == payload)

        // Pass through to a downstream status line command.
        result = try run(bridge: ["tr a-z A-Z"], input: payload)
        #expect(result.status == 0)
        #expect(result.output == payload.uppercased())
        #expect(try String(contentsOf: integration.dataFileURL, encoding: .utf8) == payload)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: integration.dataDirectory.path)
        #expect(leftovers == ["statusline.json"])
    }

    private func run(bridge arguments: [String], input: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [integration.bridgeURL.path] + arguments
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
