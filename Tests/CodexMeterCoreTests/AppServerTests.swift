import Darwin
import Foundation
import Testing
@testable import CodexMeterCore

struct AppServerTests {
    private func fixture(_ body: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        let script = """
        #!/usr/bin/env python3
        import json, os, sys, time, signal
        if '--help' in sys.argv:
            print('codex app-server --listen <URL>')
            sys.exit(0)
        \(body)
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (directory, executable)
    }

    @Test func testReadOnlyProtocolAndTelemetryOverrides() async throws {
        let (directory, executable) = try fixture("""
        methods = []
        for line in sys.stdin:
            request = json.loads(line)
            methods.append(request['method'])
            with open(os.path.join(os.path.dirname(__file__), 'methods.json'), 'w') as record:
                json.dump({'methods': methods, 'args': sys.argv, 'home': os.environ.get('CODEX_HOME')}, record)
            if request['method'] == 'initialize':
                result = {}
            elif request['method'] == 'initialized':
                continue
            elif request['method'] == 'account/read':
                assert request['params']['refreshToken'] is False
                result = {'account': {'type': 'chatgpt'}}
            elif request['method'] == 'account/rateLimits/read':
                result = {'rateLimits': {'primary': {'usedPercent': 18, 'windowDurationMins': 300, 'resetsAt': 12345}}}
            else:
                raise RuntimeError('Unexpected method')
            print(json.dumps({'id': request['id'], 'result': result}), flush=True)
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let quota = try await AppServerClient(executable: executable, timeout: 5).readQuota(codexHome: directory)
        #expect(quota.fiveHour?.remainingPercent == 82)
        #expect(quota.source == .appServer)
        let data = try Data(contentsOf: directory.appendingPathComponent("methods.json"))
        let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(record["methods"] as? [String] == ["initialize", "initialized", "account/read", "account/rateLimits/read"])
        #expect(record["home"] as? String == directory.path)
        let arguments = try #require(record["args"] as? [String])
        #expect(arguments.contains("analytics.enabled=false"))
        #expect(arguments.contains("otel.exporter=\"none\""))
    }

    @Test func testFailureDoesNotLeakServerMessage() async throws {
        let (directory, executable) = try fixture("""
        request = json.loads(sys.stdin.readline())
        print(json.dumps({'id': request['id'], 'error': {'message': 'PRIVATE_SERVER_DETAIL'}}), flush=True)
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await AppServerClient(executable: executable, timeout: 5).readQuota(codexHome: directory)
            Issue.record("Expected a sanitized failure")
        } catch {
            #expect(error as? AppServerError == .queryFailed)
            #expect(!(error.localizedDescription.contains("PRIVATE_SERVER_DETAIL")))
        }
    }

    @Test func testTimeoutKillsStubbornProcess() async throws {
        let (directory, executable) = try fixture("""
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        with open(os.path.join(os.path.dirname(__file__), 'pid'), 'w') as record:
            record.write(str(os.getpid()))
        time.sleep(120)
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date()
        do {
            _ = try await AppServerClient(executable: executable, timeout: 1).readQuota(codexHome: directory)
            Issue.record("Expected timeout")
        } catch { #expect(error as? AppServerError == .timeout) }
        #expect(Date().timeIntervalSince(start) < 4)
        let pid = try #require(Int32(String(contentsOf: directory.appendingPathComponent("pid"), encoding: .utf8)))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test func testUnsignedAccountDoesNotStartLogin() async throws {
        let (directory, executable) = try fixture("""
        for line in sys.stdin:
            request = json.loads(line)
            if request['method'] == 'initialized':
                continue
            result = {'account': None} if request['method'] == 'account/read' else {}
            print(json.dumps({'id': request['id'], 'result': result}), flush=True)
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await AppServerClient(executable: executable, timeout: 5).readQuota(codexHome: directory)
            Issue.record("Expected signed-out state")
        } catch { #expect(error as? AppServerError == .notSignedIn) }
    }
}
