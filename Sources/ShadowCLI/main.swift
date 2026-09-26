import Foundation
import ShadowCore

/// Exit codes: 0 no warnings, 1 runtime error, 2 usage error, 3 warnings or errors found.
enum Exit {
    static let ok: Int32 = 0
    static let failure: Int32 = 1
    static let usage: Int32 = 2
    static let findings: Int32 = 3
}

struct Options {
    var tools: [String] = []
    var all = false
    var shells: [ShellContext]? = nil
    var shellName = "all"
    var directory: String = FileManager.default.currentDirectoryPath
    var json = false
    var color = true
}

let usageText = """
usage: shadow [tool ...] [options]

Explains which copy of each tool runs in each shell, which copies it shadows,
who installed each one, and which rc-file line put the winner first.
Read-only: Shadow never edits rc files or PATH.

Options:
  --all                 Also list tools that are not on any captured PATH
  --shell <name>        zsh, bash, fish, sh, gui, current or all (default: all)
  --dir <path>          Directory for version files (.nvmrc, .tool-versions...)
                        and for running shims (default: current directory)
  --json                One JSON document on stdout
  --no-color            Disable colours (NO_COLOR is also honoured)
  -V, --version         Show the version
  -h, --help            Show this help

Default tools:
  \(Tools.defaultSet.joined(separator: " "))

Exit codes: 0 no warnings, 1 runtime error, 2 usage error,
            3 at least one warning or error finding
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("shadow: \(message)\ntry 'shadow --help'\n".utf8))
    exit(Exit.usage)
}

func contexts(for shell: String) -> [ShellContext]? {
    switch shell {
    case "all": return nil
    case "zsh": return [.zshInteractive, .zshLogin]
    case "bash": return [.bashInteractive, .bashLogin]
    case "fish": return [.fishLogin]
    case "sh": return [.shLogin]
    case "gui": return [.gui]
    case "current": return [.current]
    default: return []
    }
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 0
    func value(for flag: String) -> String {
        index += 1
        guard index < arguments.count else { fail("\(flag) needs a value") }
        return arguments[index]
    }
    var onlyTools = false
    while index < arguments.count {
        var arg = arguments[index]
        var inline: String?
        if !onlyTools, arg.hasPrefix("--"), let eq = arg.firstIndex(of: "=") {
            inline = String(arg[arg.index(after: eq)...])
            arg = String(arg[..<eq])
        }
        if onlyTools || !arg.hasPrefix("-") || arg == "-" {
            guard arg.range(of: #"^[A-Za-z0-9._+@-]+$"#, options: .regularExpression) != nil else {
                fail("'\(arg)' is not a valid tool name")
            }
            if !options.tools.contains(arg) { options.tools.append(arg) }
            index += 1
            continue
        }
        switch arg {
        case "--":
            onlyTools = true
        case "-h", "--help":
            print(usageText)
            exit(Exit.ok)
        case "-V", "--version":
            print("shadow \(ShadowVersion.current)")
            exit(Exit.ok)
        case "--all":
            options.all = true
        case "--json":
            options.json = true
        case "--no-color":
            options.color = false
        case "--shell":
            let name = inline ?? value(for: arg)
            let list = contexts(for: name)
            if let list, list.isEmpty {
                fail("unknown shell '\(name)' (expected zsh, bash, fish, sh, gui, current or all)")
            }
            options.shells = list
            options.shellName = name
        case "--dir":
            let path = inline ?? value(for: arg)
            let expanded = (path as NSString).expandingTildeInPath
            let absolute = expanded.hasPrefix("/")
                ? expanded
                : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded)
            guard PathResolver.isDirectory(absolute) else { fail("--dir: '\(path)' is not a directory") }
            options.directory = PathResolver.realPath(absolute) ?? absolute
        default:
            fail("unknown option '\(arg)'")
        }
        if inline != nil && !["--shell", "--dir"].contains(arg) {
            fail("\(arg) does not take a value")
        }
        index += 1
    }
    return options
}

var options = parse(Array(CommandLine.arguments.dropFirst()))
if ProcessInfo.processInfo.environment["NO_COLOR"] != nil || isatty(STDOUT_FILENO) == 0 {
    options.color = false
}

let capture = ShellCapture()
var wanted = options.shells ?? capture.availableContexts
if options.shellName == "fish" && capture.fish == nil {
    FileHandle.standardError.write(Data("shadow: fish is not installed\n".utf8))
    exit(Exit.failure)
}
wanted = wanted.filter { capture.availableContexts.contains($0) }

let captured = capture.capture(wanted)
let tools = options.tools.isEmpty ? Tools.defaultSet : options.tools
let analyzer = Analyzer()
let report = analyzer.analyze(contexts: captured, tools: tools, directory: options.directory)

if captured.allSatisfy({ $0.path == nil }) {
    FileHandle.standardError.write(Data("shadow: could not capture PATH for any shell\n".utf8))
    if options.json, let text = try? ReportFormatter.json(report) { print(text) }
    exit(Exit.failure)
}

if options.json {
    do {
        print(try ReportFormatter.json(report))
    } catch {
        FileHandle.standardError.write(Data("shadow: could not encode JSON: \(error)\n".utf8))
        exit(Exit.failure)
    }
} else {
    let formatter = ReportFormatter(color: options.color, includeMissing: options.all || !options.tools.isEmpty)
    print(formatter.render(report))
}

if let worst = report.worstSeverity, worst >= .warning {
    exit(Exit.findings)
}
exit(Exit.ok)
