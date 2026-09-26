import Foundation

/// A place a PATH can come from: a shell started a particular way, the
/// process environment, or the environment launchd gives GUI apps.
public enum ShellContext: String, Codable, CaseIterable, Sendable, Comparable {
    case zshInteractive = "zsh-il"
    case zshLogin = "zsh-l"
    case bashInteractive = "bash-il"
    case bashLogin = "bash-l"
    case fishLogin = "fish-l"
    case shLogin = "sh-l"
    case current = "current"
    case gui = "gui"

    /// Short label for tables and output.
    public var label: String {
        switch self {
        case .zshInteractive: return "zsh -il"
        case .zshLogin: return "zsh -l"
        case .bashInteractive: return "bash -il"
        case .bashLogin: return "bash -l"
        case .fishLogin: return "fish -l"
        case .shLogin: return "sh -l"
        case .current: return "current"
        case .gui: return "gui"
        }
    }

    /// Longer description for the app.
    public var summary: String {
        switch self {
        case .zshInteractive: return "zsh, interactive login (a new Terminal tab)"
        case .zshLogin: return "zsh, login but not interactive (scripts run with zsh -l)"
        case .bashInteractive: return "bash, interactive login"
        case .bashLogin: return "bash, login but not interactive"
        case .fishLogin: return "fish, login"
        case .shLogin: return "sh, login (POSIX scripts)"
        case .current: return "the environment Shadow itself was started with"
        case .gui: return "GUI apps launched from the Dock or Finder (Xcode, VS Code)"
        }
    }

    /// Shell family used to pick relevant rc files.
    public var family: String {
        switch self {
        case .zshInteractive, .zshLogin: return "zsh"
        case .bashInteractive, .bashLogin: return "bash"
        case .fishLogin: return "fish"
        case .shLogin: return "sh"
        case .current: return "current"
        case .gui: return "gui"
        }
    }

    public static func < (lhs: ShellContext, rhs: ShellContext) -> Bool {
        let order = ShellContext.allCases
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// The PATH captured for one context, or why it could not be captured.
public struct ContextPath: Codable, Sendable, Equatable {
    public let context: ShellContext
    public let path: String?
    public let error: String?

    public init(context: ShellContext, path: String?, error: String? = nil) {
        self.context = context
        self.path = path
        self.error = error
    }

    /// PATH entries in order. Empty entries are dropped.
    public var entries: [String] {
        guard let path else { return [] }
        return PathResolver.split(path)
    }
}

/// Who installed a binary.
public struct Manager: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Switches between versions of one language (nvm, pyenv, mise...).
        case versionManager
        /// General package manager (Homebrew, MacPorts, Nix).
        case packageManager
        /// A vendor installer or bundle (python.org, Docker Desktop, JDK).
        case vendor
        /// Binaries the user installed with a language tool (go install, cargo install).
        case user
        /// Shipped with macOS or with Xcode / the Command Line Tools.
        case system
        case unknown
    }

    public let id: String
    public let name: String
    public let kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// Anything a user deliberately installed, as opposed to what macOS ships.
    public var isManaged: Bool { kind != .system && kind != .unknown }

    public static let nvm = Manager(id: "nvm", name: "nvm", kind: .versionManager)
    public static let fnm = Manager(id: "fnm", name: "fnm", kind: .versionManager)
    public static let volta = Manager(id: "volta", name: "Volta", kind: .versionManager)
    public static let asdf = Manager(id: "asdf", name: "asdf", kind: .versionManager)
    public static let mise = Manager(id: "mise", name: "mise", kind: .versionManager)
    public static let pyenv = Manager(id: "pyenv", name: "pyenv", kind: .versionManager)
    public static let rbenv = Manager(id: "rbenv", name: "rbenv", kind: .versionManager)
    public static let jenv = Manager(id: "jenv", name: "jenv", kind: .versionManager)
    public static let nodenv = Manager(id: "nodenv", name: "nodenv", kind: .versionManager)
    public static let sdkman = Manager(id: "sdkman", name: "SDKMAN!", kind: .versionManager)
    public static let rustup = Manager(id: "rustup", name: "rustup", kind: .versionManager)
    public static let conda = Manager(id: "conda", name: "Conda", kind: .versionManager)
    public static let homebrew = Manager(id: "homebrew", name: "Homebrew", kind: .packageManager)
    public static let macports = Manager(id: "macports", name: "MacPorts", kind: .packageManager)
    public static let nix = Manager(id: "nix", name: "Nix", kind: .packageManager)
    public static let pythonOrg = Manager(id: "python.org", name: "Python.org installer", kind: .vendor)
    public static let dockerDesktop = Manager(id: "docker-desktop", name: "Docker Desktop", kind: .vendor)
    public static let jetbrains = Manager(id: "jetbrains-toolbox", name: "JetBrains Toolbox", kind: .vendor)
    public static let jdkBundle = Manager(id: "jdk", name: "JDK bundle", kind: .vendor)
    public static let goInstaller = Manager(id: "go-installer", name: "Go installer", kind: .vendor)
    public static let bunInstaller = Manager(id: "bun", name: "Bun installer", kind: .vendor)
    public static let denoInstaller = Manager(id: "deno", name: "Deno installer", kind: .vendor)
    public static let pnpmStandalone = Manager(id: "pnpm", name: "pnpm standalone", kind: .vendor)
    public static let goInstall = Manager(id: "go-install", name: "go install", kind: .user)
    public static let cargoInstall = Manager(id: "cargo-install", name: "cargo install", kind: .user)
    public static let localBin = Manager(id: "local-bin", name: "~/.local/bin", kind: .user)
    public static let usrLocal = Manager(id: "usr-local", name: "manual install (/usr/local)", kind: .user)
    public static let xcode = Manager(id: "xcode", name: "Xcode / Command Line Tools", kind: .system)
    public static let javaStub = Manager(id: "macos-java-stub", name: "macOS java stub", kind: .system)
    public static let system = Manager(id: "system", name: "macOS system", kind: .system)
    public static let unknown = Manager(id: "unknown", name: "unknown", kind: .unknown)
}

/// One executable found on a PATH.
public struct Copy: Codable, Sendable, Equatable {
    /// Path as found (PATH directory + tool name).
    public let path: String
    /// The PATH directory it was found in.
    public let directory: String
    /// realpath of `path`.
    public let realPath: String
    public let manager: Manager
    /// Keg, version directory or environment name, when the location tells us.
    public let detail: String?
    /// True when the file dispatches to another binary chosen at run time.
    public let isShim: Bool
    /// For dispatchers Shadow can resolve (xcrun, java_home), the binary it runs.
    public let shimTarget: String?
    public var version: String?
    public var versionLine: String?
    public var versionError: String?
    /// Contexts whose PATH contains this copy, and those where it is the winner.
    public var presentIn: [ShellContext]
    public var winsIn: [ShellContext]

    public init(
        path: String, directory: String, realPath: String, manager: Manager, detail: String?,
        isShim: Bool, shimTarget: String?, version: String? = nil, versionLine: String? = nil,
        versionError: String? = nil, presentIn: [ShellContext] = [], winsIn: [ShellContext] = []
    ) {
        self.path = path
        self.directory = directory
        self.realPath = realPath
        self.manager = manager
        self.detail = detail
        self.isShim = isShim
        self.shimTarget = shimTarget
        self.version = version
        self.versionLine = versionLine
        self.versionError = versionError
        self.presentIn = presentIn
        self.winsIn = winsIn
    }

    /// "Homebrew (node@20)", "nvm (v20.1.0)", "macOS system".
    public var managerLabel: String {
        if let detail, !detail.isEmpty { return "\(manager.name) (\(detail))" }
        return manager.name
    }
}

/// An rc-file line that puts a directory on PATH.
public struct Explanation: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// The line names the directory (after $HOME, ~ and variable expansion).
        case literal
        /// The line runs a manager's init (eval, source) that adds the directory.
        case managerInit
        /// A line of /etc/paths or /etc/paths.d, applied by path_helper.
        case pathsFile
    }

    public let file: String
    public let line: Int
    public let text: String
    public let kind: Kind
    /// Human note, e.g. "added by nvm init".
    public let note: String?

    public init(file: String, line: Int, text: String, kind: Kind, note: String?) {
        self.file = file
        self.line = line
        self.text = text
        self.kind = kind
        self.note = note
    }
}

/// A per-directory version file (.nvmrc, .python-version, .tool-versions...).
public struct VersionFile: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let language: String
    /// The version string requested, as written.
    public let value: String

    public init(name: String, path: String, language: String, value: String) {
        self.name = name
        self.path = path
        self.language = language
        self.value = value
    }
}

public enum Severity: String, Codable, Sendable, Comparable {
    case info
    case warning
    case error

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
}

/// Something worth knowing about the PATH set-up.
public struct Finding: Codable, Sendable, Equatable {
    public enum Rule: String, Codable, Sendable {
        case duplicateManagers
        case shimBeforeHomebrew
        case systemWinsOverManaged
        case missingPathDirectory
        case duplicatePathEntry
        case loginInteractiveMismatch
        case guiPathLacksManager
        case shellsDisagree
        case versionFileIgnored
        case versionFileMismatch
        case captureFailed
    }

    public let severity: Severity
    public let rule: Rule
    public let tool: String?
    public let message: String

    public init(severity: Severity, rule: Rule, tool: String?, message: String) {
        self.severity = severity
        self.rule = rule
        self.tool = tool
        self.message = message
    }
}

/// The winner of one context, used to show where contexts disagree.
public struct ContextWinner: Codable, Sendable, Equatable {
    public let context: ShellContext
    /// Path of the winning copy, or nil when the tool is not on that PATH.
    public let path: String?

    public init(context: ShellContext, path: String?) {
        self.context = context
        self.path = path
    }
}

/// Everything Shadow knows about one tool.
public struct ToolReport: Codable, Sendable {
    public let tool: String
    public let language: String
    /// Winner on the primary context's PATH.
    public let winner: Copy?
    /// Every copy: primary-PATH order first, then copies only other contexts see.
    public let copies: [Copy]
    public let because: Explanation?
    /// Other rc lines that also mention the winner's directory.
    public let alsoMentioned: [Explanation]
    /// Winner per captured context.
    public let contextWinners: [ContextWinner]
    public let findings: [Finding]

    /// Copies other than the winner.
    public var shadowed: [Copy] {
        copies.filter { $0.path != winner?.path }
    }

    /// Contexts whose winner differs from the primary winner.
    public var differences: [ContextWinner] {
        contextWinners.filter { $0.path != winner?.path }
    }

    public var isFound: Bool { !copies.isEmpty }
}

public struct ReportCounts: Codable, Sendable, Equatable {
    public let toolsChecked: Int
    public let toolsFound: Int
    public let shadowedCopies: Int
    public let errors: Int
    public let warnings: Int
    public let infos: Int
}

/// A complete analysis.
public struct Report: Codable, Sendable {
    public let shadowVersion: String
    public let generatedAt: Date
    public let directory: String
    public let primaryContext: ShellContext
    public let contexts: [ContextPath]
    public let versionFiles: [VersionFile]
    public let tools: [ToolReport]
    /// Findings about PATH itself rather than one tool.
    public let findings: [Finding]

    public var allFindings: [Finding] {
        findings + tools.flatMap(\.findings)
    }

    public var counts: ReportCounts {
        let all = allFindings
        return ReportCounts(
            toolsChecked: tools.count,
            toolsFound: tools.filter(\.isFound).count,
            shadowedCopies: tools.reduce(0) { $0 + $1.shadowed.count },
            errors: all.filter { $0.severity == .error }.count,
            warnings: all.filter { $0.severity == .warning }.count,
            infos: all.filter { $0.severity == .info }.count
        )
    }

    /// Worst severity present, if any finding exists.
    public var worstSeverity: Severity? {
        allFindings.map(\.severity).max()
    }
}

extension Copy: Identifiable {
    public var id: String { path }
}

extension ToolReport: Identifiable {
    public var id: String { tool }
}
