import Foundation

/// Connects CapTrack to Claude Code through the official status line hook.
///
/// Claude Code hands every status line command a JSON document that includes
/// `rate_limits`. CapTrack installs a small shell script that stores a copy of that
/// JSON and passes it on unchanged to whatever status line command was configured before.
struct ClaudeCodeIntegration {
    /// The integration for the current user's home directory.
    static let live = ClaudeCodeIntegration(home: FileManager.default.homeDirectoryForCurrentUser)

    /// The bridge path as written into settings.json; the shell expands `~`.
    static let bridgeCommand = "~/.local/bin/captrack-statusline"

    static let bridgeScript = """
    #!/bin/sh
    # CapTrack – Claude Code status line bridge (installed by CapTrack.app)
    #
    # Claude Code runs this command for its status line and pipes a JSON document
    # into it. The script keeps a copy for CapTrack and hands the JSON on, unchanged,
    # to the status line command given as argument (if any). It never contacts a
    # network or reads anything else.
    #
    #   captrack-statusline                              store only, print nothing
    #   captrack-statusline 'python3 ~/.claude/statusline.py'
    #                                                    store, then run that command
    set -u
    dir="$HOME/Library/Application Support/CapTrack"
    mkdir -p "$dir"
    tmp="$dir/.statusline.json.$$"
    trap 'rm -f "$tmp"; exit 1' INT TERM
    if [ $# -gt 0 ]; then
      tee "$tmp" | sh -c "$*"
    else
      cat > "$tmp"
    fi
    mv -f "$tmp" "$dir/statusline.json"

    """

    let home: URL

    var dataDirectory: URL { home.appending(path: "Library/Application Support/CapTrack") }
    var dataFileURL: URL { dataDirectory.appending(path: "statusline.json") }
    var bridgeURL: URL { home.appending(path: ".local/bin/captrack-statusline") }
    var claudeDirectory: URL { home.appending(path: ".claude") }
    var settingsURL: URL { claudeDirectory.appending(path: "settings.json") }

    enum Status: Equatable {
        case claudeCodeNotFound
        case notConfigured
        case configured
        case unreadable(String)

        var isConfigured: Bool { self == .configured }
    }

    nonisolated enum SetupError: LocalizedError {
        case settingsNotAnObject
        case statusLineNotACommand

        var errorDescription: String? {
            switch self {
            case .settingsNotAnObject: "~/.claude/settings.json does not contain a JSON object."
            case .statusLineNotACommand: "The existing statusLine entry is not of type \"command\". Please edit it by hand."
            }
        }
    }

    /// Writes the bridge script if it is missing or outdated.
    func installBridge() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bridgeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: bridgeURL, encoding: .utf8), existing == Self.bridgeScript { return }
        try Self.bridgeScript.write(to: bridgeURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgeURL.path)
    }

    func status() -> Status {
        guard FileManager.default.fileExists(atPath: claudeDirectory.path) else { return .claudeCodeNotFound }
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return .notConfigured }
        do {
            let settings = try readSettings()
            return Self.currentCommand(in: settings)?.contains("captrack-statusline") == true ? .configured : .notConfigured
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// The `statusLine` entry CapTrack would write, for users who prefer editing by hand.
    func suggestedSnippet() -> String {
        let existing = (try? readSettings()).flatMap(Self.currentCommand(in:))
        let command = Self.wrappedCommand(existing: existing)
        let json = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        "statusLine": {
          "type": "command",
          "command": "\(json)"
        }
        """
    }

    /// Adds the bridge to `~/.claude/settings.json`, keeping any existing status line command.
    /// A timestamped backup of the previous file is written next to it.
    func configureAutomatically() throws {
        try installBridge()
        var settings = try readSettings()
        var statusLine = settings["statusLine"] as? [String: Any] ?? ["type": "command"]
        if statusLine["type"] as? String != "command" { throw SetupError.statusLineNotACommand }
        let existing = statusLine["command"] as? String
        if existing?.contains("captrack-statusline") == true { return }

        statusLine["command"] = Self.wrappedCommand(existing: existing)
        settings["statusLine"] = statusLine

        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            let backup = claudeDirectory.appending(path: "settings.json.captrack-backup-\(stamp)")
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try writeSettings(settings)
    }

    // MARK: - Helpers

    static func wrappedCommand(existing: String?) -> String {
        guard let existing, !existing.trimmingCharacters(in: .whitespaces).isEmpty else { return bridgeCommand }
        if existing.contains("captrack-statusline") { return existing }
        let quoted = existing.replacingOccurrences(of: "'", with: "'\\''")
        return "\(bridgeCommand) '\(quoted)'"
    }

    static func currentCommand(in settings: [String: Any]) -> String? {
        guard let statusLine = settings["statusLine"] as? [String: Any],
              statusLine["type"] as? String == "command" else { return nil }
        return statusLine["command"] as? String
    }

    func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SetupError.settingsNotAnObject
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try (Self.normalizeFormatting(String(decoding: data, as: UTF8.self)) + "\n")
            .write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    /// Foundation prints `"key" : value`; Claude Code writes `"key": value`.
    static func normalizeFormatting(_ json: String) -> String {
        let keyColon = #/(?m)^(\s*"(?:[^"\\]|\\.)*") : /#
        return json.replacing(keyColon) { "\($0.output.1): " }
    }
}
