import Foundation

/// The tool catalogue: default set, language grouping and version arguments.
public enum Tools {
    /// Checked when no tool is named.
    public static let defaultSet: [String] = [
        "node", "npm", "npx", "pnpm", "yarn", "bun", "deno",
        "python", "python3", "pip", "pip3",
        "ruby", "gem", "bundle",
        "java", "javac",
        "go",
        "rustc", "cargo",
        "swift",
        "php", "composer",
        "git", "gh", "brew", "docker", "kubectl", "terraform",
    ]

    /// Language a tool belongs to, used to group managers and version files.
    public static func language(of tool: String) -> String {
        switch tool {
        case "node", "npm", "npx", "pnpm", "yarn", "corepack": return "node"
        case "python", "python3", "pip", "pip3", "pipx": return "python"
        case "ruby", "gem", "bundle", "bundler", "irb": return "ruby"
        case "java", "javac", "jar", "jshell", "javadoc", "keytool": return "java"
        case "go", "gofmt": return "go"
        case "rustc", "cargo", "rustup", "rustfmt", "rustdoc": return "rust"
        case "php", "composer": return "php"
        case "swift", "swiftc": return "swift"
        default:
            // python3.12, pip3.12 and friends
            if tool.hasPrefix("python3") || tool.hasPrefix("pip3") { return "python" }
            return tool
        }
    }

    /// Tools whose version a per-directory version file controls.
    public static func versionControlledTools(for language: String) -> Set<String> {
        switch language {
        case "node": return ["node"]
        case "python": return ["python", "python3"]
        case "ruby": return ["ruby"]
        case "java": return ["java", "javac"]
        case "go": return ["go"]
        case "rust": return ["rustc", "cargo"]
        default: return []
        }
    }

    /// Arguments that print a version.
    public static func versionArguments(for tool: String) -> [String] {
        switch tool {
        case "java", "javac": return ["-version"]
        case "go": return ["version"]
        case "kubectl": return ["version", "--client"]
        default: return ["--version"]
        }
    }

    /// Tools under /usr/bin that dispatch through the Java launcher stub.
    public static let javaStubTools: Set<String> = [
        "java", "javac", "jar", "jarsigner", "javadoc", "javap", "jcmd", "jconsole",
        "jdb", "jdeps", "jhsdb", "jinfo", "jlink", "jmap", "jps", "jrunscript",
        "jshell", "jstack", "jstat", "jstatd", "keytool", "rmiregistry", "serialver",
    ]

    /// rustup proxies installed into ~/.cargo/bin.
    public static let rustupProxies: Set<String> = [
        "rustc", "cargo", "rustup", "rustfmt", "rustdoc", "cargo-fmt", "cargo-clippy",
        "clippy-driver", "rust-analyzer", "rust-gdb", "rust-lldb", "rust-gdbgui", "cargo-miri",
    ]
}
