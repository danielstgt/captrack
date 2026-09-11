import Foundation

enum AppInfo {
    static let name = "CapTrack"
    static let repository = "danielstgt/captrack"
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// Marketing version from the bundle, or "dev" when running unbundled (`swift run`).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }
}
