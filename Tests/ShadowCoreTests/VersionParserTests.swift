import XCTest
@testable import ShadowCore

final class VersionParserTests: XCTestCase {
    func testNodeLeadingV() {
        XCTAssertEqual(VersionParser.parse("v20.1.0"), "20.1.0")
    }

    func testPython() {
        XCTAssertEqual(VersionParser.parse("Python 3.12.1"), "3.12.1")
    }

    func testOpenJDKQuotedVersion() {
        XCTAssertEqual(VersionParser.parse(#"openjdk version "21.0.2" 2024-01-16"#), "21.0.2")
        XCTAssertEqual(VersionParser.parse(#"openjdk version "21" 2023-09-19"#), "21")
    }

    func testGoVersion() {
        XCTAssertEqual(VersionParser.parse("go version go1.22.0 darwin/arm64"), "1.22.0")
    }

    func testRubyPatchSuffix() {
        XCTAssertEqual(VersionParser.parse("ruby 3.3.0p0 (2023-12-25 revision 5124f9ac75) [arm64-darwin23]"), "3.3.0")
    }

    func testRustcAndPHP() {
        XCTAssertEqual(VersionParser.parse("rustc 1.77.0 (aedd173a2 2024-03-17)"), "1.77.0")
        XCTAssertEqual(VersionParser.parse("PHP 8.3.1 (cli) (built: Dec 20 2023 12:44:38) (NTS)"), "8.3.1")
    }

    func testSwiftDriverPrefersSwiftVersion() {
        let line = "swift-driver version: 1.115.1 Apple Swift version 6.3 (swiftlang-6.3.0.1 clang-1700.3.1)"
        XCTAssertEqual(VersionParser.parse(line), "6.3")
    }

    func testNoVersion() {
        XCTAssertNil(VersionParser.parse("usage: tool [options]"))
    }

    func testFirstLinePrefersStdoutThenStderr() {
        XCTAssertEqual(VersionParser.firstLine(stdout: "\n  v20.1.0\nmore", stderr: "x"), "v20.1.0")
        XCTAssertEqual(VersionParser.firstLine(stdout: "", stderr: "openjdk version \"21.0.2\"\nOpenJDK"), "openjdk version \"21.0.2\"")
    }

    func testSatisfies() {
        XCTAssertEqual(VersionParser.satisfies(requested: "20", actual: "20.1.0"), true)
        XCTAssertEqual(VersionParser.satisfies(requested: "v20.1", actual: "20.1.0"), true)
        XCTAssertEqual(VersionParser.satisfies(requested: "18", actual: "20.1.0"), false)
        XCTAssertEqual(VersionParser.satisfies(requested: "python-3.12", actual: "3.12.1"), true)
        XCTAssertEqual(VersionParser.satisfies(requested: "openjdk-21", actual: "21.0.2"), true)
        XCTAssertEqual(VersionParser.satisfies(requested: "3.12.0", actual: "3.12"), true)
        XCTAssertNil(VersionParser.satisfies(requested: "lts/*", actual: "20.1.0"))
        XCTAssertNil(VersionParser.satisfies(requested: "system", actual: "3.9.6"))
    }
}
