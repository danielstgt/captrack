import Foundation
import Observation

/// Looks up the latest GitHub release. Never downloads or installs anything by itself;
/// the user is sent to the release in the browser.
@Observable
final class UpdateChecker {
    nonisolated struct Release: Sendable, Equatable {
        var version: String
        var pageURL: URL
        var downloadURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate(checkedAt: Date)
        case available(Release)
        case failed(String)
    }

    private(set) var state: State = .idle
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Returns the release if a newer version exists, nil otherwise.
    @discardableResult
    func check() async -> Release? {
        if state == .checking { return nil }
        state = .checking
        defer { preferences.lastUpdateCheck = .now }
        do {
            let release = try await fetchLatestRelease()
            if Self.isVersion(release.version, newerThan: AppInfo.version) {
                state = .available(release)
                return release
            }
            state = .upToDate(checkedAt: .now)
        } catch {
            state = .failed(error.localizedDescription)
        }
        return nil
    }

    /// Automatic check on launch: at most once a day, and only when enabled.
    func checkInBackgroundIfDue() async -> Release? {
        guard preferences.automaticUpdateChecks else { return nil }
        if let last = preferences.lastUpdateCheck, Date.now.timeIntervalSince(last) < 24 * 3600 { return nil }
        guard let release = await check() else { return nil }
        return release.version == preferences.skippedVersion ? nil : release
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: AppInfo.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse }
        guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            throw UpdateError.badResponse
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets
            .compactMap { $0["browser_download_url"] as? String }
            .first { $0.hasSuffix(".zip") }
            .flatMap(URL.init(string:))
        return Release(version: Self.normalize(tag), pageURL: page, downloadURL: zip)
    }

    nonisolated enum UpdateError: LocalizedError {
        case badResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse: "Unexpected response from GitHub."
            case .http(404): "No release found on GitHub yet."
            case .http(let code): "GitHub answered with HTTP \(code)."
            }
        }
    }

    // MARK: - Version comparison

    /// Strips a leading "v" and any pre-release suffix: "v1.2.0-beta" -> "1.2.0".
    nonisolated static func normalize(_ tag: String) -> String {
        var version = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        return String(version.split(separator: "-", maxSplits: 1).first ?? "")
    }

    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = components(of: candidate), b = components(of: current)
        guard !a.isEmpty else { return false }
        guard !b.isEmpty else { return true }   // "dev" builds always count as older
        let length = max(a.count, b.count)
        for index in 0..<length {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private nonisolated static func components(of version: String) -> [Int] {
        let parts = normalize(version).split(separator: ".").map { Int($0) }
        return parts.contains(nil) ? [] : parts.compactMap { $0 }
    }
}
