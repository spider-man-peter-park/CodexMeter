import Foundation
import ServiceManagement
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@Suite(.serialized) struct GeneralExperienceTests {
    @Test func releaseVersionsCompareNumericallyAndRejectMalformedMetadata() throws {
        #expect(try #require(AppReleaseVersion("0.3.5")) < #require(AppReleaseVersion("0.10.0")))
        #expect(AppReleaseVersion("1.0.0")?.description == "1.0.0")
        for text in ["", "v0.3.5", "0.3", "0.3.5.1", " 0.3.5", "0.03.5", "0.3.beta", "-1.0.0"] {
            #expect(AppReleaseVersion(text) == nil)
        }
        #expect(try AppUpdateClient.parse(Data("{\"version\":\"0.3.5\"}".utf8)).description == "0.3.5")
        #expect(throws: AppUpdateError.self) { try AppUpdateClient.parse(Data("{\"version\":\"latest\"}".utf8)) }
        #expect(throws: AppUpdateError.self) { try AppUpdateClient.parse(Data(repeating: 32, count: 16_385)) }
    }

    @Test func subscriptionLabelsUseOnlyReportedPlanIdentity() {
        #expect(SubscriptionPlanLabel.title(for: "plus") == "Plus")
        #expect(SubscriptionPlanLabel.title(for: "prolite") == "Pro Lite")
        #expect(SubscriptionPlanLabel.title(for: "pro") == "Pro")
        #expect(SubscriptionPlanLabel.title(for: "pro_5x") == "Pro 5×")
        #expect(SubscriptionPlanLabel.title(for: "pro10x") == "Pro 10×")
        #expect(SubscriptionPlanLabel.title(for: nil) == L10n.text("Unavailable"))
        #expect(SubscriptionPlanLabel.title(for: "future_plan").contains("Future"))
        #expect(!SubscriptionPlanLabel.title(for: "pro").contains("×"))
    }

    @Test @MainActor func updatePreferencePersistsAndStartsWithNoAutomaticNetwork() throws {
        let suite = "io.github.codexmeter.general-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppUpdates(defaults: defaults, version: "0.3.5")
        #expect(!first.automaticallyChecks)
        first.start()
        #expect(!first.checking)
        first.stop()
        first.automaticallyChecks = true
        let second = AppUpdates(defaults: defaults, version: "0.3.5")
        #expect(second.automaticallyChecks)
        second.automaticallyChecks = false
        #expect(!AppUpdates(defaults: defaults, version: "0.3.5").automaticallyChecks)
        defaults.set(Date(), forKey: "lastUpdateCheck")
        defaults.set("0.3.6", forKey: "latestAppVersion")
        let cached = AppUpdates(defaults: defaults, version: "0.3.5")
        #expect(cached.updateAvailable)
        cached.check()
        #expect(!cached.checking)
    }

    @Test @MainActor func loginStatusRefreshReadsSystemStateWithoutChangingIt() throws {
        let suite = "io.github.codexmeter.general-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/private/tmp/codexmeter-general-tests-empty", forKey: "codexHome")
        let before = SMAppService.mainApp.status
        let model = AppModel(defaults: defaults)
        model.refreshLoginStatus()
        #expect(model.loginEnabled == (before == .enabled))
        #expect(SMAppService.mainApp.status == before)
    }

    @Test @MainActor func manualUpdateChecksCoalesceAndFailuresHaveSafeFeedback() async throws {
        let suite = "io.github.codexmeter.general-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ReleaseProtocol.fixture.configure(status: 200, data: Data("{\"version\":\"0.3.6\"}".utf8))
        let checker = AppUpdates(defaults: defaults, client: AppUpdateClient(session: session), version: "0.3.5")
        checker.check(force: true)
        checker.check(force: true)
        for _ in 0..<200 where checker.checking { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!checker.checking)
        #expect(checker.updateAvailable)
        #expect(ReleaseProtocol.fixture.requests == 1)
        ReleaseProtocol.fixture.configure(status: 503, data: Data("PRIVATE_SERVER_ERROR".utf8))
        checker.check(force: true)
        for _ in 0..<200 where checker.checking { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!checker.checking)
        #expect(checker.warning == "Unable to check for updates. Try again later.")
        checker.check()
        #expect(!checker.checking)
        #expect(ReleaseProtocol.fixture.requests == 1)
        checker.stop()
    }
}

private final class ReleaseFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var data = Data()
    private var count = 0
    var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
    func configure(status: Int, data: Data) {
        lock.lock(); defer { lock.unlock() }
        self.status = status; self.data = data; count = 0
    }
    func response() -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        count += 1; return (status, data)
    }
}

private final class ReleaseProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = ReleaseFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.fixture.response()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
