import Foundation
import XCTest
@testable import ShadowCore

/// A throwaway directory tree under a fresh mkdtemp directory, canonicalised
/// with realpath so /var and /private/var never differ. Removed on release.
final class Fixture {
    let root: String

    init() throws {
        var template = Array((NSTemporaryDirectory() as NSString)
            .appendingPathComponent("shadow-test-XXXXXX").utf8CString)
        guard let made = mkdtemp(&template) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        root = PathResolver.realPath(String(cString: made)) ?? String(cString: made)
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }

    var home: String { root + "/home" }

    /// Layout whose home, Homebrew prefixes and system directories live in the fixture.
    var layout: Layout {
        Layout(
            home: home,
            homebrewPrefixes: [root + "/opt/homebrew", root + "/usr/local"],
            systemDirectories: [root + "/usr/bin", root + "/bin"],
            root: root)
    }

    func path(_ relative: String) -> String {
        root + "/" + relative
    }

    /// Writes a file, creating parents.
    @discardableResult
    func write(_ relative: String, _ contents: String, mode: mode_t = 0o644) throws -> String {
        let full = path(relative)
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: full))
        chmod(full, mode)
        return full
    }

    /// An executable shell script that prints `output` (to stderr when asked).
    @discardableResult
    func tool(_ relative: String, prints output: String, toStderr: Bool = false) throws -> String {
        let redirect = toStderr ? " 1>&2" : ""
        return try write(relative, "#!/bin/sh\nprintf '%s\\n' '\(output)'\(redirect)\n", mode: 0o755)
    }

    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
    }

    func symlink(_ relative: String, to destination: String) throws {
        let full = path(relative)
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: full, withDestinationPath: destination)
    }

    /// A detector that never shells out.
    func detector(xcrun: String? = nil, javaHome: String? = nil) -> ManagerDetector {
        ManagerDetector(layout: layout, xcrunFind: { _ in xcrun }, javaHome: { javaHome })
    }

    func analyzer(probe: Bool = true, xcrun: String? = nil) -> Analyzer {
        Analyzer(layout: layout, detector: detector(xcrun: xcrun), probe: VersionProbe(timeout: 5),
                 shadowVersion: "test", probeVersions: probe)
    }
}
