import AppKit
import Darwin
import Foundation

public enum AppServerError: Error, LocalizedError, Sendable, Equatable {
    case executableMissing, launchFailed, timeout, invalidResponse, notSignedIn, queryFailed, unsupportedMethod, cancelled

    public var errorDescription: String? {
        switch self {
        case .executableMissing: L10n.text("Codex executable not found. Open or install Codex Desktop.")
        case .launchFailed: L10n.text("Could not start the Codex App Server.")
        case .timeout: L10n.text("Codex App Server timed out.")
        case .invalidResponse: L10n.text("Codex App Server returned an unsupported response.")
        case .notSignedIn: L10n.text("Sign in through Codex Desktop to read plan limits.")
        case .queryFailed: L10n.text("Codex account information is temporarily unavailable.")
        case .unsupportedMethod: L10n.text("This version of Codex does not support the requested account query.")
        case .cancelled: L10n.text("Codex App Server query was cancelled.")
        }
    }
}

public struct AppServerClient: Sendable {
    private let executable: URL?
    private let timeout: TimeInterval

    public init(executable: URL? = nil, timeout: TimeInterval = 15) {
        self.executable = executable
        self.timeout = max(0.1, timeout)
    }

    public func readQuota(codexHome: URL) async throws -> QuotaSnapshot {
        let runner = AppServerRunner(executable: executable, codexHome: codexHome, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try runner.run()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { runner.cancel() }
    }

    public func readAccountInfo(codexHome: URL) async throws -> AccountInfoSnapshot {
        let runner = AppServerRunner(executable: executable, codexHome: codexHome, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try runner.runAccountInfo()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { runner.cancel() }
    }

    public static func discoverExecutable() -> URL? {
        let manager = FileManager.default
        var apps = [URL(fileURLWithPath: "/Applications/Codex.app"),
                    URL(fileURLWithPath: "/Applications/ChatGPT.app"),
                    manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app"),
                    manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ChatGPT.app")]
        for identifier in ["com.openai.codex", "com.openai.chat"] {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { apps.insert(app, at: 0) }
        }
        let relative = ["Contents/Resources/codex", "Contents/Resources/bin/codex",
                        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                        "Contents/Resources/codex-cli/bin/codex", "Contents/MacOS/codex"]
        for app in apps {
            for path in relative {
                let candidate = app.appendingPathComponent(path)
                if manager.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for path in paths {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent("codex")
            if manager.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

private final class AppServerRunner: @unchecked Sendable {
    private let executable: URL?
    private let codexHome: URL
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var cancelled = false
    private let maxOutputBytes = 1_048_576

    init(executable: URL?, codexHome: URL, timeout: TimeInterval) {
        self.executable = executable
        self.codexHome = codexHome
        self.timeout = timeout
    }

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private func check(_ deadline: TimeInterval) throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw AppServerError.cancelled }
        if ProcessInfo.processInfo.systemUptime >= deadline { throw AppServerError.timeout }
    }

    private enum Query { case quota, accountInfo }
    private enum QueryResult {
        case quota(QuotaSnapshot)
        case accountInfo(AccountInfoSnapshot)
    }

    func run() throws -> QuotaSnapshot {
        guard case .quota(let snapshot) = try run(query: .quota) else { throw AppServerError.invalidResponse }
        return snapshot
    }

    func runAccountInfo() throws -> AccountInfoSnapshot {
        guard case .accountInfo(let snapshot) = try run(query: .accountInfo) else { throw AppServerError.invalidResponse }
        return snapshot
    }

    private func run(query: Query) throws -> QueryResult {
        guard let executable = executable ?? AppServerClient.discoverExecutable() else {
            throw AppServerError.executableMissing
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let help = try runHelp(executable, deadline: deadline)
        var arguments = ["app-server"]
        if help.contains("--listen") { arguments += ["--listen", "stdio://"] }
        else if help.contains("--stdio") { arguments.append("--stdio") }
        arguments += ["-c", "analytics.enabled=false", "-c", "otel.exporter=\"none\"",
                      "-c", "otel.trace_exporter=\"none\"", "-c", "otel.metrics_exporter=\"none\""]
        let (process, input, output) = try launch(executable, arguments: arguments)
        defer { finish(process, input: input, output: output) }
        var buffer = Data()
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "codexmeter", "title": "CodexMeter", "version": "0.3.0"]
        ]], to: input)
        _ = try response(id: 1, process: process, output: output, buffer: &buffer, deadline: deadline)
        try send(["method": "initialized"], to: input)
        try send(["id": 2, "method": "account/read", "params": ["refreshToken": false]], to: input)
        let account = try response(id: 2, process: process, output: output, buffer: &buffer, deadline: deadline)
        guard account["account"] is [String: Any] else { throw AppServerError.notSignedIn }
        switch query {
        case .quota:
            try send(["id": 3, "method": "account/rateLimits/read"], to: input)
            let limits = try response(id: 3, process: process, output: output, buffer: &buffer, deadline: deadline)
            guard let snapshot = QuotaParser.parse(limits) else { throw AppServerError.invalidResponse }
            return .quota(snapshot)
        case .accountInfo:
            // Omitting threadId requests account-wide activity, not per-thread cost estimates.
            try send(["id": 3, "method": "account/usage/read", "params": [:]], to: input)
            let usage = try response(id: 3, process: process, output: output, buffer: &buffer, deadline: deadline)
            guard let snapshot = AccountInfoParser.parse(account: account, usage: usage) else {
                throw AppServerError.invalidResponse
            }
            return .accountInfo(snapshot)
        }
    }

    private func launch(_ executable: URL, arguments: [String]) throws -> (Process, FileHandle, FileHandle) {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome.path
        environment["RUST_LOG"] = "off"
        process.environment = environment
        // Avoid project-scoped configuration discovery in the monitored working directory.
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        do { try process.run() } catch { throw AppServerError.launchFailed }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        return (process, input.fileHandleForWriting, output.fileHandleForReading)
    }

    private func runHelp(_ executable: URL, deadline: TimeInterval) throws -> String {
        let (process, input, output) = try launch(executable, arguments: ["app-server", "--help"])
        defer { finish(process, input: input, output: output) }
        try? input.close()
        var data = Data()
        while true {
            try check(deadline)
            let bytes = try readAvailable(output, deadline: deadline)
            if bytes.isEmpty { break }
            data.append(bytes)
            guard data.count <= maxOutputBytes else { throw AppServerError.invalidResponse }
        }
        while process.isRunning { try check(deadline); usleep(10_000) }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let help = String(data: data, encoding: .utf8), help.contains("app-server") else {
            throw AppServerError.launchFailed
        }
        return help
    }

    private func response(id: Int, process: Process, output: FileHandle, buffer: inout Data,
                          deadline: TimeInterval) throws -> [String: Any] {
        while true {
            try check(deadline)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw AppServerError.invalidResponse
                }
                if object["method"] != nil {
                    // No authentication challenge, tool request, or other interactive action is supported.
                    if object["id"] != nil { throw AppServerError.queryFailed }
                    continue
                }
                guard (object["id"] as? NSNumber)?.intValue == id else { continue }
                if let error = object["error"] as? [String: Any] {
                    if (error["code"] as? NSNumber)?.intValue == -32601 { throw AppServerError.unsupportedMethod }
                    throw AppServerError.queryFailed
                }
                guard let result = object["result"] as? [String: Any] else { throw AppServerError.invalidResponse }
                return result
            }
            let data = try readAvailable(output, deadline: deadline)
            guard !data.isEmpty else { throw AppServerError.queryFailed }
            buffer.append(data)
            guard buffer.count <= maxOutputBytes else { throw AppServerError.invalidResponse }
        }
    }

    private func readAvailable(_ handle: FileHandle, deadline: TimeInterval) throws -> Data {
        while true {
            try check(deadline)
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                throw AppServerError.queryFailed
            }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw AppServerError.queryFailed
            }
            return Data(bytes.prefix(max(0, count)))
        }
    }

    private func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        do { try handle.write(contentsOf: data) } catch { throw AppServerError.queryFailed }
    }

    private func finish(_ process: Process, input: FileHandle, output: FileHandle) {
        try? input.close()
        try? output.close()
        if process.isRunning {
            process.terminate()
            let deadline = ProcessInfo.processInfo.systemUptime + 0.4
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
    }
}
