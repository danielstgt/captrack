import Foundation

/// Reports changes inside a directory (files written, renamed or removed) on the main queue.
///
/// If the directory itself disappears the watcher stops and reports once more; the
/// owner can call `start()` again once the directory exists. Watchers are meant to live
/// for the whole app run, so there is no automatic teardown.
final class DirectoryWatcher {
    let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    var isWatching: Bool { source != nil }

    /// Starts watching; returns false if the directory cannot be opened (yet).
    @discardableResult
    func start() -> Bool {
        if source != nil { return true }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                stop()
            }
            onChange()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
