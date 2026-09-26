import Foundation

/// Fixed locations Shadow reasons about. Tests substitute a temporary tree.
public struct Layout: Sendable {
    /// The user's home directory, without a trailing slash.
    public var home: String
    /// Homebrew prefixes, most specific first.
    public var homebrewPrefixes: [String]
    /// Directories whose contents ship with macOS.
    public var systemDirectories: [String]
    /// Root under which /etc and /Library are read ("/" in production).
    public var root: String

    public init(home: String, homebrewPrefixes: [String], systemDirectories: [String], root: String) {
        self.home = PathResolver.trimSlash(home)
        self.homebrewPrefixes = homebrewPrefixes.map(PathResolver.trimSlash)
        self.systemDirectories = systemDirectories.map(PathResolver.trimSlash)
        self.root = root
    }

    /// The running user's layout.
    public static func live() -> Layout {
        Layout(
            home: NSHomeDirectory(),
            homebrewPrefixes: ["/opt/homebrew", "/usr/local"],
            systemDirectories: ["/usr/bin", "/bin", "/usr/sbin", "/sbin"],
            root: "/"
        )
    }

    /// Absolute path of a system location such as "/etc/paths" under `root`.
    public func rooted(_ absolute: String) -> String {
        if root == "/" || root.isEmpty { return absolute }
        return PathResolver.trimSlash(root) + absolute
    }

    /// Replaces the home prefix with "~" for display.
    public func shorten(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
