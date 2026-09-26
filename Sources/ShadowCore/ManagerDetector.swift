import Foundation

/// Labels a PATH hit with the manager that installed it and whether it is a shim.
public struct ManagerDetector: Sendable {
    public struct Classification: Equatable, Sendable {
        public let manager: Manager
        public let detail: String?
        public let isShim: Bool
        public let shimTarget: String?
    }

    public let layout: Layout
    /// Resolves an Xcode stub (xcrun --find <tool>); nil when the tools are missing.
    public let xcrunFind: @Sendable (String) -> String?
    /// JAVA_HOME chosen by /usr/libexec/java_home; nil when no JDK is installed.
    public let javaHome: @Sendable () -> String?

    public init(
        layout: Layout,
        xcrunFind: @escaping @Sendable (String) -> String? = ManagerDetector.liveXcrunFind,
        javaHome: @escaping @Sendable () -> String? = ManagerDetector.liveJavaHome
    ) {
        self.layout = layout
        self.xcrunFind = xcrunFind
        self.javaHome = javaHome
    }

    public func classify(tool: String, path: String, directory: String, realPath: String) -> Classification {
        if let shim = shimClassification(tool: tool, path: path, directory: directory, realPath: realPath) {
            return shim
        }
        if let (manager, detail) = install(for: realPath, directory: nil) {
            return Classification(manager: manager, detail: detail, isShim: false, shimTarget: nil)
        }
        if let (manager, detail) = install(for: path, directory: directory) {
            return Classification(manager: manager, detail: detail, isShim: false, shimTarget: nil)
        }
        return Classification(manager: .unknown, detail: nil, isShim: false, shimTarget: nil)
    }

    // MARK: - Shims

    private func shimClassification(tool: String, path: String, directory: String, realPath: String) -> Classification? {
        let home = layout.home
        let shimDirs: [(String, Manager)] = [
            (home + "/.volta/bin", .volta),
            (home + "/.asdf/shims", .asdf),
            (home + "/.local/share/mise/shims", .mise),
            (home + "/.local/share/rtx/shims", .mise),
            (home + "/.pyenv/shims", .pyenv),
            (home + "/.rbenv/shims", .rbenv),
            (home + "/.jenv/shims", .jenv),
            (home + "/.nodenv/shims", .nodenv),
        ]
        for (dir, manager) in shimDirs where directory == dir {
            return Classification(manager: manager, detail: nil, isShim: true, shimTarget: nil)
        }
        if directory == home + "/.cargo/bin",
           Tools.rustupProxies.contains(tool) || (realPath as NSString).lastPathComponent == "rustup" {
            return Classification(manager: .rustup, detail: nil, isShim: true, shimTarget: nil)
        }
        if layout.systemDirectories.contains(directory) {
            if ManagerDetector.fileContains(path, marker: "libxcselect") {
                return Classification(manager: .xcode, detail: "xcrun stub", isShim: true, shimTarget: xcrunFind(tool))
            }
            if Tools.javaStubTools.contains(tool)
                && (ManagerDetector.fileContains(path, marker: "JavaLaunching")
                    || ManagerDetector.fileContains(path, marker: "JavaVM")) {
                let target = javaHome().map { PathResolver.trimSlash($0) + "/bin/" + tool }
                return Classification(manager: .javaStub, detail: nil, isShim: true, shimTarget: target)
            }
        }
        return nil
    }

    // MARK: - Installs

    /// Manager for a concrete location. `directory` is set when classifying the
    /// unresolved path, which enables the directory-only fallbacks.
    private func install(for path: String, directory: String?) -> (Manager, String?)? {
        let home = layout.home

        if let v = component(after: home + "/.nvm/versions/node/", in: path) { return (.nvm, v) }
        if path.contains("/fnm_multishells/") { return (.fnm, "multishell") }
        for base in [home + "/Library/Application Support/fnm/node-versions/",
                     home + "/.fnm/node-versions/",
                     home + "/.local/share/fnm/node-versions/"] {
            if let v = component(after: base, in: path) { return (.fnm, v) }
        }
        if let rest = components(after: home + "/.volta/tools/image/", in: path, count: 2) {
            return (.volta, rest.joined(separator: " "))
        }
        if let rest = components(after: home + "/.asdf/installs/", in: path, count: 2) {
            return (.asdf, rest.joined(separator: " "))
        }
        for base in [home + "/.local/share/mise/installs/", home + "/.local/share/rtx/installs/"] {
            if let rest = components(after: base, in: path, count: 2) {
                return (.mise, rest.joined(separator: " "))
            }
        }
        if let v = component(after: home + "/.pyenv/versions/", in: path) { return (.pyenv, v) }
        if let v = component(after: home + "/.rbenv/versions/", in: path) { return (.rbenv, v) }
        if let v = component(after: home + "/.jenv/versions/", in: path) { return (.jenv, v) }
        if let v = component(after: home + "/.nodenv/versions/", in: path) { return (.nodenv, v) }
        if let rest = components(after: home + "/.sdkman/candidates/", in: path, count: 2) {
            return (.sdkman, rest.joined(separator: " "))
        }
        if let v = component(after: home + "/.rustup/toolchains/", in: path) { return (.rustup, v) }

        if let conda = condaDetail(path) { return (.conda, conda) }

        if let v = component(after: layout.rooted("/Library/Frameworks/Python.framework/Versions/"), in: path) {
            return (.pythonOrg, v)
        }
        if path.hasPrefix(layout.rooted("/Applications/Docker.app/")) || path.hasPrefix(home + "/.docker/bin/") {
            return (.dockerDesktop, nil)
        }
        if path.hasPrefix(home + "/Library/Application Support/JetBrains/Toolbox/") {
            return (.jetbrains, nil)
        }
        for base in [layout.rooted("/Library/Java/JavaVirtualMachines/"), home + "/Library/Java/JavaVirtualMachines/"] {
            if let jdk = component(after: base, in: path) { return (.jdkBundle, jdk) }
        }
        if path.hasPrefix(layout.rooted("/Applications/Xcode")) && path.contains(".app/Contents/Developer/") {
            return (.xcode, nil)
        }
        if path.hasPrefix(layout.rooted("/Library/Developer/CommandLineTools/")) {
            return (.xcode, "Command Line Tools")
        }

        for prefix in layout.homebrewPrefixes {
            if let keg = component(after: prefix + "/Cellar/", in: path) { return (.homebrew, keg) }
            if let cask = component(after: prefix + "/Caskroom/", in: path) { return (.homebrew, "cask " + cask) }
            if let keg = component(after: prefix + "/opt/", in: path) { return (.homebrew, keg) }
        }
        // /opt/homebrew belongs to Homebrew entirely; /usr/local is shared, so
        // only its Cellar, Caskroom and opt count unless it is a brew prefix
        // with no other owner (handled by the directory fallback below).
        for prefix in layout.homebrewPrefixes where !prefix.hasSuffix("/usr/local") {
            if path.hasPrefix(prefix + "/") { return (.homebrew, nil) }
        }

        if path.hasPrefix(layout.rooted("/usr/local/go/")) { return (.goInstaller, nil) }
        if path.hasPrefix(home + "/go/bin/") { return (.goInstall, nil) }
        if path.hasPrefix(home + "/.cargo/bin/") { return (.cargoInstall, nil) }
        if path.hasPrefix(home + "/.bun/") { return (.bunInstaller, nil) }
        if path.hasPrefix(home + "/.deno/") { return (.denoInstaller, nil) }
        if path.hasPrefix(home + "/Library/pnpm/") { return (.pnpmStandalone, nil) }
        if path.hasPrefix(home + "/.local/bin/") { return (.localBin, nil) }
        if path.hasPrefix("/opt/local/") { return (.macports, nil) }
        if path.hasPrefix("/nix/") || path.hasPrefix(home + "/.nix-profile/") || path.hasPrefix("/run/current-system/") {
            return (.nix, nil)
        }
        if path.hasPrefix("/System/") { return (.system, nil) }
        for dir in layout.systemDirectories where path.hasPrefix(dir + "/") {
            return (.system, nil)
        }

        if let directory {
            for prefix in layout.homebrewPrefixes where prefix.hasSuffix("/usr/local") {
                if directory == prefix + "/bin" || directory == prefix + "/sbin" {
                    return (.usrLocal, nil)
                }
            }
        }
        return nil
    }

    private func condaDetail(_ path: String) -> String? {
        let home = layout.home
        var roots = ["miniconda3", "anaconda3", "miniforge3", "mambaforge", "micromamba",
                     "opt/miniconda3", "opt/anaconda3", "opt/miniforge3"].map { home + "/" + $0 + "/" }
        roots += ["/opt/miniconda3/", "/opt/anaconda3/", "/opt/miniforge3/"].map(layout.rooted)
        for prefix in layout.homebrewPrefixes {
            roots += ["miniconda/base/", "miniforge/base/", "anaconda/base/"].map { prefix + "/Caskroom/" + $0 }
        }
        for root in roots where path.hasPrefix(root) {
            if let env = component(after: root + "envs/", in: path) { return "env " + env }
            return "base"
        }
        return nil
    }

    private func component(after base: String, in path: String) -> String? {
        components(after: base, in: path, count: 1)?.first
    }

    /// The `count` path components that follow `base` in `path`, if all exist
    /// and at least one more component follows them.
    private func components(after base: String, in path: String, count: Int) -> [String]? {
        guard path.hasPrefix(base) else { return nil }
        let rest = path.dropFirst(base.count).split(separator: "/").map(String.init)
        guard rest.count > count else { return nil }
        return Array(rest.prefix(count))
    }

    // MARK: - Live resolvers

    public static let liveXcrunFind: @Sendable (String) -> String? = { tool in
        guard let result = ProcessRunner.run(["/usr/bin/xcrun", "--find", tool], timeout: 5),
              result.status == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }

    public static let liveJavaHome: @Sendable () -> String? = {
        guard let result = ProcessRunner.run(["/usr/libexec/java_home"], timeout: 5),
              result.status == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }

    /// True when the first megabyte of the file contains `marker`.
    static func fileContains(_ path: String, marker: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty else { return false }
        return data.range(of: Data(marker.utf8)) != nil
    }
}
