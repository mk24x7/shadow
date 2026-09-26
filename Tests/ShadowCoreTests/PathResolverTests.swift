import XCTest
@testable import ShadowCore

final class PathResolverTests: XCTestCase {
    func testWinnerIsFirstExecutableInPathOrder() throws {
        let f = try Fixture()
        try f.tool("a/node", prints: "v18.0.0")
        try f.tool("b/node", prints: "v20.1.0")
        try f.write("c/node", "not executable")          // no exec bit: skipped
        try f.mkdir("d/node")                           // a directory: skipped
        let entries = [f.path("c"), f.path("d"), f.path("b"), f.path("a")]
        let hits = PathResolver.find("node", in: entries)
        XCTAssertEqual(hits.map(\.path), [f.path("b/node"), f.path("a/node")])
        XCTAssertEqual(hits.first?.directory, f.path("b"))
    }

    func testSymlinkResolvedWithRealpath() throws {
        let f = try Fixture()
        try f.tool("Cellar/node/20.1.0/bin/node", prints: "v20.1.0")
        try f.symlink("bin/node", to: f.path("Cellar/node/20.1.0/bin/node"))
        let hits = PathResolver.find("node", in: [f.path("bin")])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].path, f.path("bin/node"))
        XCTAssertEqual(hits[0].realPath, f.path("Cellar/node/20.1.0/bin/node"))
    }

    func testBrokenSymlinkIgnored() throws {
        let f = try Fixture()
        try f.symlink("bin/node", to: f.path("nowhere/node"))
        XCTAssertTrue(PathResolver.find("node", in: [f.path("bin")]).isEmpty)
    }

    func testSplitDropsEmptyEntriesAndDuplicateDirectoryYieldsOneHit() throws {
        let f = try Fixture()
        try f.tool("bin/go", prints: "go version go1.22.0 darwin/arm64")
        let path = "\(f.path("bin"))::\(f.path("bin"))/:relative/dir"
        let entries = PathResolver.split(path)
        XCTAssertEqual(entries, [f.path("bin"), f.path("bin"), "relative/dir"])
        XCTAssertEqual(PathResolver.find("go", in: entries).count, 1)
    }
}
