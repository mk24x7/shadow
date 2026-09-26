import Foundation

/// The rules that turn resolved copies into findings. Pure functions over
/// already-collected data so each rule is testable on its own.
public enum FindingRules {
    // MARK: - PATH-level

    /// Missing directories, duplicated entries and contexts that could not be captured.
    public static func pathFindings(contexts: [ContextPath], directoryExists: (String) -> Bool = FindingRules.entryExists) -> [Finding] {
        var findings: [Finding] = []

        for context in contexts where context.path == nil {
            findings.append(Finding(
                severity: .warning, rule: .captureFailed, tool: nil,
                message: "Could not capture PATH for \(context.context.label): \(context.error ?? "unknown error")."))
        }

        var missing: [(String, [ShellContext])] = []
        var duplicates: [(String, [ShellContext])] = []
        for context in contexts {
            var seen = Set<String>()
            for entry in context.entries {
                if !seen.insert(entry).inserted {
                    append(&duplicates, entry, context.context)
                } else if !directoryExists(entry) {
                    append(&missing, entry, context.context)
                }
            }
        }
        for (dir, where_) in missing {
            findings.append(Finding(
                severity: .info, rule: .missingPathDirectory, tool: nil,
                message: "PATH entry \(dir) does not exist (\(labels(where_)))."))
        }
        for (dir, where_) in duplicates {
            findings.append(Finding(
                severity: .info, rule: .duplicatePathEntry, tool: nil,
                message: "PATH lists \(dir) more than once (\(labels(where_))); only the first occurrence is used."))
        }
        return findings
    }

    /// Apple adds these cryptex bootstrap entries to every PATH; they only exist
    /// on some systems and are not something a user can or should change.
    static let systemManagedPrefixes = ["/var/run/com.apple.security.cryptexd/", "/System/Cryptexes/"]

    /// False only when the entry is definitely absent (ENOENT or ENOTDIR), so an
    /// unreadable directory is not reported as missing.
    public static func entryExists(_ path: String) -> Bool {
        if systemManagedPrefixes.contains(where: { path.hasPrefix($0) }) { return true }
        var info = stat()
        if stat(path, &info) == 0 { return (info.st_mode & S_IFMT) == S_IFDIR }
        return errno != ENOENT && errno != ENOTDIR
    }

    private static func append(_ list: inout [(String, [ShellContext])], _ dir: String, _ context: ShellContext) {
        if let index = list.firstIndex(where: { $0.0 == dir }) {
            if !list[index].1.contains(context) { list[index].1.append(context) }
        } else {
            list.append((dir, [context]))
        }
    }

    static func labels(_ contexts: [ShellContext]) -> String {
        contexts.map(\.label).joined(separator: ", ")
    }

    // MARK: - Language-level

    /// More than one version manager provides tools of one language on the primary PATH.
    public static func duplicateManagers(language: String, copies: [Copy], primary: ShellContext) -> Finding? {
        var managers: [Manager] = []
        for copy in copies where copy.presentIn.contains(primary) && copy.manager.kind == .versionManager {
            if !managers.contains(copy.manager) { managers.append(copy.manager) }
        }
        guard managers.count >= 2 else { return nil }
        let names = managers.map(\.name)
        let list = names.dropLast().joined(separator: ", ") + " and " + names.last!
        return Finding(
            severity: .warning, rule: .duplicateManagers, tool: nil,
            message: "\(list) all put \(language) tools on PATH (\(primary.label)). Only the first one on PATH "
                + "decides each command, so versions can switch depending on which command you run; "
                + "keep one and remove the other's init line.")
    }

    // MARK: - Tool-level

    public static func toolFindings(
        tool: String,
        language: String,
        winner: Copy?,
        copies: [Copy],
        contextWinners: [ContextWinner],
        primary: ShellContext,
        versionFiles: [VersionFile]
    ) -> [Finding] {
        var findings: [Finding] = []
        guard let winner else { return findings }
        let shadowedOnPrimary = copies.filter { $0.path != winner.path && $0.presentIn.contains(primary) }

        if winner.isShim, winner.manager.kind == .versionManager,
           let brew = shadowedOnPrimary.first(where: { $0.manager.id == Manager.homebrew.id }) {
            findings.append(Finding(
                severity: .info, rule: .shimBeforeHomebrew, tool: tool,
                message: "The \(winner.manager.name) shim \(winner.path) is ahead of Homebrew's \(tool) (\(brew.path)); "
                    + "Homebrew's copy only runs where the shim directory is not on PATH."))
        }

        if winner.manager.kind == .system,
           let managed = shadowedOnPrimary.first(where: { $0.manager.isManaged }) {
            findings.append(Finding(
                severity: .warning, rule: .systemWinsOverManaged, tool: tool,
                message: "The \(winner.managerLabel) \(tool) (\(winner.path)) wins over the \(managed.managerLabel) copy "
                    + "(\(managed.path)); put \(managed.directory) before \(winner.directory) in PATH if you meant to use it."))
        }

        let byContext = Dictionary(contextWinners.map { ($0.context, $0.path) }, uniquingKeysWith: { a, _ in a })
        func describe(_ path: String??) -> String {
            guard let path, let path else { return "no \(tool)" }
            return path
        }

        var contextRuleFired = false
        for (interactive, login) in [(ShellContext.zshInteractive, ShellContext.zshLogin),
                                     (.bashInteractive, .bashLogin)] {
            guard let a = byContext[interactive], let b = byContext[login], a != b else { continue }
            contextRuleFired = true
            findings.append(Finding(
                severity: .warning, rule: .loginInteractiveMismatch, tool: tool,
                message: "\(interactive.label) runs \(describe(a)) but \(login.label) runs \(describe(b)). "
                    + "Scripts, editors and CI steps that start a login shell without -i get the second one; "
                    + "the usual cause is PATH set in an interactive-only file (.zshrc, .bashrc)."))
        }

        if winner.manager.isManaged, let gui = byContext[.gui], gui != winner.path {
            contextRuleFired = true
            findings.append(Finding(
                severity: .warning, rule: .guiPathLacksManager, tool: tool,
                message: "Apps started from the Dock or Finder (Xcode, VS Code, cron-like agents) run \(describe(gui)), "
                    + "not \(winner.path): their PATH does not include \(winner.directory)."))
        }

        if !contextRuleFired {
            let others = contextWinners.filter { $0.path != winner.path && $0.context != primary }
            if !others.isEmpty {
                let detail = others.map { "\($0.context.label): \($0.path ?? "no \(tool)")" }.joined(separator: "; ")
                findings.append(Finding(
                    severity: .info, rule: .shellsDisagree, tool: tool,
                    message: "Other contexts resolve \(tool) differently (\(detail))."))
            }
        }

        if Tools.versionControlledTools(for: language).contains(tool) {
            for file in versionFiles where file.language == language {
                let readers = VersionFiles.readers[file.name] ?? []
                if !readers.contains(winner.manager.id) {
                    findings.append(Finding(
                        severity: .warning, rule: .versionFileIgnored, tool: tool,
                        message: "\(file.path) asks for \(file.value), but \(tool) resolves to \(winner.managerLabel) "
                            + "(\(winner.path)), which does not read \(file.name)."))
                } else if let version = winner.version,
                          VersionParser.satisfies(requested: file.value, actual: version) == false {
                    let hint = winner.manager.id == Manager.nvm.id ? " nvm switches only when `nvm use` runs." : ""
                    findings.append(Finding(
                        severity: .warning, rule: .versionFileMismatch, tool: tool,
                        message: "\(file.path) asks for \(file.value), but \(tool) reports \(version) "
                            + "(\(winner.path)).\(hint)"))
                }
            }
        }
        return findings
    }
}
