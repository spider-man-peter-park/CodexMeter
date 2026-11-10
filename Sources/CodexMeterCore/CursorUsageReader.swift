import Foundation
import CoreFoundation

/// Reads the signed-in Cursor account's dashboard; it never refreshes or persists its credentials.
public actor CursorUsageReader {
    private let databaseURL: URL
    private let session: URLSession
    private let credentialReader: @Sendable (URL) throws -> String?
    private let passwordReader: @Sendable (String) -> String?
    private static let redirectPolicy = CursorRedirectPolicy()

    public init(databaseURL: URL? = nil, session: URLSession? = nil,
                credentialReader: (@Sendable (URL) throws -> String?)? = nil,
                passwordReader: (@Sendable (String) -> String?)? = nil) {
        self.databaseURL = databaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        self.credentialReader = credentialReader ?? { try CursorLocalCredentials.read(database: $0) }
        self.passwordReader = passwordReader ?? { CursorLocalCredentials.password(account: $0) }
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    public func readUsage(now: Date = Date()) async -> ProviderUsageResult {
        do {
            try Task.checkCancellation()
            guard let stored = try credentialReader(databaseURL), !stored.isEmpty else {
                throw CursorCredentialFailure.missingToken
            }
            let token = try CursorLocalCredentials.decode(stored, passwordReader: passwordReader)
            let user = try Self.userID(token: token, now: now)
            let cookie = "WorkosCursorSessionToken=\(user)%3A%3A\(token)"
            try Task.checkCancellation()
            let data = try await fetch(path: "/api/usage-summary", cookie: cookie)
            let summary = try Self.object(data)
            try Task.checkCancellation()
            let weekly: [String: Any]?
            do {
                let weeklyData = try await fetch(path: "/api/dashboard/get-sand-usage-status", cookie: cookie, post: true)
                weekly = try Self.object(weeklyData)
            }
            catch { weekly = nil }
            try Task.checkCancellation()
            guard let snapshot = Self.project(summary: summary, weekly: weekly, now: now) else {
                return result(.unsupported, "Cursor did not report a usable allowance. Open its usage dashboard for details.")
            }
            return ProviderUsageResult(provider: .cursor, status: .ready, snapshot: snapshot,
                message: snapshot.periodLabel == "Weekly"
                    ? "Cursor account-wide weekly included usage. Additional spending is separate."
                    : "Cursor account-wide billing-cycle allowance. Dollar values describe included usage, not an invoice.")
        } catch CursorCredentialFailure.missingDatabase {
            return result(.notFound, "Cursor local sign-in data was not found. Open Cursor, sign in, then refresh.")
        } catch CursorCredentialFailure.protectedToken {
            return result(.signInRequired, "Cursor saved sign-in is protected and could not be read without a permission prompt.")
        } catch CursorCredentialFailure.unavailableDatabase {
            return result(.unavailable, "Cursor local sign-in data is temporarily unreadable. Open Cursor and try again.")
        } catch is CursorCredentialFailure {
            return result(.signInRequired, "Cursor sign-in is missing or expired. Sign in through Cursor, then refresh.")
        } catch CursorRequestFailure.notSignedIn {
            return result(.signInRequired, "Cursor rejected the saved session. Sign in through Cursor, then refresh.")
        } catch is CancellationError {
            return result(.unavailable, "Cursor usage refresh was cancelled.")
        } catch {
            return result(.unavailable, "Cursor usage could not be refreshed. Try again later.")
        }
    }

    private func result(_ status: ProviderConnectionStatus, _ message: String) -> ProviderUsageResult {
        ProviderUsageResult(provider: .cursor, status: status, message: message)
    }

    private static func userID(token: String, now: Date) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !token.isEmpty, token.utf8.count <= 65_536,
              token.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else {
            throw CursorCredentialFailure.invalidToken
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else { throw CursorCredentialFailure.invalidToken }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let object = try? Self.object(data),
              let subject = object["sub"] as? String,
              let user = subject.split(separator: "|", omittingEmptySubsequences: false).last, !user.isEmpty,
              user.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }),
              let expiration = number(object["exp"]), expiration > now.timeIntervalSince1970 + 60 else {
            throw CursorCredentialFailure.invalidToken
        }
        return String(user)
    }

    private func fetch(path: String, cookie: String, post: Bool = false) async throws -> Data {
        let url = URL(string: "https://cursor.com" + path)!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: post ? 5 : 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexMeter", forHTTPHeaderField: "User-Agent")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if post {
            request.httpMethod = "POST"
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await session.data(for: request, delegate: Self.redirectPolicy)
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https", response.url?.host == "cursor.com" else { throw CursorRequestFailure.invalid }
        if response.statusCode == 401 || response.statusCode == 403 { throw CursorRequestFailure.notSignedIn }
        guard response.statusCode == 200, data.count <= 1_048_576 else { throw CursorRequestFailure.invalid }
        return data
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_048_576,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorRequestFailure.invalid
        }
        return value
    }

    private static func project(summary: [String: Any], weekly: [String: Any]?, now: Date) -> ProviderUsageSnapshot? {
        let membership = (summary["membershipType"] as? String)?.lowercased() ?? ""
        let isUnified = membership.hasPrefix("unified_") || boolean(weekly?["isUnified"]) == true
        var snapshot = ProviderUsageSnapshot(provider: .cursor, scope: .accountPeriod, sampledAt: now)
        if isUnified {
            guard let weekly, boolean(weekly["isUnified"]) == true,
                  boolean(weekly["includedLimitZero"]) != true,
                  boolean(weekly["includedLimitZero"]) == false || boolean(weekly["hasNonZeroIncludedLimit"]) == true,
                  let used = number(weekly["usagePercent"]), used >= 0,
                  let reset = date(weekly["nextResetTimestampUtc"]), reset > now else { return nil }
            let start = date(weekly["currentPeriodStart"])
            guard start.map({ $0 <= now && $0 < reset }) ?? true else { return nil }
            snapshot.periodLabel = "Weekly"
            snapshot.periodStart = start
            snapshot.resetAt = reset
            snapshot.usedPercent = min(100, used)
            return snapshot
        }
        guard !membership.isEmpty || summary["individualUsage"] is [String: Any],
              let usage = summary["individualUsage"] as? [String: Any] else { return nil }
        let plan = usage["plan"] as? [String: Any]
        let overall = usage["overall"] as? [String: Any]
        let selected = plan ?? overall
        guard let selected, boolean(selected["enabled"]) != false else { return nil }
        let start = date(summary["billingCycleStart"])
        let reset = date(summary["billingCycleEnd"])
        guard start.map({ $0 <= now }) ?? true, reset.map({ $0 > now }) ?? true,
              start.flatMap({ start in reset.map { start < $0 } }) ?? true else { return nil }
        let used = nonnegative(selected["used"])
        let limit = nonnegative(selected["limit"])
        let percentage = nonnegative(selected["totalPercentUsed"])
            ?? used.flatMap { used in limit.flatMap { $0 > 0 ? used / $0 * 100 : nil } }
        guard percentage != nil || used.map({ $0 > 0 }) == true || limit.map({ $0 > 0 }) == true else { return nil }
        snapshot.periodLabel = "Billing cycle"
        snapshot.periodStart = start
        snapshot.resetAt = reset
        snapshot.usedPercent = percentage.map { min(100, $0) }
        snapshot.costUSD = used.map { $0 / 100 }
        snapshot.limitUSD = limit.flatMap { $0 > 0 ? $0 / 100 : nil }
        snapshot.isPartial = percentage == nil || start == nil || reset == nil
        return snapshot
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func nonnegative(_ value: Any?) -> Double? {
        number(value).flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }
}

private enum CursorRequestFailure: Error { case invalid, notSignedIn }

private final class CursorRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "cursor.com" ? request : nil)
    }
}
