import Foundation

/// Finds every executable called `tool` on a PATH, in lookup order.
public enum PathResolver {
    /// Splits a PATH string, dropping empty entries (an empty entry means the
    /// current directory, which Shadow does not treat as a location).
    public static func split(_ path: String) -> [String] {
        path.split(separator: ":", omittingEmptySubsequences: true)
            .map { trimSlash(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Removes trailing slashes, keeping "/" itself.
    public static func trimSlash(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    /// realpath(3), or nil when the path cannot be resolved.
    public static func realPath(_ path: String) -> String? {
        guard let resolved = Darwin.realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// True when `path` (following symlinks) is a regular file the user may execute.
    public static func isExecutableFile(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return false }
        return access(path, X_OK) == 0
    }

    /// True when `path` exists and is a directory (following symlinks).
    public static func isDirectory(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// A PATH hit before classification.
    public struct Hit: Equatable, Sendable {
        public let path: String
        public let directory: String
        public let realPath: String
    }

    /// Every executable named `tool` on `entries`, first one wins. A directory
    /// listed twice yields one hit (the shell never reaches the second).
    public static func find(_ tool: String, in entries: [String]) -> [Hit] {
        var seenDirectories = Set<String>()
        var hits: [Hit] = []
        for directory in entries where directory.hasPrefix("/") {
            guard seenDirectories.insert(directory).inserted else { continue }
            let candidate = directory == "/" ? "/" + tool : directory + "/" + tool
            guard isExecutableFile(candidate) else { continue }
            let real = realPath(candidate) ?? candidate
            hits.append(Hit(path: candidate, directory: directory, realPath: real))
        }
        return hits
    }
}
