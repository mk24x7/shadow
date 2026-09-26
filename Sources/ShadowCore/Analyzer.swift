import Foundation

/// Turns captured PATHs into a Report: resolves every tool in every context,
/// labels copies, probes versions, explains winners and applies the rules.
public final class Analyzer: @unchecked Sendable {
    public let layout: Layout
    public let detector: ManagerDetector
    public let probe: VersionProbe
    public let explainer: RcExplainer
    public let shadowVersion: String
    /// When false no binary is executed (versions stay empty). Tests use this
    /// for fixtures that do not care about versions.
    public var probeVersions: Bool

    public init(
        layout: Layout = .live(),
        detector: ManagerDetector? = nil,
        probe: VersionProbe = VersionProbe(),
        shadowVersion: String = ShadowVersion.current,
        probeVersions: Bool = true
    ) {
        self.layout = layout
        self.detector = detector ?? ManagerDetector(layout: layout)
        self.probe = probe
        self.explainer = RcExplainer(layout: layout)
        self.shadowVersion = shadowVersion
        self.probeVersions = probeVersions
    }

    /// The context that represents "a new Terminal window" for a login shell.
    public static func defaultPrimary(loginShell: String?, available: [ShellContext]) -> ShellContext {
        let name = ((loginShell ?? "") as NSString).lastPathComponent
        let preferred: ShellContext
        switch name {
        case "bash": preferred = .bashInteractive
        case "fish": preferred = .fishLogin
        case "sh": preferred = .shLogin
        default: preferred = .zshInteractive
        }
        if available.contains(preferred) { return preferred }
        return available.first ?? .current
    }

    /// The user's login shell from the password database.
    public static func loginShell() -> String? {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else {
            return ProcessInfo.processInfo.environment["SHELL"]
        }
        return String(cString: shell)
    }

    public func analyze(
        contexts: [ContextPath],
        tools: [String],
        directory: String,
        primary requestedPrimary: ShellContext? = nil,
        explainFamily: String? = nil
    ) -> Report {
        let usable = contexts.filter { $0.path != nil }
        let primary: ShellContext = {
            if let requestedPrimary, usable.contains(where: { $0.context == requestedPrimary }) { return requestedPrimary }
            return Analyzer.defaultPrimary(loginShell: Analyzer.loginShell(), available: usable.map(\.context))
        }()
        let primaryPath = usable.first { $0.context == primary }?.path
        let family: String = {
            if let explainFamily { return explainFamily }
            switch primary.family {
            case "zsh", "bash", "fish", "sh": return primary.family
            default:
                let login = ((Analyzer.loginShell() ?? "zsh") as NSString).lastPathComponent
                return ["bash", "fish", "sh"].contains(login) ? login : "zsh"
            }
        }()
        let versionFiles = VersionFiles.find(in: directory)

        // 1. Resolve and classify.
        var classifications: [String: ManagerDetector.Classification] = [:]
        var perTool: [(tool: String, copies: [Copy], winners: [ContextWinner])] = []
        for tool in tools {
            var copies: [Copy] = []
            var winners: [ContextWinner] = []
            let ordered = usable.sorted { a, b in
                if a.context == primary { return b.context != primary }
                if b.context == primary { return false }
                return a.context < b.context
            }
            for context in ordered {
                let hits = PathResolver.find(tool, in: context.entries)
                winners.append(ContextWinner(context: context.context, path: hits.first?.path))
                for (index, hit) in hits.enumerated() {
                    if let existing = copies.firstIndex(where: { $0.path == hit.path }) {
                        copies[existing].presentIn.append(context.context)
                        if index == 0 { copies[existing].winsIn.append(context.context) }
                        continue
                    }
                    let c = classifications[hit.path] ?? detector.classify(
                        tool: tool, path: hit.path, directory: hit.directory, realPath: hit.realPath)
                    classifications[hit.path] = c
                    copies.append(Copy(
                        path: hit.path, directory: hit.directory, realPath: hit.realPath,
                        manager: c.manager, detail: c.detail, isShim: c.isShim, shimTarget: c.shimTarget,
                        presentIn: [context.context], winsIn: index == 0 ? [context.context] : []))
                }
            }
            winners.sort { $0.context < $1.context }
            for index in copies.indices {
                copies[index].presentIn.sort()
                copies[index].winsIn.sort()
            }
            perTool.append((tool, copies, winners))
        }

        // 2. Versions, concurrently.
        if probeVersions {
            var jobs: [(tool: Int, copy: Int)] = []
            for (t, entry) in perTool.enumerated() {
                for c in entry.copies.indices { jobs.append((t, c)) }
            }
            var results = [VersionProbe.Result?](repeating: nil, count: jobs.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
                let job = jobs[index]
                let tool = perTool[job.tool].tool
                let copy = perTool[job.tool].copies[job.copy]
                let result = versionOf(tool: tool, copy: copy, directory: directory, pathVariable: primaryPath)
                lock.lock()
                results[index] = result
                lock.unlock()
            }
            for (index, job) in jobs.enumerated() {
                guard let result = results[index] else { continue }
                perTool[job.tool].copies[job.copy].version = result.version
                perTool[job.tool].copies[job.copy].versionLine = result.line
                perTool[job.tool].copies[job.copy].versionError = result.error
            }
        }

        // 3. Language-level findings go on the first found tool of each language.
        var languageFinding: [String: Finding] = [:]
        var languageOwner: [String: String] = [:]
        var byLanguage: [String: [Copy]] = [:]
        for entry in perTool {
            let language = Tools.language(of: entry.tool)
            byLanguage[language, default: []] += entry.copies
            if languageOwner[language] == nil, !entry.copies.isEmpty { languageOwner[language] = entry.tool }
        }
        for (language, copies) in byLanguage {
            if let finding = FindingRules.duplicateManagers(language: language, copies: copies, primary: primary) {
                languageFinding[language] = finding
            }
        }

        // 4. Build tool reports.
        var reports: [ToolReport] = []
        for entry in perTool {
            let language = Tools.language(of: entry.tool)
            let winner = entry.copies.first { $0.winsIn.contains(primary) }
            var because: Explanation?
            var also: [Explanation] = []
            if let winner {
                let result = explainer.explain(directory: winner.directory, manager: winner.manager, family: family)
                because = result.because
                also = result.alsoMentioned
            }
            var findings: [Finding] = []
            if languageOwner[language] == entry.tool, let finding = languageFinding[language] {
                findings.append(Finding(severity: finding.severity, rule: finding.rule, tool: entry.tool, message: finding.message))
            }
            findings += FindingRules.toolFindings(
                tool: entry.tool, language: language, winner: winner, copies: entry.copies,
                contextWinners: entry.winners, primary: primary, versionFiles: versionFiles)
            reports.append(ToolReport(
                tool: entry.tool, language: language, winner: winner, copies: entry.copies,
                because: because, alsoMentioned: also, contextWinners: entry.winners, findings: findings))
        }

        return Report(
            shadowVersion: shadowVersion,
            generatedAt: Date(),
            directory: directory,
            primaryContext: primary,
            contexts: contexts,
            versionFiles: versionFiles,
            tools: reports,
            findings: FindingRules.pathFindings(contexts: contexts))
    }

    private func versionOf(tool: String, copy: Copy, directory: String, pathVariable: String?) -> VersionProbe.Result {
        let executable: String
        let key: String
        switch copy.manager.id {
        case Manager.xcode.id where copy.isShim, Manager.javaStub.id:
            guard let target = copy.shimTarget else {
                let missing = copy.manager.id == Manager.javaStub.id
                    ? "no JDK installed (the stub would only print an error)"
                    : "developer tools not installed (running the stub would open an installer)"
                return VersionProbe.Result(version: nil, line: nil, error: missing)
            }
            executable = target
            key = PathResolver.realPath(target) ?? target
        default:
            executable = copy.path
            key = copy.isShim ? "\(copy.path)|\(directory)" : copy.realPath + "|" + tool
        }
        return probe.probe(tool: tool, executable: executable, cacheKey: key, cwd: directory, pathVariable: pathVariable)
    }
}

