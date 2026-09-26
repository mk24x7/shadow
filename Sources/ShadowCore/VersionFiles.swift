import Foundation

/// Finds per-directory version files that decide what a shim runs.
public enum VersionFiles {
    /// File name -> language, for single-language files.
    public static let singleLanguage: [(name: String, language: String)] = [
        (".nvmrc", "node"),
        (".node-version", "node"),
        (".python-version", "python"),
        (".ruby-version", "ruby"),
        (".java-version", "java"),
        ("rust-toolchain.toml", "rust"),
        ("rust-toolchain", "rust"),
    ]

    /// Managers that read each file (directly or through an option they document).
    public static let readers: [String: Set<String>] = [
        ".nvmrc": ["nvm", "fnm", "mise", "asdf", "nodenv"],
        ".node-version": ["fnm", "nodenv", "mise", "asdf"],
        ".python-version": ["pyenv", "mise", "asdf"],
        ".ruby-version": ["rbenv", "mise", "asdf"],
        ".java-version": ["jenv", "mise", "asdf"],
        ".tool-versions": ["asdf", "mise"],
        "rust-toolchain.toml": ["rustup"],
        "rust-toolchain": ["rustup"],
    ]

    /// .tool-versions plugin name -> language.
    static func toolVersionsLanguage(_ plugin: String) -> String {
        switch plugin {
        case "nodejs", "node": return "node"
        case "python": return "python"
        case "ruby": return "ruby"
        case "java": return "java"
        case "golang", "go": return "go"
        case "rust": return "rust"
        case "php": return "php"
        default: return plugin
        }
    }

    /// Version files that apply in `directory`: for each file name the nearest
    /// one walking up to the filesystem root, as the managers themselves do.
    public static func find(in directory: String) -> [VersionFile] {
        var results: [VersionFile] = []
        var found = Set<String>()
        var current = PathResolver.trimSlash(directory)
        while true {
            for (name, language) in singleLanguage where !found.contains(name) {
                let path = current == "/" ? "/" + name : current + "/" + name
                guard let text = read(path) else { continue }
                found.insert(name)
                if let value = singleValue(name: name, text: text) {
                    results.append(VersionFile(name: name, path: path, language: language, value: value))
                }
            }
            if !found.contains(".tool-versions") {
                let path = current == "/" ? "/.tool-versions" : current + "/.tool-versions"
                if let text = read(path) {
                    found.insert(".tool-versions")
                    results.append(contentsOf: parseToolVersions(text, path: path))
                }
            }
            if current == "/" || current.isEmpty { break }
            current = (current as NSString).deletingLastPathComponent
        }
        return results
    }

    static func read(_ path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size < 65536 else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// The version a single-language file asks for.
    static func singleValue(name: String, text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        if name == "rust-toolchain.toml" {
            for line in lines where line.hasPrefix("channel") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                }
            }
            return nil
        }
        return lines.first
    }

    /// One entry per tool line of a .tool-versions file.
    public static func parseToolVersions(_ text: String, path: String) -> [VersionFile] {
        var results: [VersionFile] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = String(raw)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2 else { continue }
            results.append(VersionFile(
                name: ".tool-versions", path: path,
                language: toolVersionsLanguage(fields[0]), value: fields[1]))
        }
        return results
    }
}
