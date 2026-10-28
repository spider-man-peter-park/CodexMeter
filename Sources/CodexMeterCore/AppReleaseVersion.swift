import Foundation

public struct AppReleaseVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    private let parts: [Int]
    public var description: String { parts.map(String.init).joined(separator: ".") }

    public init?(_ text: String) {
        let values = text.split(separator: ".", omittingEmptySubsequences: false)
        guard values.count == 3 else { return nil }
        var numbers: [Int] = []
        for value in values {
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  value.count == 1 || value.first != "0", let number = Int(value) else { return nil }
            numbers.append(number)
        }
        parts = numbers
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

public enum AppUpdateError: Error { case unavailable, invalidMetadata }

public struct AppUpdateClient: Sendable {
    public static let feedURL = URL(string: "https://raw.githubusercontent.com/spider-man-peter-park/CodexMeter/main/updates.json")!
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: configuration)
    }

    public func latestVersion() async throws -> AppReleaseVersion {
        var request = URLRequest(url: Self.feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexMeter", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw AppUpdateError.unavailable }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> AppReleaseVersion {
        struct Feed: Decodable { let version: String }
        guard data.count <= 16_384, let feed = try? JSONDecoder().decode(Feed.self, from: data),
              let version = AppReleaseVersion(feed.version) else { throw AppUpdateError.invalidMetadata }
        return version
    }
}
