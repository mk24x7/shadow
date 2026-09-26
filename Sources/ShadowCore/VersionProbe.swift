import Foundation

/// Parses the version a tool prints.
public enum VersionParser {
    /// The first non-empty line of the output that looks like it carries a version.
    public static func firstLine(stdout: String, stderr: String) -> String? {
        for text in [stdout, stderr] {
            let line = text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            if let line { return line }
        }
        return nil
    }

    /// Extracts a version number from one line of `--version` output:
    ///
    ///     v20.1.0                               -> 20.1.0
    ///     Python 3.12.1                         -> 3.12.1
    ///     openjdk version "21.0.2" 2024-01-16   -> 21.0.2
    ///     go version go1.22.0 darwin/arm64      -> 1.22.0
    ///     ruby 3.3.0p0 (2023-12-25 ...)         -> 3.3.0
    ///     rustc 1.77.0 (aedd173a2 2024-03-17)   -> 1.77.0
    ///     PHP 8.3.1 (cli) (built: ...)          -> 8.3.1
    ///     swift-driver version: 1.115 Apple Swift version 6.3 -> 6.3
    public static func parse(_ line: String) -> String? {
        if let range = line.range(of: "Swift version ") {
            if let v = firstMatch(#"\d+(?:\.\d+)+"#, in: String(line[range.upperBound...])) { return v }
        }
        // Quoted version first (java prints `version "21.0.2"`, or `"21"`).
        if let quoted = firstMatch(#""\d+(?:\.\d+)*[^"]*""#, in: line) {
            let inner = quoted.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let v = firstMatch(#"\d+(?:\.\d+)*"#, in: inner) { return v }
        }
        if let v = firstMatch(#"\d+(?:\.\d+)+"#, in: line) { return v }
        // A bare major version after the word "version".
        if let range = line.range(of: "version", options: .caseInsensitive),
           let v = firstMatch(#"\d+"#, in: String(line[range.upperBound...])) {
            return v
        }
        return nil
    }

    /// True when a version-file request such as "20", "v20.1", "3.12.1",
    /// "python-3.12" or "openjdk-21" is satisfied by `actual`. Returns nil
    /// when the request cannot be compared ("lts/*", "system", "latest").
    public static func satisfies(requested: String, actual: String) -> Bool? {
        guard let firstDigit = requested.firstIndex(where: \.isNumber) else { return nil }
        let wanted = String(requested[firstDigit...])
        guard let wantedVersion = firstMatch(#"\d+(?:\.\d+)*"#, in: wanted) else { return nil }
        let want = wantedVersion.split(separator: ".").map(String.init)
        let have = actual.split(separator: ".").map(String.init)
        guard want.count <= have.count else {
            // "3.12.0" requested, "3.12" reported: compare what both have.
            return Array(want.prefix(have.count)) == have && want.dropFirst(have.count).allSatisfy { $0 == "0" }
        }
        return Array(have.prefix(want.count)) == want
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}

/// Runs `<binary> --version` (or the tool's equivalent) and caches the answer.
public final class VersionProbe: @unchecked Sendable {
    public struct Result: Equatable, Sendable {
        public let version: String?
        public let line: String?
        public let error: String?
    }

    public let timeout: TimeInterval
    private let lock = NSLock()
    private var cache: [String: Result] = [:]

    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    /// - Parameters:
    ///   - executable: the file to run (a shim's own path, so it sees its argv[0]).
    ///   - cacheKey: realpath for real binaries; shims are keyed by path and cwd
    ///     because their answer depends on both.
    public func probe(tool: String, executable: String, cacheKey: String, cwd: String, pathVariable: String?) -> Result {
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var environment = ProcessInfo.processInfo.environment
        if let pathVariable { environment["PATH"] = pathVariable }
        let argv = [executable] + Tools.versionArguments(for: tool)
        let result: Result
        if let output = ProcessRunner.run(argv, cwd: cwd, environment: environment, timeout: timeout) {
            let line = VersionParser.firstLine(stdout: output.stdout, stderr: output.stderr)
            if output.timedOut {
                result = Result(version: nil, line: line, error: "timed out after \(Int(timeout)) s")
            } else if let line, let version = VersionParser.parse(line) {
                result = Result(version: version, line: line, error: nil)
            } else if output.status != 0 {
                result = Result(version: nil, line: line, error: line ?? "exited with status \(output.status)")
            } else {
                result = Result(version: nil, line: line, error: "no version in output")
            }
        } else {
            result = Result(version: nil, line: nil, error: "could not be started")
        }

        lock.lock()
        cache[cacheKey] = result
        lock.unlock()
        return result
    }

    public func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
