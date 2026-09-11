import Foundation
import Observation

/// Watches the JSON file written by the status line bridge and exposes the latest snapshot.
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot?
    /// Human-readable reason the last file read failed, if any.
    private(set) var lastError: String?

    let dataFileURL: URL

    private var watcher: DirectoryWatcher?
    private var pendingReload: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    init(dataFileURL: URL) {
        self.dataFileURL = dataFileURL
    }

    /// Snapshot-only store for previews and rendering.
    static func fixed(_ snapshot: UsageSnapshot) -> UsageStore {
        let store = UsageStore(dataFileURL: URL(fileURLWithPath: "/dev/null"))
        store.snapshot = snapshot
        return store
    }

    func start() {
        let directory = dataFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()

        let watcher = DirectoryWatcher(url: directory) { [weak self] in self?.scheduleReload() }
        watcher.start()
        self.watcher = watcher

        // Safety net: the directory watch is event driven; a slow poll covers missed events
        // (e.g. the directory being recreated) at negligible cost.
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                if watcher.isWatching == false { watcher.start() }
                reload()
            }
        }
    }

    func reload() {
        do {
            let values = try dataFileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let data = try Data(contentsOf: dataFileURL)
            guard !data.isEmpty else { return }
            let parsed = try UsageSnapshot.parse(data, receivedAt: values.contentModificationDate ?? .now)
            if parsed != snapshot { snapshot = parsed }
            lastError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            lastError = nil
        } catch {
            // Keep the last good snapshot; a partially written file will trigger another event.
            lastError = error.localizedDescription
        }
    }

    /// Coalesces bursts of directory events (temp file, rename) into one read.
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
