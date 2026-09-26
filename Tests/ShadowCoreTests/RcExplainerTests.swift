import XCTest
@testable import ShadowCore

final class RcExplainerTests: XCTestCase {
    func testLiteralHomeExport() throws {
        let f = try Fixture()
        try f.write("home/.zshrc", "# comment\nexport PATH=\"$HOME/.nvm/versions/node/v20.1.0/bin:$PATH\"\n")
        let r = RcExplainer(layout: f.layout).explain(
            directory: f.home + "/.nvm/versions/node/v20.1.0/bin", manager: .nvm, family: "zsh")
        XCTAssertEqual(r.because?.file, f.home + "/.zshrc")
        XCTAssertEqual(r.because?.line, 2)
        XCTAssertEqual(r.because?.kind, .literal)
    }

    func testTildeInZshPathArray() throws {
        let f = try Fixture()
        try f.write("home/.zprofile", "typeset -U path\npath=(~/.local/bin $path)\n")
        let r = RcExplainer(layout: f.layout).explain(directory: f.home + "/.local/bin", manager: .localBin, family: "zsh")
        XCTAssertEqual(r.because?.line, 2)
        XCTAssertEqual(r.because?.text, "path=(~/.local/bin $path)")
    }

    func testNvmSourcingIsManagerInit() throws {
        let f = try Fixture()
        try f.write("home/.zshrc", "export NVM_DIR=\"$HOME/.nvm\"\n[ -s \"$NVM_DIR/nvm.sh\" ] && \\. \"$NVM_DIR/nvm.sh\"\n")
        let r = RcExplainer(layout: f.layout).explain(
            directory: f.home + "/.nvm/versions/node/v18.20.0/bin", manager: .nvm, family: "zsh")
        XCTAssertEqual(r.because?.kind, .managerInit)
        XCTAssertEqual(r.because?.line, 2)
        XCTAssertEqual(r.because?.note, "added by nvm init")
    }

    func testEtcPathsExplainsSystemDirectory() throws {
        let f = try Fixture()
        try f.write("etc/paths", "/usr/local/bin\n/usr/bin\n/bin\n")
        let r = RcExplainer(layout: f.layout).explain(directory: "/usr/bin", manager: .system, family: "zsh")
        XCTAssertEqual(r.because?.kind, .pathsFile)
        XCTAssertEqual(r.because?.file, f.path("etc/paths"))
        XCTAssertEqual(r.because?.line, 2)
    }

    func testBrewShellenvAndBrewPrefix() throws {
        let f = try Fixture()
        try f.write("home/.zprofile", "eval \"$(/opt/homebrew/bin/brew shellenv)\"\n")
        try f.write("home/.zshrc", "export PATH=\"$(brew --prefix node@20)/bin:$PATH\"\n")
        let explainer = RcExplainer(layout: f.layout)
        let brew = explainer.explain(directory: f.path("opt/homebrew/bin"), manager: .homebrew, family: "zsh")
        XCTAssertEqual(brew.because?.note, "added by Homebrew init")
        let keg = explainer.explain(directory: f.path("opt/homebrew/opt/node@20/bin"), manager: .homebrew, family: "zsh")
        XCTAssertEqual(keg.because?.file, f.home + "/.zshrc")
        XCTAssertEqual(keg.because?.kind, .literal)
    }

    func testLaterPrependWinsAndAppendRanksLower() throws {
        let f = try Fixture()
        try f.write("home/.zprofile", "export PATH=\"$PATH:$HOME/bin\"\n")
        try f.write("home/.zshrc", "export PATH=\"$HOME/bin:$PATH\"\n")
        try f.write("home/.bashrc", "export PATH=\"$HOME/bin:$PATH\"\n")
        let r = RcExplainer(layout: f.layout).explain(directory: f.home + "/bin", manager: .unknown, family: "zsh")
        XCTAssertEqual(r.because?.file, f.home + "/.zshrc")
        XCTAssertEqual(r.alsoMentioned.count, 2)
    }

    func testVariablesAndSourcedFiles() throws {
        let f = try Fixture()
        try f.write("home/.zshrc", "source ~/.config/zsh/paths.zsh\n")
        try f.write("home/.config/zsh/paths.zsh", "export PNPM_HOME=\"$HOME/Library/pnpm\"\nexport PATH=\"$PNPM_HOME:$PATH\"\n")
        let r = RcExplainer(layout: f.layout).explain(directory: f.home + "/Library/pnpm", manager: .pnpmStandalone, family: "zsh")
        XCTAssertEqual(r.because?.file, f.home + "/.config/zsh/paths.zsh")
        XCTAssertEqual(r.because?.line, 2)
    }

    func testFishAddPath() throws {
        let f = try Fixture()
        try f.write("home/.config/fish/config.fish", "set -gx VOLTA_HOME $HOME/.volta\nfish_add_path $VOLTA_HOME/bin\n")
        let r = RcExplainer(layout: f.layout).explain(directory: f.home + "/.volta/bin", manager: .volta, family: "fish")
        XCTAssertEqual(r.because?.line, 2)
        XCTAssertEqual(r.because?.kind, .literal)
    }

    func testNoMatch() throws {
        let f = try Fixture()
        try f.write("home/.zshrc", "alias ll='ls -l'\n")
        let r = RcExplainer(layout: f.layout).explain(directory: "/nowhere/bin", manager: .unknown, family: "zsh")
        XCTAssertNil(r.because)
    }
}
