import Foundation

/// Output of a finished (or killed) child process.
public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
}

/// Runs a program from an argv array (never through a shell string built by
/// Shadow) with a hard timeout. Output is collected incrementally, so a
/// grandchild that inherits the pipes and outlives the child (a prompt daemon
/// started by an interactive rc file, for example) cannot block the caller.
public enum ProcessRunner {
    /// - Parameters:
    ///   - argv: absolute executable path followed by its arguments.
    ///   - cwd: working directory, or nil for the current one.
    ///   - environment: full environment, or nil to inherit.
    ///   - timeout: seconds before the child is terminated.
    /// - Returns: nil when the executable could not be started.
    public static func run(
        _ argv: [String],
        cwd: String? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval = 5
    ) -> ProcessResult? {
        guard let executable = argv.first else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }
        if let environment {
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collector = OutputCollector()
        let eof = DispatchGroup()
        eof.enter()
        eof.enter()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                eof.leave()
            } else {
                collector.append(data, toStdout: true)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                eof.leave()
            } else {
                collector.append(data, toStdout: false)
            }
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }

        // Give the readers a moment to drain; a lingering grandchild may keep
        // the write end open forever, so never wait unbounded.
        if eof.wait(timeout: .now() + 1) == .timedOut {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
        }

        let status = process.isRunning ? -1 : process.terminationStatus
        let (out, err) = collector.strings()
        return ProcessResult(status: status, stdout: out, stderr: err, timedOut: timedOut)
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()

    func append(_ data: Data, toStdout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if toStdout { out.append(data) } else { err.append(data) }
    }

    func strings() -> (String, String) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}
