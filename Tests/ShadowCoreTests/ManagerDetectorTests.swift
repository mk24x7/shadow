import XCTest
@testable import ShadowCore

final class ManagerDetectorTests: XCTestCase {
    private func classify(_ f: Fixture, _ detector: ManagerDetector, tool: String, dir: String) -> ManagerDetector.Classification {
        let path = f.path(dir) + "/" + tool
        return detector.classify(tool: tool, path: path, directory: f.path(dir),
                                 realPath: PathResolver.realPath(path) ?? path)
    }

    func testNvmInstallWithVersionDetail() throws {
        let f = try Fixture()
        try f.tool("home/.nvm/versions/node/v20.1.0/bin/node", prints: "v20.1.0")
        let c = classify(f, f.detector(), tool: "node", dir: "home/.nvm/versions/node/v20.1.0/bin")
        XCTAssertEqual(c.manager, .nvm)
        XCTAssertEqual(c.detail, "v20.1.0")
        XCTAssertFalse(c.isShim)
    }

    func testShimDirectoriesAreShims() throws {
        let f = try Fixture()
        let cases: [(String, String, Manager)] = [
            ("home/.volta/bin", "node", .volta),
            ("home/.asdf/shims", "node", .asdf),
            ("home/.local/share/mise/shims", "python3", .mise),
            ("home/.pyenv/shims", "python3", .pyenv),
            ("home/.rbenv/shims", "ruby", .rbenv),
            ("home/.jenv/shims", "java", .jenv),
            ("home/.cargo/bin", "cargo", .rustup),
        ]
        for (dir, tool, manager) in cases {
            try f.tool("\(dir)/\(tool)", prints: "1.0.0")
            let c = classify(f, f.detector(), tool: tool, dir: dir)
            XCTAssertEqual(c.manager, manager, dir)
            XCTAssertTrue(c.isShim, dir)
        }
    }

    func testMiseShimSymlinkToHomebrewStillCountsAsMiseShim() throws {
        let f = try Fixture()
        try f.tool("opt/homebrew/Cellar/mise/2024.1.0/bin/mise", prints: "2024.1.0")
        try f.symlink("home/.local/share/mise/shims/node", to: f.path("opt/homebrew/Cellar/mise/2024.1.0/bin/mise"))
        let c = classify(f, f.detector(), tool: "node", dir: "home/.local/share/mise/shims")
        XCTAssertEqual(c.manager, .mise)
        XCTAssertTrue(c.isShim)
    }

    func testHomebrewVersionedKegThroughOptSymlink() throws {
        let f = try Fixture()
        try f.tool("opt/homebrew/Cellar/node@20/20.11.0/bin/node", prints: "v20.11.0")
        try f.symlink("opt/homebrew/opt/node@20", to: f.path("opt/homebrew/Cellar/node@20/20.11.0"))
        let c = classify(f, f.detector(), tool: "node", dir: "opt/homebrew/opt/node@20/bin")
        XCTAssertEqual(c.manager, .homebrew)
        XCTAssertEqual(c.detail, "node@20")

        try f.tool("opt/homebrew/Cellar/python@3.12/3.12.1/bin/python3", prints: "Python 3.12.1")
        try f.symlink("opt/homebrew/bin/python3", to: f.path("opt/homebrew/Cellar/python@3.12/3.12.1/bin/python3"))
        let p = classify(f, f.detector(), tool: "python3", dir: "opt/homebrew/bin")
        XCTAssertEqual(p.detail, "python@3.12")
    }

    func testXcodeStubResolvedThroughXcrun() throws {
        let f = try Fixture()
        try f.write("usr/bin/git", "#!/bin/sh\n# links /usr/lib/libxcselect.dylib\necho stub\n", mode: 0o755)
        let c = classify(f, f.detector(xcrun: "/Applications/Xcode.app/Contents/Developer/usr/bin/git"),
                         tool: "git", dir: "usr/bin")
        XCTAssertEqual(c.manager, .xcode)
        XCTAssertTrue(c.isShim)
        XCTAssertEqual(c.shimTarget, "/Applications/Xcode.app/Contents/Developer/usr/bin/git")

        try f.tool("usr/bin/ruby", prints: "ruby 2.6.10p210")
        let ruby = classify(f, f.detector(), tool: "ruby", dir: "usr/bin")
        XCTAssertEqual(ruby.manager, .system)
        XCTAssertFalse(ruby.isShim)
    }

    func testJavaStubWithoutJDKHasNoTarget() throws {
        let f = try Fixture()
        try f.write("usr/bin/java", "#!/bin/sh\n# JavaLaunching\n", mode: 0o755)
        let none = classify(f, f.detector(javaHome: nil), tool: "java", dir: "usr/bin")
        XCTAssertEqual(none.manager, .javaStub)
        XCTAssertNil(none.shimTarget)
        let some = classify(f, f.detector(javaHome: "/Library/Java/JavaVirtualMachines/x.jdk/Contents/Home/"),
                            tool: "java", dir: "usr/bin")
        XCTAssertEqual(some.shimTarget, "/Library/Java/JavaVirtualMachines/x.jdk/Contents/Home/bin/java")
    }

    func testCondaPythonOrgAndUserInstalls() throws {
        let f = try Fixture()
        try f.tool("home/miniconda3/envs/ml/bin/python", prints: "Python 3.11.7")
        XCTAssertEqual(classify(f, f.detector(), tool: "python", dir: "home/miniconda3/envs/ml/bin").detail, "env ml")
        try f.tool("Library/Frameworks/Python.framework/Versions/3.12/bin/python3", prints: "Python 3.12.1")
        let org = classify(f, f.detector(), tool: "python3", dir: "Library/Frameworks/Python.framework/Versions/3.12/bin")
        XCTAssertEqual(org.manager, .pythonOrg)
        XCTAssertEqual(org.detail, "3.12")
        try f.tool("home/go/bin/gopls", prints: "v0.15.0")
        XCTAssertEqual(classify(f, f.detector(), tool: "gopls", dir: "home/go/bin").manager, .goInstall)
        try f.tool("usr/local/bin/terraform", prints: "Terraform v1.7.0")
        XCTAssertEqual(classify(f, f.detector(), tool: "terraform", dir: "usr/local/bin").manager, .usrLocal)
    }
}
