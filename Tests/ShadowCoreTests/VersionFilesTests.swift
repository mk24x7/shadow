import XCTest
@testable import ShadowCore

final class VersionFilesTests: XCTestCase {
    func testNearestFilesWalkingUp() throws {
        let f = try Fixture()
        try f.write("work/.nvmrc", "18\n")
        try f.write("work/app/.nvmrc", "# pinned\nv20.1.0\n")
        try f.write("work/.python-version", "3.12.1\n")
        try f.mkdir("work/app/src")
        let files = VersionFiles.find(in: f.path("work/app/src"))
        let nvmrc = files.filter { $0.name == ".nvmrc" }
        XCTAssertEqual(nvmrc.count, 1, "only the nearest .nvmrc applies")
        XCTAssertEqual(nvmrc.first?.value, "v20.1.0")
        XCTAssertEqual(nvmrc.first?.path, f.path("work/app/.nvmrc"))
        XCTAssertEqual(files.first { $0.name == ".python-version" }?.value, "3.12.1")
    }

    func testToolVersionsAndRustToolchain() throws {
        let f = try Fixture()
        try f.write("p/.tool-versions", "nodejs 20.1.0\npython 3.12.1 3.11.7  # two\ngolang 1.22.0\n\n# comment\n")
        try f.write("p/rust-toolchain.toml", "[toolchain]\nchannel = \"1.77.0\"\n")
        let files = VersionFiles.find(in: f.path("p"))
        let tv = files.filter { $0.name == ".tool-versions" }
        XCTAssertEqual(tv.map(\.language), ["node", "python", "go"])
        XCTAssertEqual(tv.map(\.value), ["20.1.0", "3.12.1", "1.22.0"])
        XCTAssertEqual(files.first { $0.name == "rust-toolchain.toml" }?.value, "1.77.0")
    }
}
