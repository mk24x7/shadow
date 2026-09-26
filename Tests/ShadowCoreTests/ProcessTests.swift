import XCTest
@testable import ShadowCore

final class ProcessTests: XCTestCase {
    func testTimeoutKillsChild() {
        let start = Date()
        let result = ProcessRunner.run(["/bin/sleep", "30"], timeout: 0.5)
        XCTAssertEqual(result?.timedOut, true)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testArgvIsNotShellInterpreted() {
        let result = ProcessRunner.run(["/bin/echo", "$HOME; rm -rf /"])
        XCTAssertEqual(result?.stdout, "$HOME; rm -rf /\n")
    }

    func testMissingExecutableReturnsNil() {
        XCTAssertNil(ProcessRunner.run(["/nonexistent/tool", "--version"]))
    }

    func testMarkerExtractionIgnoresRcNoise() {
        let output = "Welcome!\nlast login\n\(ShellCapture.beginMarker)/a:/b\(ShellCapture.endMarker)trailing"
        XCTAssertEqual(ShellCapture.extract(output), "/a:/b")
        XCTAssertNil(ShellCapture.extract("no markers here"))
    }

    func testShellCaptureRunsRealShell() {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin"
        let capture = ShellCapture(timeout: 10, environment: env, fish: nil)
        let result = capture.capture(.shLogin)
        XCTAssertNotNil(result.path, result.error ?? "")
        XCTAssertTrue(result.entries.contains("/usr/bin"))
        XCTAssertEqual(capture.capture(.current).path, "/usr/bin:/bin")
        XCTAssertFalse(capture.availableContexts.contains(.fishLogin))
    }

    func testDefaultPrimaryFollowsLoginShell() {
        let all = ShellContext.allCases
        XCTAssertEqual(Analyzer.defaultPrimary(loginShell: "/bin/zsh", available: all), .zshInteractive)
        XCTAssertEqual(Analyzer.defaultPrimary(loginShell: "/bin/bash", available: all), .bashInteractive)
        XCTAssertEqual(Analyzer.defaultPrimary(loginShell: "/opt/homebrew/bin/fish", available: [.current, .gui]), .current)
    }
}
