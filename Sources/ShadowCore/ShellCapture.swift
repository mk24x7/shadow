import Foundation

/// Captures the PATH each shell context ends up with by starting the shell
/// the same way a terminal, a script or launchd would.
public struct ShellCapture: Sendable {
    public static let beginMarker = "__SHADOW_PATH_BEGIN__"
    public static let endMarker = "__SHADOW_PATH_END__"

    public var timeout: TimeInterval
    public var environment: [String: String]
    public var zsh: String
    public var bash: String
    public var sh: String
    /// nil when fish is not installed.
    public var fish: String?

    public init(
        timeout: TimeInterval = 10,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        zsh: String = "/bin/zsh",
        bash: String = "/bin/bash",
        sh: String = "/bin/sh",
        fish: String? = ShellCapture.locateFish()
    ) {
        self.timeout = timeout
        self.environment = environment
        self.zsh = zsh
        self.bash = bash
        self.sh = sh
        self.fish = fish
    }

    /// Contexts that can be captured on this machine.
    public var availableContexts: [ShellContext] {
        ShellContext.allCases.filter { $0 != .fishLogin || fish != nil }
    }

    /// argv that prints the PATH between markers, so banners, prompts and
    /// other rc-file output cannot be mistaken for it.
    public func argv(for context: ShellContext) -> [String]? {
        let posix = "printf '%s' \"\(Self.beginMarker)${PATH}\(Self.endMarker)\""
        switch context {
        case .zshInteractive: return [zsh, "-ilc", posix]
        case .zshLogin: return [zsh, "-lc", posix]
        case .bashInteractive: return [bash, "-ilc", posix]
        case .bashLogin: return [bash, "-lc", posix]
        case .shLogin: return [sh, "-lc", posix]
        case .fishLogin:
            guard let fish else { return nil }
            return [fish, "-lc", "printf '%s' \(Self.beginMarker)(string join : $PATH)\(Self.endMarker)"]
        case .current, .gui: return nil
        }
    }

    /// Captures every requested context concurrently.
    public func capture(_ contexts: [ShellContext]) -> [ContextPath] {
        var results = [ContextPath?](repeating: nil, count: contexts.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: contexts.count) { index in
            let value = capture(contexts[index])
            lock.lock()
            results[index] = value
            lock.unlock()
        }
        return results.compactMap { $0 }
    }

    public func capture(_ context: ShellContext) -> ContextPath {
        switch context {
        case .current:
            return ContextPath(context: .current, path: environment["PATH"] ?? "")
        case .gui:
            return ContextPath(context: .gui, path: Self.guiPath())
        default:
            guard let argv = argv(for: context) else {
                return ContextPath(context: context, path: nil, error: "shell not installed")
            }
            guard let result = ProcessRunner.run(argv, cwd: NSHomeDirectory(), environment: environment, timeout: timeout) else {
                return ContextPath(context: context, path: nil, error: "\(argv[0]) could not be started")
            }
            if let path = Self.extract(result.stdout) {
                return ContextPath(context: context, path: path)
            }
            if result.timedOut {
                return ContextPath(context: context, path: nil, error: "timed out after \(Int(timeout)) s")
            }
            let detail = VersionParser.firstLine(stdout: "", stderr: result.stderr) ?? "exit status \(result.status)"
            return ContextPath(context: context, path: nil, error: "no PATH printed (\(detail))")
        }
    }

    /// The text between the markers, if present.
    public static func extract(_ output: String) -> String? {
        guard let begin = output.range(of: beginMarker),
              let end = output.range(of: endMarker, range: begin.upperBound..<output.endIndex) else { return nil }
        return String(output[begin.upperBound..<end.lowerBound])
    }

    /// The PATH launchd gives apps started from the Dock or Finder:
    /// `launchctl getenv PATH` when someone set it, otherwise launchd's default.
    public static let defaultGUIPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    public static func guiPath() -> String {
        if let result = ProcessRunner.run(["/bin/launchctl", "getenv", "PATH"], timeout: 5), result.status == 0 {
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return defaultGUIPath
    }

    public static func locateFish() -> String? {
        var candidates = ["/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/run/current-system/sw/bin/fish"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += PathResolver.split(path).map { $0 + "/fish" }
        }
        return candidates.first(where: PathResolver.isExecutableFile)
    }
}
