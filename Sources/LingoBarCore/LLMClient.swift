import Foundation

public enum ModelChoice: String, CaseIterable, Sendable {
    case sonnet55 = "claude-sonnet-5-5"
    case haiku55 = "claude-haiku-5-5"

    public var displayName: String {
        switch self {
        case .sonnet55: return "Sonnet 5.5"
        case .haiku55: return "Haiku 5.5"
        }
    }

    /// Thinking control differs per model: Sonnet 5.5 rejects MAX_THINKING_TOKENS=0
    /// with a 400, so it gets `--effort low`; Haiku 5.5 gets thinking disabled via env.
    public var extraArguments: [String] {
        switch self {
        case .sonnet55: return ["--effort", "low"]
        case .haiku55: return []
        }
    }

    public var extraEnvironment: [String: String] {
        switch self {
        case .sonnet55: return [:]
        case .haiku55: return ["MAX_THINKING_TOKENS": "0"]
        }
    }
}

/// Backend-agnostic text completion. A future API-key backend implements this too.
public protocol LLMClient: Sendable {
    func complete(system: String, user: String, model: ModelChoice) async throws -> String
}

public enum LLMError: LocalizedError {
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut(TimeInterval)
    case processFailed(status: Int32, message: String)
    case reportedError(String)
    case unreadableOutput(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Claude CLI not found at \(path). Set it with: defaults write io.github.if-route.lingobar claudePath /path/to/claude"
        case .launchFailed(let message):
            return "Could not start Claude CLI: \(message)"
        case .timedOut(let seconds):
            return "Claude CLI did not answer within \(Int(seconds)) seconds."
        case .processFailed(let status, let message):
            return "Claude CLI exited with status \(status): \(message)"
        case .reportedError(let message):
            return "Claude returned an error: \(message)"
        case .unreadableOutput(let snippet):
            return "Could not read Claude CLI output: \(snippet)"
        }
    }
}

/// Runs `claude -p` with the prompt on stdin. Uses the user's OAuth login, so
/// `--bare` must not be passed.
public struct ClaudeCLIClient: LLMClient {
    public let executablePath: String
    public let timeout: TimeInterval

    public init(executablePath: String, timeout: TimeInterval = 30) {
        self.executablePath = executablePath
        self.timeout = timeout
    }

    public func arguments(system: String, model: ModelChoice) -> [String] {
        [
            "-p",
            "--model", model.rawValue,
            "--no-session-persistence",
            "--strict-mcp-config",
            "--setting-sources", "",
            "--tools", "",
            "--output-format", "json",
            "--system-prompt", system
        ] + model.extraArguments
    }

    func environment(model: ModelChoice) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Don't let a parent Claude Code session or a stray setting leak into the child.
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "MAX_THINKING_TOKENS"] {
            env.removeValue(forKey: key)
        }
        let home = NSHomeDirectory()
        let basePath = "/usr/bin:/bin:/usr/sbin:/sbin:\(home)/.local/bin"
        env["PATH"] = env["PATH"].map { "\($0):\(basePath)" } ?? basePath
        env["HOME"] = env["HOME"] ?? home
        env.merge(model.extraEnvironment) { _, new in new }
        return env
    }

    public func complete(system: String, user: String, model: ModelChoice) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LLMError.executableNotFound(executablePath)
        }
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("LingoBar-cli", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let output = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: executablePath),
            arguments: arguments(system: system, model: model),
            environment: environment(model: model),
            workingDirectory: workDir,
            stdin: Data(user.utf8),
            timeout: timeout
        )
        if output.timedOut {
            throw LLMError.timedOut(timeout)
        }
        let stdout = String(decoding: output.stdout, as: UTF8.self)
        let stderr = String(decoding: output.stderr, as: UTF8.self)

        if let result = try Self.parseResult(stdout) {
            return result
        }
        if output.status != 0 {
            let message = [stderr, stdout].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "no output"
            throw LLMError.processFailed(status: output.status, message: ModelOutputParser.snippet(message))
        }
        throw LLMError.unreadableOutput(ModelOutputParser.snippet(stdout.isEmpty ? stderr : stdout))
    }

    /// Parses `--output-format json`: a single result object, or (with --verbose)
    /// an array of events whose last `result` event holds the answer.
    public static func parseResult(_ stdout: String) throws -> String? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let event: [String: Any]?
        if let object = json as? [String: Any] {
            event = object
        } else if let array = json as? [[String: Any]] {
            event = array.last { ($0["type"] as? String) == "result" }
        } else {
            event = nil
        }
        guard let event else { return nil }
        let result = event["result"] as? String
        if (event["is_error"] as? Bool) == true || ((event["subtype"] as? String).map { $0 != "success" } ?? false) {
            throw LLMError.reportedError(result ?? (event["subtype"] as? String) ?? "unknown error")
        }
        return result
    }
}

enum ProcessRunner {
    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: Data
        let timedOut: Bool
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var stdout = Data()
        var stderr = Data()
        var timedOut = false
    }

    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        stdin: Data,
        timeout: TimeInterval
    ) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        let state = State()
        let readers = DispatchGroup()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                process.terminationHandler = { finished in
                    readers.notify(queue: .global()) {
                        state.lock.lock()
                        let output = Output(status: finished.terminationStatus, stdout: state.stdout, stderr: state.stderr, timedOut: state.timedOut)
                        state.lock.unlock()
                        continuation.resume(returning: output)
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LLMError.launchFailed(error.localizedDescription))
                    return
                }

                readers.enter()
                DispatchQueue.global().async {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    state.lock.lock(); state.stdout = data; state.lock.unlock()
                    readers.leave()
                }
                readers.enter()
                DispatchQueue.global().async {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    state.lock.lock(); state.stderr = data; state.lock.unlock()
                    readers.leave()
                }
                DispatchQueue.global().async {
                    // Throwing API: the child may exit before reading stdin (EPIPE).
                    try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
                    try? inPipe.fileHandleForWriting.close()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    state.lock.lock(); state.timedOut = true; state.lock.unlock()
                    process.terminate()
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
