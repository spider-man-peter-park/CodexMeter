import CommonCrypto
import Foundation
import SQLite3
import Testing
@testable import CodexMeterCore

@Suite(.serialized) struct CursorUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let legacy = Data(#"{"billingCycleStart":"2027-01-01T00:00:00Z","billingCycleEnd":"2027-02-01T00:00:00Z","membershipType":"pro","individualUsage":{"plan":{"enabled":true,"used":1500,"limit":5000,"totalPercentUsed":30},"onDemand":{"used":500,"limit":10000}}}"#.utf8)
    private let weekly = Data(#"{"isUnified":true,"includedLimitZero":false,"usagePercent":35,"currentPeriodStart":"2027-01-13T00:00:00Z","nextResetTimestampUtc":"2027-01-20T00:00:00Z"}"#.utf8)

    private func token(expiration: Double = 1_900_000_000, subject: String = "auth0|fixture-user") throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["sub": subject, "exp": expiration])
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        // This deliberately has no valid signature and can authenticate only the URLProtocol fixture.
        return "eyJhbGciOiJub25lIn0." + payload + ".fixture-signature"
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CursorFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func read(_ data: Data, weekly: Data? = nil, automaticToken: String? = nil,
                      status: Int = 200, weeklyStatus: Int = 404) async throws -> ProviderUsageResult {
        let value = try automaticToken ?? token()
        CursorFixtureProtocol.fixture.configure(summary: data, status: status, weekly: weekly,
            weeklyStatus: weekly == nil ? weeklyStatus : 200)
        let session = session()
        defer { session.invalidateAndCancel() }
        let reader = CursorUsageReader(session: session, credentialReader: { _ in value })
        return await reader.readUsage(now: now)
    }

    @Test func legacyAllowanceUsesItsAccountBillingCycleAndCents() async throws {
        let result = try await read(legacy)
        #expect(result.status == .ready)
        let snapshot = try #require(result.snapshot)
        #expect(snapshot.provider == .cursor && snapshot.scope == .accountPeriod)
        #expect(snapshot.periodLabel == "Billing cycle")
        #expect(snapshot.usedPercent == 30)
        #expect(snapshot.costUSD == 15 && snapshot.limitUSD == 50)
        #expect(snapshot.periodStart == (try Date.ISO8601FormatStyle().parse("2027-01-01T00:00:00Z")))
        #expect(snapshot.resetAt == (try Date.ISO8601FormatStyle().parse("2027-02-01T00:00:00Z")))
        #expect(snapshot.totalTokens == nil)
        #expect(!snapshot.isPartial)
        let requests = CursorFixtureProtocol.fixture.requests
        #expect(requests.map { $0.url?.host } == ["cursor.com", "cursor.com"])
        #expect(requests.first?.value(forHTTPHeaderField: "Cookie")?.hasPrefix("WorkosCursorSessionToken=fixture-user%3A%3A") == true)
        #expect(requests.last?.httpMethod == "POST")
        #expect(requests.last?.value(forHTTPHeaderField: "Origin") == "https://cursor.com")
        #expect(requests.last?.httpBody == Data("{}".utf8) || requests.last?.httpBodyStream != nil)
    }

    @Test func fractionalPercentagesAreAlreadyPercentageUnits() async throws {
        let data = Data(#"{"membershipType":"pro","individualUsage":{"plan":{"totalPercentUsed":0.36}}}"#.utf8)
        let result = try await read(data)
        #expect(result.snapshot?.usedPercent == 0.36)
        #expect(result.snapshot?.limitUSD == nil)
        #expect(result.snapshot?.isPartial == true)
    }

    @Test func ratioFallbackPreservesKnownZeroAndDoesNotUseBreakdownAsTheLimit() async throws {
        let zero = Data(#"{"membershipType":"pro","individualUsage":{"plan":{"used":0,"limit":2000}}}"#.utf8)
        let measured = try await read(zero)
        #expect(measured.snapshot?.usedPercent == 0)
        #expect(measured.snapshot?.costUSD == 0)
        #expect(measured.snapshot?.limitUSD == 20)
        let noCap = Data(#"{"membershipType":"pro","individualUsage":{"plan":{"used":1500,"breakdown":{"total":5000},"autoPercentUsed":10,"apiPercentUsed":90}}}"#.utf8)
        let unknown = try await read(noCap)
        #expect(unknown.snapshot?.costUSD == 15)
        #expect(unknown.snapshot?.usedPercent == nil)
        #expect(unknown.snapshot?.limitUSD == nil)
        #expect(unknown.snapshot?.isPartial == true)
    }

    @Test func absentFalseAndMalformedFieldsDoNotInventZeroUsage() async throws {
        for json in [
            #"{"membershipType":"pro","individualUsage":{"plan":{"used":0,"limit":0}}}"#,
            #"{"membershipType":"pro","individualUsage":{"plan":{"used":-1,"limit":-1,"totalPercentUsed":false}}}"#,
            #"{"membershipType":"pro","individualUsage":{"plan":{"enabled":false,"used":20,"limit":100}}}"#,
            #"{"unexpected":"envelope"}"#
        ] {
            let result = try await read(Data(json.utf8))
            #expect(result.status == .unsupported)
            #expect(result.snapshot == nil)
        }
    }

    @Test func unifiedWeeklyPoolOverridesTheLegacyMonthlyValues() async throws {
        let summary = Data(#"{"membershipType":"unified_premium","limitType":"user","billingCycleEnd":"2027-02-01T00:00:00Z","individualUsage":{"plan":{"used":0,"limit":2000,"totalPercentUsed":0},"onDemand":{"used":5000,"limit":10000}}}"#.utf8)
        let result = try await read(summary, weekly: weekly)
        #expect(result.status == .ready)
        #expect(result.snapshot?.periodLabel == "Weekly")
        #expect(result.snapshot?.usedPercent == 35)
        #expect(result.snapshot?.resetAt == (try Date.ISO8601FormatStyle().parse("2027-01-20T00:00:00Z")))
        // Monthly additional spend cannot be presented under the weekly allowance's period.
        #expect(result.snapshot?.costUSD == nil && result.snapshot?.limitUSD == nil)
    }

    @Test func unifiedAccountsDoNotFallBackToStaleMonthlyNumbersWhenWeeklyDataIsUnavailable() async throws {
        let summary = Data(#"{"membershipType":"unified_premium","individualUsage":{"plan":{"used":0,"limit":2000,"totalPercentUsed":0}}}"#.utf8)
        for response in [nil,
            Data(#"{"isUnified":true,"includedLimitZero":false,"usagePercent":20,"nextResetTimestampUtc":"2027-01-01T00:00:00Z"}"#.utf8),
            Data(#"{"isUnified":true,"includedLimitZero":true,"usagePercent":20,"nextResetTimestampUtc":"2027-01-20T00:00:00Z"}"#.utf8)] {
            let result = try await read(summary, weekly: response)
            #expect(result.status == .unsupported)
            #expect(result.snapshot == nil)
        }
    }

    @Test func failureOfOptionalWeeklyDataKeepsValidLegacyAllowance() async throws {
        let result = try await read(legacy, weeklyStatus: 503)
        #expect(result.status == .ready)
        #expect(result.snapshot?.usedPercent == 30)
    }

    @Test func expiredMalformedAndMissingTokensNeverMakeANetworkRequest() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for value in [nil, "", "not-a-jwt", try token(expiration: now.timeIntervalSince1970 + 59),
                      try token(subject: "auth0|unsafe;cookie")] {
            CursorFixtureProtocol.fixture.configure(summary: legacy)
            let reader = CursorUsageReader(session: session, credentialReader: { _ in value })
            let result = await reader.readUsage(now: now)
            #expect(result.status == .signInRequired)
            #expect(result.snapshot == nil)
            #expect(CursorFixtureProtocol.fixture.requests.isEmpty)
        }
    }

    @Test func rejectedOrUnavailableSessionsDoNotRetainAFormerAccountSnapshot() async throws {
        for status in [401, 403, 500] {
            let result = try await read(legacy, status: status)
            #expect(result.status == (status == 500 ? .unavailable : .signInRequired))
            #expect(result.snapshot == nil)
            #expect(CursorFixtureProtocol.fixture.requests.count == 1)
        }
    }

    @Test func protectedCredentialsFailClosedWhenKeychainAccessIsUnavailable() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let stored = try protectedToken(token())
        CursorFixtureProtocol.fixture.configure(summary: legacy)
        let reader = CursorUsageReader(session: session, credentialReader: { _ in stored }, passwordReader: { _ in nil })
        let result = await reader.readUsage(now: now)
        #expect(result.status == .signInRequired)
        #expect(result.snapshot == nil)
        #expect(!result.message.contains(stored))
        #expect(CursorFixtureProtocol.fixture.requests.isEmpty)
    }

    @Test func protectedTokenSupportsCurrentAndLegacySafeStorageAccounts() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let stored = try protectedToken(token())
        for account in ["Cursor Key", "Cursor"] {
            CursorFixtureProtocol.fixture.configure(summary: legacy)
            let reader = CursorUsageReader(session: session, credentialReader: { _ in stored },
                passwordReader: { name in name == account ? "fixture-safe-storage" : nil })
            #expect((await reader.readUsage(now: now)).status == .ready)
        }
    }

    @Test func sqliteReadsOnlyTheAccessTokenAndDoesNotRewriteTheDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for encoding in [String.Encoding.utf8, .utf16LittleEndian] {
            let database = directory.appendingPathComponent(UUID().uuidString + ".vscdb")
            let value = try token()
            try createDatabase(database, token: #require(value.data(using: encoding)))
            let before = try Data(contentsOf: database)
            let session = session()
            defer { session.invalidateAndCancel() }
            CursorFixtureProtocol.fixture.configure(summary: legacy)
            let reader = CursorUsageReader(databaseURL: database, session: session)
            #expect((await reader.readUsage(now: now)).status == .ready)
            #expect(try Data(contentsOf: database) == before)
            #expect(!FileManager.default.fileExists(atPath: database.path + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: database.path + "-shm"))
        }
    }

    @Test func activeWalCredentialsAreReadWithoutIgnoringUncheckpointedState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("state.vscdb")
        var writer: OpaquePointer?
        try #require(sqlite3_open(database.path, &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        try #require(sqlite3_exec(writer, "PRAGMA journal_mode=WAL; CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value BLOB)", nil, nil, nil) == SQLITE_OK)
        try insertToken(#require(token().data(using: .utf8)), connection: writer)
        #expect(FileManager.default.fileExists(atPath: database.path + "-wal"))
        let session = session()
        defer { session.invalidateAndCancel() }
        CursorFixtureProtocol.fixture.configure(summary: legacy)
        #expect((await CursorUsageReader(databaseURL: database, session: session).readUsage(now: now)).status == .ready)
    }

    @Test func missingDatabaseIsReportedWithoutCreatingACredentialStore() async {
        let database = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/state.vscdb")
        let result = await CursorUsageReader(databaseURL: database).readUsage(now: now)
        #expect(result.status == .notFound)
        #expect(result.snapshot == nil)
        #expect(!FileManager.default.fileExists(atPath: database.path))
    }

    private func createDatabase(_ url: URL, token: Data) throws {
        var connection: OpaquePointer?
        try #require(sqlite3_open(url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        try #require(sqlite3_exec(connection,
            "CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value BLOB); INSERT INTO ItemTable VALUES('cursorAuth/refreshToken','must-not-read')", nil, nil, nil) == SQLITE_OK)
        try insertToken(token, connection: connection)
    }

    private func insertToken(_ data: Data, connection: OpaquePointer?) throws {
        try data.withUnsafeBytes { bytes in
            var statement: OpaquePointer?
            try #require(sqlite3_prepare_v2(connection, "INSERT INTO ItemTable VALUES('cursorAuth/accessToken', ?)", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            try #require(sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), nil) == SQLITE_OK)
            try #require(sqlite3_step(statement) == SQLITE_DONE)
        }
    }

    private func protectedToken(_ token: String) throws -> String {
        let password = "fixture-safe-storage"
        let salt = Data("saltysalt".utf8)
        var key = Data(count: 16)
        _ = key.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordBytes.count - 1, saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, keyBytes.bindMemory(to: UInt8.self).baseAddress, 16)
                }
            }
        }
        let input = Data(token.utf8)
        let iv = Data(repeating: 0x20, count: 16)
        var output = Data(count: input.count + 16)
        let capacity = output.count
        var count = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, 16, ivBytes.baseAddress, inputBytes.baseAddress, input.count,
                            outputBytes.baseAddress, capacity, &count)
                    }
                }
            }
        }
        try #require(status == kCCSuccess)
        output.count = count
        return "cursor-safe-storage:v1:" + (Data("v10".utf8) + output).base64EncodedString()
    }
}

private final class CursorFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var summary = Data()
    private var summaryStatus = 200
    private var weekly: Data?
    private var weeklyStatus = 404
    private var captured: [URLRequest] = []
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    func configure(summary: Data, status: Int = 200, weekly: Data? = nil, weeklyStatus: Int = 404) {
        lock.lock(); defer { lock.unlock() }
        self.summary = summary; summaryStatus = status
        self.weekly = weekly; self.weeklyStatus = weeklyStatus; captured.removeAll()
    }
    func respond(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        captured.append(request)
        return request.url?.path == "/api/usage-summary" ? (summaryStatus, summary) : (weeklyStatus, weekly ?? Data("{}".utf8))
    }
}

private final class CursorFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = CursorFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.fixture.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
