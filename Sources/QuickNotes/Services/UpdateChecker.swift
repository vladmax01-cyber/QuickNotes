import AppKit
import Foundation

struct QuickNotesRelease: Equatable {
    let version: String
    let pageURL: URL
}

@MainActor
final class UpdateChecker: ObservableObject {
    private enum Key {
        static let lastAttempt = "lastUpdateCheckAttempt"
        static let lastSuccess = "lastSuccessfulUpdateCheck"
        static let dismissedVersion = "dismissedUpdateVersion"
        static let cachedVersion = "cachedUpdateVersion"
        static let cachedURL = "cachedUpdateURL"
    }

    @Published private(set) var availableRelease: QuickNotesRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var checkMessage: String?

    private let defaults: UserDefaults
    private let currentVersion: String
    private let releasesURL = URL(string:
        "https://api.github.com/repos/vladmax01-cyber/QuickNotes/releases/latest")!

    var visibleRelease: QuickNotesRelease? {
        guard let release = availableRelease,
              defaults.string(forKey: Key.dismissedVersion) != release.version else { return nil }
        return release
    }

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
        if let version = defaults.string(forKey: Key.cachedVersion),
           let value = defaults.string(forKey: Key.cachedURL),
           let url = URL(string: value),
           Self.isTrustedReleaseURL(url),
           Self.urlTagMatches(version, url: url),
           Self.isNewer(version, than: currentVersion) {
            availableRelease = QuickNotesRelease(version: version, pageURL: url)
        }
    }

    func checkIfNeeded() {
        let lastSuccess = defaults.object(forKey: Key.lastSuccess) as? Date ?? .distantPast
        let lastAttempt = defaults.object(forKey: Key.lastAttempt) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastSuccess) >= 24 * 60 * 60,
              Date().timeIntervalSince(lastAttempt) >= 2 * 60 * 60 else { return }
        checkNow()
    }

    func checkNow() {
        guard !isChecking else { return }
        isChecking = true
        checkMessage = nil
        defaults.set(Date(), forKey: Key.lastAttempt)
        Task {
            defer { isChecking = false }
            do {
                var request = URLRequest(url: releasesURL)
                request.timeoutInterval = 10
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      response.statusCode == 200 else { throw UpdateError.unavailable }
                let release = try Self.parseRelease(data)
                defaults.set(Date(), forKey: Key.lastSuccess)
                availableRelease = Self.isNewer(release.version, than: currentVersion)
                    ? release : nil
                defaults.set(availableRelease?.version, forKey: Key.cachedVersion)
                defaults.set(availableRelease?.pageURL.absoluteString, forKey: Key.cachedURL)
                checkMessage = availableRelease == nil ? "Quick Notes is up to date." : nil
            } catch {
                checkMessage = "Could not check for updates. Try again later."
            }
        }
    }

    func dismiss() {
        guard let release = availableRelease else { return }
        defaults.set(release.version, forKey: Key.dismissedVersion)
        objectWillChange.send()
    }

    func openRelease() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(release.pageURL)
    }

    nonisolated static func isNewer(_ candidate: String, than installed: String) -> Bool {
        func components(_ version: String) -> [Int]? {
            let value = version.hasPrefix("v") || version.hasPrefix("V")
                ? String(version.dropFirst()) : version
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.count <= 4 else { return nil }
            let numbers = parts.compactMap { Int($0) }
            return numbers.count == parts.count ? numbers : nil
        }
        guard let candidateParts = components(candidate),
              let installedParts = components(installed) else { return false }
        for index in 0..<max(candidateParts.count, installedParts.count) {
            let left = index < candidateParts.count ? candidateParts[index] : 0
            let right = index < installedParts.count ? installedParts[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    nonisolated static func parseRelease(_ data: Data) throws -> QuickNotesRelease {
        struct Asset: Decodable { let name: String }
        struct Feed: Decodable {
            let tagName: String
            let pageURL: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case pageURL = "html_url"
                case draft, prerelease, assets
            }
        }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard !feed.draft, !feed.prerelease,
              feed.assets.contains(where: { $0.name.lowercased().hasSuffix(".dmg") }),
              isTrustedReleaseURL(feed.pageURL) else {
            throw UpdateError.unavailable
        }
        let version = feed.tagName.hasPrefix("v") || feed.tagName.hasPrefix("V")
            ? String(feed.tagName.dropFirst()) : feed.tagName
        guard !version.isEmpty, urlTagMatches(version, url: feed.pageURL) else {
            throw UpdateError.unavailable
        }
        return QuickNotesRelease(version: version, pageURL: feed.pageURL)
    }

    nonisolated private static func isTrustedReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.path.hasPrefix("/vladmax01-cyber/QuickNotes/releases/tag/")
    }

    nonisolated private static func urlTagMatches(_ version: String, url: URL) -> Bool {
        url.lastPathComponent == version || url.lastPathComponent == "v\(version)"
    }

    private enum UpdateError: Error { case unavailable }
}
