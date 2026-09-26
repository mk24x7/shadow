import XCTest
@testable import ShadowCore

final class AnalyzerTests: XCTestCase {
    /// nvm node ahead of Homebrew node, a system python behind a pyenv shim.
    private func makeTree() throws -> Fixture {
        let f = try Fixture()
        try f.tool("home/.nvm/versions/node/v20.1.0/bin/node", prints: "v20.1.0")
        try f.tool("opt/homebrew/Cellar/node/22.3.0/bin/node", prints: "v22.3.0")
        try f.symlink("opt/homebrew/bin/node", to: f.path("opt/homebrew/Cellar/node/22.3.0/bin/node"))
        try f.tool("usr/bin/ruby", prints: "ruby 2.6.10p210 (2022-04-12 revision 67958) [universal.arm64e-darwin23]")
        try f.tool("home/.rbenv/versions/3.3.0/bin/ruby", prints: "ruby 3.3.0p0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]")
        try f.tool("usr/local/opt/openjdk/bin/java", prints: #"openjdk version "21.0.2" 2024-01-16"#, toStderr: true)
        try f.write("home/.zshrc", "export PATH=\"$HOME/.nvm/versions/node/v20.1.0/bin:$PATH\"\n")
        return f
    }

    private func contexts(_ f: Fixture, primary: [String], extra: [ShellContext: [String]] = [:]) -> [ContextPath] {
        var list = [ContextPath(context: .zshInteractive, path: primary.map(f.path).joined(separator: ":"))]
        for (context, dirs) in extra.sorted(by: { $0.key < $1.key }) {
            list.append(ContextPath(context: context, path: dirs.map(f.path).joined(separator: ":")))
        }
        return list
    }

    func testWinnerShadowedVersionsAndBecause() throws {
        let f = try makeTree()
        let report = f.analyzer().analyze(
            contexts: contexts(f, primary: ["home/.nvm/versions/node/v20.1.0/bin", "opt/homebrew/bin", "usr/bin"]),
            tools: ["node"], directory: f.root, primary: .zshInteractive, explainFamily: "zsh")
        let node = try XCTUnwrap(report.tools.first)
        XCTAssertEqual(node.winner?.manager, .nvm)
        XCTAssertEqual(node.winner?.version, "20.1.0")
        XCTAssertEqual(node.shadowed.map(\.manager), [.homebrew])
        XCTAssertEqual(node.shadowed.first?.version, "22.3.0")
        XCTAssertEqual(node.shadowed.first?.detail, "node")
        XCTAssertEqual(node.because?.file, f.home + "/.zshrc")
        XCTAssertEqual(node.because?.line, 1)
    }

    func testJavaVersionFromStderr() throws {
        let f = try makeTree()
        let report = f.analyzer().analyze(
            contexts: contexts(f, primary: ["usr/local/opt/openjdk/bin"]),
            tools: ["java"], directory: f.root, primary: .zshInteractive, explainFamily: "zsh")
        XCTAssertEqual(report.tools.first?.winner?.version, "21.0.2")
        XCTAssertEqual(report.tools.first?.winner?.manager, .homebrew)
    }

    func testPerShellComparisonWithInjectedPaths() throws {
        let f = try makeTree()
        let report = f.analyzer(probe: false).analyze(
            contexts: contexts(f,
                primary: ["home/.nvm/versions/node/v20.1.0/bin", "opt/homebrew/bin", "usr/bin"],
                extra: [.zshLogin: ["opt/homebrew/bin", "usr/bin"], .gui: ["usr/bin", "bin"]]),
            tools: ["node"], directory: f.root, primary: .zshInteractive, explainFamily: "zsh")
        let node = try XCTUnwrap(report.tools.first)
        let byContext = Dictionary(uniqueKeysWithValues: node.contextWinners.map { ($0.context, $0.path) })
        XCTAssertEqual(byContext[.zshInteractive] ?? nil, f.path("home/.nvm/versions/node/v20.1.0/bin/node"))
        XCTAssertEqual(byContext[.zshLogin] ?? nil, f.path("opt/homebrew/bin/node"))
        XCTAssertEqual(byContext[.gui] ?? "missing", nil)
        let rules = Set(node.findings.map(\.rule))
        XCTAssertTrue(rules.contains(.loginInteractiveMismatch))
        XCTAssertTrue(rules.contains(.guiPathLacksManager))
        let brew = node.copies.first { $0.manager == .homebrew }
        XCTAssertEqual(brew?.winsIn, [.zshLogin])
        XCTAssertEqual(brew?.presentIn, [.zshInteractive, .zshLogin])
    }

    func testCopyOnlyOnOtherContextIsListed() throws {
        let f = try makeTree()
        let report = f.analyzer(probe: false).analyze(
            contexts: contexts(f, primary: ["home/.nvm/versions/node/v20.1.0/bin"],
                               extra: [.bashInteractive: ["opt/homebrew/bin"]]),
            tools: ["node"], directory: f.root, primary: .zshInteractive, explainFamily: "zsh")
        let node = try XCTUnwrap(report.tools.first)
        XCTAssertEqual(node.copies.count, 2)
        XCTAssertEqual(node.shadowed.first?.presentIn, [.bashInteractive])
        XCTAssertTrue(node.findings.contains { $0.rule == .shellsDisagree })
    }

    func testSystemRubyWinsOverRbenv() throws {
        let f = try makeTree()
        let report = f.analyzer().analyze(
            contexts: contexts(f, primary: ["usr/bin", "home/.rbenv/versions/3.3.0/bin"]),
            tools: ["ruby"], directory: f.root, primary: .zshInteractive, explainFamily: "zsh")
        let ruby = try XCTUnwrap(report.tools.first)
        XCTAssertEqual(ruby.winner?.manager, .system)
        XCTAssertEqual(ruby.winner?.version, "2.6.10")
        XCTAssertEqual(ruby.shadowed.first?.version, "3.3.0")
        XCTAssertTrue(ruby.findings.contains { $0.rule == .systemWinsOverManaged && $0.severity == .warning })
    }

    func testVersionFileMismatchAndIgnored() throws {
        let f = try makeTree()
        try f.write("proj/.nvmrc", "18\n")
        try f.write("proj/.ruby-version", "3.3.0\n")
        let report = f.analyzer().analyze(
            contexts: contexts(f, primary: ["home/.nvm/versions/node/v20.1.0/bin", "usr/bin"]),
            tools: ["node", "ruby"], directory: f.path("proj"), primary: .zshInteractive, explainFamily: "zsh")
        let node = try XCTUnwrap(report.tools.first { $0.tool == "node" })
        XCTAssertTrue(node.findings.contains { $0.rule == .versionFileMismatch })
        let ruby = try XCTUnwrap(report.tools.first { $0.tool == "ruby" })
        XCTAssertTrue(ruby.findings.contains { $0.rule == .versionFileIgnored })
        XCTAssertEqual(report.versionFiles.map(\.name).sorted(), [".nvmrc", ".ruby-version"])
    }

    func testShimVersionRunsInWorkingDirectory() throws {
        let f = try Fixture()
        // A shim whose answer depends on the directory it runs in.
        try f.write("home/.pyenv/shims/python3",
                    "#!/bin/sh\nif [ -f .python-version ]; then echo \"Python $(cat .python-version)\"; else echo 'Python 3.9.6'; fi\n",
                    mode: 0o755)
        try f.write("a/.python-version", "3.12.1\n")
        try f.mkdir("b")
        let analyzer = f.analyzer()
        let ctx = [ContextPath(context: .zshInteractive, path: f.path("home/.pyenv/shims") + ":/usr/bin:/bin")]
        let inA = analyzer.analyze(contexts: ctx, tools: ["python3"], directory: f.path("a"), primary: .zshInteractive, explainFamily: "zsh")
        let inB = analyzer.analyze(contexts: ctx, tools: ["python3"], directory: f.path("b"), primary: .zshInteractive, explainFamily: "zsh")
        XCTAssertEqual(inA.tools.first?.winner?.version, "3.12.1")
        XCTAssertEqual(inA.tools.first?.winner?.isShim, true)
        XCTAssertEqual(inB.tools.first?.winner?.version, "3.9.6")
        XCTAssertTrue(inA.tools.first?.findings.filter { $0.rule == .versionFileIgnored || $0.rule == .versionFileMismatch }.isEmpty ?? false)
    }

    func testJSONEncodingCarriesReport() throws {
        let f = try makeTree()
        let report = f.analyzer(probe: false).analyze(
            contexts: contexts(f, primary: ["home/.nvm/versions/node/v20.1.0/bin", "opt/homebrew/bin"]),
            tools: ["node", "nosuchtool"], directory: f.root, primary: .zshInteractive, explainFamily: "zsh")
        let json = try ReportFormatter.json(report)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["primaryContext"] as? String, "zsh-il")
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual((tools[0]["copies"] as? [Any])?.count, 2)
        XCTAssertEqual(report.counts.toolsFound, 1)
        XCTAssertEqual(report.counts.shadowedCopies, 1)
    }

    func testTextReportShowsWinnerShadowedAndBecause() throws {
        let f = try makeTree()
        let report = f.analyzer().analyze(
            contexts: contexts(f, primary: ["home/.nvm/versions/node/v20.1.0/bin", "opt/homebrew/bin"]),
            tools: ["node"], directory: f.root, primary: .zshInteractive, explainFamily: "zsh")
        let text = ReportFormatter(color: false, layout: f.layout).render(report)
        XCTAssertTrue(text.contains("winner   ~/.nvm/versions/node/v20.1.0/bin/node  20.1.0  nvm (v20.1.0)"), text)
        XCTAssertTrue(text.contains("shadowed"), text)
        XCTAssertTrue(text.contains("because: ~/.zshrc:1 export PATH="), text)
        XCTAssertTrue(text.contains("1 tools checked, 1 found, 1 shadowed copy"), text)
        XCTAssertFalse(text.contains("\u{1B}["), "no ANSI codes when colour is off")
    }
}
