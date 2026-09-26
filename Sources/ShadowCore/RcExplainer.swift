import Foundation

/// Finds the rc-file line that put a directory on PATH. Best effort: it reads
/// the files the shells read at startup, follows simple `source` lines, tracks
/// plain variable assignments, and recognises the init lines of the common
/// version managers. It never runs anything.
public struct RcExplainer: Sendable {
    public let layout: Layout

    public init(layout: Layout) {
        self.layout = layout
    }

    // MARK: - Files

    /// Startup files per shell family, in the order the shell reads them.
    public func files(for family: String) -> [String] {
        let home = layout.home
        let paths = [layout.rooted("/etc/paths")] + pathsDFiles()
        switch family {
        case "zsh":
            return [layout.rooted("/etc/zshenv"), home + "/.zshenv"] + paths + [
                layout.rooted("/etc/zprofile"), home + "/.zprofile",
                layout.rooted("/etc/zshrc"), home + "/.zshrc", home + "/.zlogin",
            ]
        case "bash":
            return paths + [layout.rooted("/etc/profile"), home + "/.bash_profile", home + "/.bashrc", home + "/.profile"]
        case "sh":
            return paths + [layout.rooted("/etc/profile"), home + "/.profile"]
        case "fish":
            return paths + fishConfD() + [home + "/.config/fish/config.fish"]
        default:
            return []
        }
    }

    /// Every file Shadow reads, zsh order first, without duplicates.
    public var allFiles: [String] {
        var seen = Set<String>()
        return (files(for: "zsh") + files(for: "bash") + files(for: "sh") + files(for: "fish"))
            .filter { seen.insert($0).inserted }
    }

    private func pathsDFiles() -> [String] {
        let dir = layout.rooted("/etc/paths.d")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { dir + "/" + $0 }
    }

    private func fishConfD() -> [String] {
        let dir = layout.home + "/.config/fish/conf.d"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.hasSuffix(".fish") }.sorted().map { dir + "/" + $0 }
    }

    // MARK: - Explain

    public struct Result: Sendable, Equatable {
        public let because: Explanation?
        public let alsoMentioned: [Explanation]
    }

    /// The line most likely responsible for `directory` being where it is on
    /// the PATH of `family` (zsh, bash, sh, fish), plus every other mention.
    public func explain(directory: String, manager: Manager, family: String) -> Result {
        let directory = PathResolver.trimSlash(directory)
        var all: [(match: Match, order: Int)] = []
        var order = 0
        var scanned = Set<String>()
        for file in allFiles {
            for match in scan(file: file, directory: directory, manager: manager, depth: 0, scanned: &scanned) {
                all.append((match, order))
                order += 1
            }
        }
        guard !all.isEmpty else { return Result(because: nil, alsoMentioned: []) }

        let familyFiles = files(for: family)
        let inFamily = all.filter { familyFiles.contains($0.match.topLevelFile) }
        let pool = inFamily.isEmpty ? all : inFamily
        // Within the family, a later prepend or init wins over an earlier one;
        // appends and /etc/paths entries only explain a directory nothing else adds.
        func rank(_ m: Match) -> Int {
            if m.explanation.kind == .pathsFile { return 0 }
            if m.isAppend { return 1 }
            return 2
        }
        let best = pool.max { a, b in
            let ra = rank(a.match), rb = rank(b.match)
            if ra != rb { return ra < rb }
            let fa = familyFiles.firstIndex(of: a.match.topLevelFile) ?? -1
            let fb = familyFiles.firstIndex(of: b.match.topLevelFile) ?? -1
            if fa != fb { return fa < fb }
            return a.order < b.order
        }!
        let others = all.filter { $0.order != best.order }.map(\.match.explanation)
        return Result(because: best.match.explanation, alsoMentioned: others)
    }

    struct Match {
        let explanation: Explanation
        /// The startup file this match was reached from (differs for sourced files).
        let topLevelFile: String
        let isAppend: Bool
    }

    private func scan(file: String, directory: String, manager: Manager, depth: Int,
                      scanned: inout Set<String>, topLevel: String? = nil) -> [Match] {
        guard scanned.insert(file).inserted, let text = RcExplainer.read(file) else { return [] }
        let top = topLevel ?? file
        let isPathsFile = file == layout.rooted("/etc/paths") || file.hasPrefix(layout.rooted("/etc/paths.d") + "/")
        var matches: [Match] = []
        var variables: [String: String] = [:]

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let lineNumber = index + 1

            if isPathsFile {
                if PathResolver.trimSlash(expand(line, variables: [:], directory: directory)) == directory {
                    matches.append(Match(
                        explanation: Explanation(file: file, line: lineNumber, text: line, kind: .pathsFile,
                                                 note: "listed in \(layout.shorten(file)), applied by path_helper"),
                        topLevelFile: top, isAppend: false))
                }
                continue
            }

            let expanded = expand(line, variables: variables, directory: directory)
            if RcExplainer.modifiesPath(line) && RcExplainer.containsDirectory(expanded, directory) {
                matches.append(Match(
                    explanation: Explanation(file: file, line: lineNumber, text: line, kind: .literal, note: nil),
                    topLevelFile: top, isAppend: RcExplainer.isAppend(expanded, directory: directory)))
            } else if let initManager = initLineManager(line, directory: directory, manager: manager) {
                matches.append(Match(
                    explanation: Explanation(file: file, line: lineNumber, text: line, kind: .managerInit,
                                             note: "added by \(initManager) init"),
                    topLevelFile: top, isAppend: false))
            } else if depth < 2, let sourced = sourcedFile(line, variables: variables, relativeTo: file) {
                matches += scan(file: sourced, directory: directory, manager: manager, depth: depth + 1,
                                scanned: &scanned, topLevel: top)
            }

            if let (name, value) = RcExplainer.assignment(line), name != "PATH", name != "path" {
                variables[name] = expand(value, variables: variables, directory: directory)
            }
        }
        return matches
    }

    // MARK: - Line analysis

    static func read(_ path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size < 512 * 1024 else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// True when the line changes PATH in sh, zsh or fish syntax.
    static func modifiesPath(_ line: String) -> Bool {
        let patterns = [
            #"(^|[\s;&|])(export\s+|typeset\s+(-[a-zA-Z]+\s+)*|declare\s+(-[a-zA-Z]+\s+)*)?PATH\+?="#,
            #"(^|[\s;&|])path\+?=\("#,
            #"(^|[\s;&|])path\[[^\]]*\]="#,
            #"(^|[\s;&|])fish_add_path\b"#,
            #"(^|[\s;&|])set\s+(-[a-zA-Z]+\s+)*(PATH|fish_user_paths)\b"#,
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
    }

    /// True when `text` names `directory` as a whole PATH element.
    static func containsDirectory(_ text: String, _ directory: String) -> Bool {
        let boundaries: Set<Character> = [":", "\"", "'", " ", "\t", ")", ";"]
        for candidate in [directory, directory + "/"] {
            var searchStart = text.startIndex
            while let range = text.range(of: candidate, range: searchStart..<text.endIndex) {
                let beforeOK = range.lowerBound == text.startIndex
                    || [":", "\"", "'", " ", "\t", "(", "="].contains(text[text.index(before: range.lowerBound)])
                let afterOK = range.upperBound == text.endIndex || boundaries.contains(text[range.upperBound])
                if beforeOK && afterOK { return true }
                searchStart = text.index(after: range.lowerBound)
            }
        }
        return false
    }

    /// True when the directory is added after the existing PATH.
    static func isAppend(_ text: String, directory: String) -> Bool {
        if text.range(of: #"path\+=\("#, options: .regularExpression) != nil { return true }
        if text.range(of: #"fish_add_path\s+(-[a-zA-Z]*a|--append)"#, options: .regularExpression) != nil { return true }
        guard let dirRange = text.range(of: directory) else { return false }
        for token in ["$PATH", "${PATH}", "$path", "${path}", "$fish_user_paths"] {
            if let tokenRange = text.range(of: token), tokenRange.lowerBound < dirRange.lowerBound {
                return true
            }
        }
        return false
    }

    /// `NAME=value`, `export NAME=value`, `set -gx NAME value`.
    static func assignment(_ line: String) -> (String, String)? {
        let shell = #"^(?:export\s+|typeset\s+(?:-[a-zA-Z]+\s+)*|declare\s+(?:-[a-zA-Z]+\s+)*|local\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$"#
        let fish = #"^set\s+(?:-[a-zA-Z]+\s+)*([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$"#
        for pattern in [shell, fish] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else { continue }
            var value = String(line[valueRange]).trimmingCharacters(in: .whitespaces)
            // Drop a trailing comment and one level of quotes.
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            return (String(line[nameRange]), value)
        }
        return nil
    }

    /// Expands $HOME, ~, $(brew --prefix) and tracked variables.
    func expand(_ text: String, variables: [String: String], directory: String) -> String {
        var result = text
        let brewPrefix = layout.homebrewPrefixes.first { directory.hasPrefix($0 + "/") } ?? layout.homebrewPrefixes.first ?? "/opt/homebrew"

        if let regex = try? NSRegularExpression(pattern: #"\$\(\s*(?:\S*/)?brew\s+--prefix\s+([A-Za-z0-9@._+-]+)\s*\)"#) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: brewPrefix) + "/opt/$1")
        }
        if let regex = try? NSRegularExpression(pattern: #"\$\(\s*(?:\S*/)?brew\s+--prefix\s*\)"#) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: brewPrefix))
        }

        var vars = variables
        if vars["HOME"] == nil { vars["HOME"] = layout.home }
        if vars["HOMEBREW_PREFIX"] == nil { vars["HOMEBREW_PREFIX"] = brewPrefix }
        if vars["XDG_DATA_HOME"] == nil { vars["XDG_DATA_HOME"] = layout.home + "/.local/share" }
        if vars["XDG_CONFIG_HOME"] == nil { vars["XDG_CONFIG_HOME"] = layout.home + "/.config" }
        // Longest names first so $HOMEBREW_PREFIX is not read as $HOME + BREW_PREFIX.
        for name in vars.keys.sorted(by: { $0.count > $1.count }) {
            let value = vars[name]!
            result = result.replacingOccurrences(of: "${\(name)}", with: value)
            if let regex = try? NSRegularExpression(pattern: "\\$\(name)(?![A-Za-z0-9_])") {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result),
                    withTemplate: NSRegularExpression.escapedTemplate(for: value))
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"(^|[\s:"'=(])~(?=/|$|[\s:"')])"#) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: layout.home))
        }
        return result
    }

    /// The file a `source file` or `. file` line reads, when it is a plain
    /// file under the home directory and not a manager or framework script.
    private func sourcedFile(_ line: String, variables: [String: String], relativeTo file: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^(?:source|\.)\s+["']?([^"'\s;|&]+)["']?\s*(?:$|;|&&|\|\|)"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        var path = expand(String(line[range]), variables: variables, directory: "")
        if !path.hasPrefix("/") {
            path = ((file as NSString).deletingLastPathComponent as NSString).appendingPathComponent(path)
        }
        guard path.hasPrefix(layout.home + "/") else { return nil }
        let skipped = ["/.oh-my-zsh/", "/.nvm/", "/.sdkman/", "/.asdf/", "/.zinit/", "/.antigen/",
                       "/.zprezto/", "/node_modules/", "/.fzf", "/.iterm2", "/.cargo/env", "/.rustup/"]
        if skipped.contains(where: { path.contains($0) }) { return nil }
        return path
    }

    /// Manager whose init line adds `directory`, if `line` is one.
    func initLineManager(_ line: String, directory: String, manager: Manager) -> String? {
        let home = layout.home
        let inits: [(name: String, pattern: String, applies: Bool)] = [
            ("nvm", #"nvm\.sh"#, directory.hasPrefix(home + "/.nvm/")),
            ("fnm", #"fnm\s+env"#, directory.contains("fnm_multishells") || directory.contains("/fnm/")),
            ("Volta", #"VOLTA_HOME"#, directory.hasPrefix(home + "/.volta/")),
            ("asdf", #"asdf\.(sh|fish)|ASDF_DATA_DIR"#, directory.hasPrefix(home + "/.asdf/")),
            ("mise", #"(mise|rtx)\s+activate"#, directory.contains("/mise/") || directory.contains("/rtx/")),
            ("pyenv", #"pyenv\s+init"#, directory.hasPrefix(home + "/.pyenv/")),
            ("rbenv", #"rbenv\s+init"#, directory.hasPrefix(home + "/.rbenv/")),
            ("jenv", #"jenv\s+init"#, directory.hasPrefix(home + "/.jenv/")),
            ("nodenv", #"nodenv\s+init"#, directory.hasPrefix(home + "/.nodenv/")),
            ("SDKMAN!", #"sdkman-init\.sh"#, directory.hasPrefix(home + "/.sdkman/")),
            ("Conda", #"conda\s+(initialize|shell)|conda\.(sh|fish)|conda"\s+"shell"#, manager.id == "conda"),
            ("rustup", #"\.cargo/env"#, directory == home + "/.cargo/bin"),
            ("Homebrew", #"brew["']?\s+shellenv"#,
             layout.homebrewPrefixes.contains { directory == $0 + "/bin" || directory == $0 + "/sbin" }),
            ("Bun", #"BUN_INSTALL|\.bun/_bun"#, directory.hasPrefix(home + "/.bun/")),
            ("OrbStack", #"orbstack/shell/init"#, directory.contains("/.orbstack/")),
        ]
        for entry in inits where entry.applies {
            if line.range(of: entry.pattern, options: .regularExpression) != nil { return entry.name }
        }
        return nil
    }
}
