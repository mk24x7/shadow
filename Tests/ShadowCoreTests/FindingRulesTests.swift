import XCTest
@testable import ShadowCore

final class FindingRulesTests: XCTestCase {
    private func copy(_ path: String, _ manager: Manager, shim: Bool = false, in contexts: [ShellContext] = [.zshInteractive]) -> Copy {
        Copy(path: path, directory: (path as NSString).deletingLastPathComponent, realPath: path,
             manager: manager, detail: nil, isShim: shim, shimTarget: nil, presentIn: contexts)
    }

    func testDuplicateManagersForOneLanguage() {
        let copies = [copy("/h/.volta/bin/node", .volta, shim: true),
                      copy("/h/.nvm/versions/node/v20/bin/node", .nvm),
                      copy("/opt/homebrew/bin/node", .homebrew)]
        let finding = FindingRules.duplicateManagers(language: "node", copies: copies, primary: .zshInteractive)
        XCTAssertEqual(finding?.rule, .duplicateManagers)
        XCTAssertTrue(finding?.message.contains("Volta and nvm") ?? false)
        XCTAssertNil(FindingRules.duplicateManagers(language: "node", copies: [copies[0], copies[2]], primary: .zshInteractive))
    }

    func testShimInFrontOfHomebrew() {
        let winner = copy("/h/.asdf/shims/node", .asdf, shim: true)
        let findings = FindingRules.toolFindings(
            tool: "node", language: "node", winner: winner,
            copies: [winner, copy("/opt/homebrew/bin/node", .homebrew)],
            contextWinners: [ContextWinner(context: .zshInteractive, path: winner.path)],
            primary: .zshInteractive, versionFiles: [])
        XCTAssertEqual(findings.map(\.rule), [.shimBeforeHomebrew])
        XCTAssertEqual(findings.first?.severity, .info)
    }

    func testMissingAndDuplicatePathEntries() {
        let contexts = [
            ContextPath(context: .zshInteractive, path: "/a:/missing:/a:/b"),
            ContextPath(context: .zshLogin, path: "/missing:/b"),
            ContextPath(context: .fishLogin, path: nil, error: "timed out after 10 s"),
            ContextPath(context: .gui, path: "/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin"),
        ]
        let findings = FindingRules.pathFindings(contexts: contexts) { $0 != "/missing" }
        let missing = findings.filter { $0.rule == .missingPathDirectory }
        XCTAssertEqual(missing.count, 1)
        XCTAssertTrue(missing[0].message.contains("zsh -il, zsh -l"))
        XCTAssertEqual(findings.filter { $0.rule == .duplicatePathEntry }.count, 1)
        XCTAssertEqual(findings.filter { $0.rule == .captureFailed }.count, 1)
        XCTAssertTrue(FindingRules.entryExists("/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin"))
    }

    func testNoFindingsWhenEverythingAgrees() {
        let winner = copy("/opt/homebrew/bin/node", .homebrew, in: [.zshInteractive, .zshLogin, .gui])
        let winners = [ShellContext.zshInteractive, .zshLogin, .gui].map { ContextWinner(context: $0, path: winner.path) }
        let findings = FindingRules.toolFindings(
            tool: "node", language: "node", winner: winner, copies: [winner],
            contextWinners: winners, primary: .zshInteractive, versionFiles: [])
        XCTAssertTrue(findings.isEmpty)
    }
}
