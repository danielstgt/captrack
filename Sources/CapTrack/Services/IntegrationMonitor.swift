import Foundation
import Observation

/// Keeps the Claude Code connection status current.
///
/// The status is re-read whenever `~/.claude` changes (Claude Code and CapTrack both
/// write settings.json atomically, which shows up as a directory event), when the
/// popover or the settings window opens, on request, and every minute as a fallback.
@Observable
final class IntegrationMonitor {
    let integration: ClaudeCodeIntegration
    private(set) var status: ClaudeCodeIntegration.Status
    /// The `statusLine` entry for manual setup, derived from the current settings.json.
    private(set) var snippet: String
    private(set) var lastChecked: Date

    private var watcher: DirectoryWatcher?
    private var pendingRefresh: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    init(integration: ClaudeCodeIntegration) {
        self.integration = integration
        status = integration.status()
        snippet = integration.suggestedSnippet()
        lastChecked = .now
    }

    func start() {
        let watcher = DirectoryWatcher(url: integration.claudeDirectory) { [weak self] in self?.scheduleRefresh() }
        watcher.start()
        self.watcher = watcher

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                if watcher.isWatching == false { watcher.start() }
                refresh()
            }
        }
    }

    func refresh() {
        let newStatus = integration.status()
        if newStatus != status { status = newStatus }
        let newSnippet = integration.suggestedSnippet()
        if newSnippet != snippet { snippet = newSnippet }
        lastChecked = .now
    }

    func configureAutomatically() throws {
        defer { refresh() }
        try integration.configureAutomatically()
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
