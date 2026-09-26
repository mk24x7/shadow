import AppKit
import SwiftUI
import ShadowCore

/// Hidden snapshot mode used to regenerate the README screenshot without
/// screen recording permission:
///
///     SHADOW_SNAPSHOT_DIR=/tmp/shadow-shots dist/Shadow.app/Contents/MacOS/Shadow
///
/// No shell is started and nothing on the real machine is read. Snapshot mode
/// builds a throwaway fixture instead: a fake home with rc files, fake
/// Homebrew, nvm, pyenv, Go and JDK trees whose binaries are small scripts
/// that print a version, and PATH strings for four contexts. The report for
/// that fixture is rendered offscreen at 2x into results.png (the node detail
/// view) and the app quits. Displayed paths have the fixture root stripped, so
/// they read like the same set-up on a real Mac.
enum Snapshot {
    static let size = NSSize(width: 1080, height: 700)
    static let scale: CGFloat = 2

    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["SHADOW_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Root of the fixture built by makeState(), removed before quitting.
    @MainActor private static var fixture: SnapshotFixture?

    /// The app state for snapshot mode: analyses the fixture's PATHs with a
    /// layout rooted in the fixture. Falls back to an empty live state (which
    /// run() never scans) if the fixture cannot be written.
    @MainActor
    static func makeState() -> AppState {
        do {
            let fixture = try SnapshotFixture()
            self.fixture = fixture
            let analyzer = Analyzer(
                layout: fixture.layout,
                detector: ManagerDetector(
                    layout: fixture.layout,
                    xcrunFind: { _ in nil },
                    javaHome: { [javaHome = fixture.javaHome] in javaHome }),
                probe: VersionProbe(timeout: 5))
            return AppState(analyzer: analyzer, contexts: fixture.contexts, primary: .zshInteractive,
                            directory: fixture.projectDirectory, displayRoot: fixture.root)
        } catch {
            FileHandle.standardError.write(Data("snapshot: could not build the fixture: \(error)\n".utf8))
            return AppState()
        }
    }

    @MainActor
    static func run(state: AppState) async {
        guard let dir = directory else { return }
        guard fixture != nil else {
            finish(error: "no fixture")
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        state.rescan()
        let deadline = Date().addingTimeInterval(60)
        while state.report == nil || state.isScanning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard state.report != nil else {
            finish(error: "analysis did not finish")
            return
        }
        state.selection = .tool("node")
        await render(state: state, to: dir.appendingPathComponent("results.png"))
        finish(error: nil)
    }

    @MainActor
    private static func finish(error: String?) {
        if let error {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
        }
        if let root = fixture?.root {
            try? FileManager.default.removeItem(atPath: root)
        }
        NSApp.terminate(nil)
    }

    /// Hosts the sidebar and detail column side by side in a borderless window
    /// of the default window size and captures it. NavigationSplitView's
    /// translucent sidebar does not render through cacheDisplay, so it is
    /// replaced by a solid background here.
    @MainActor
    private static func render(state: AppState, to url: URL) async {
        let content = HStack(spacing: 0) {
            SidebarView()
                .frame(width: 220)
                .background(Color(nsColor: .underPageBackgroundColor))
            Divider()
            DetailColumn()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .environmentObject(state)
        .preferredColorScheme(.dark)

        let window = KeyableWindow(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        // Keep the regular app window out of the way so it cannot take key
        // status back and draw the controls inactive in the capture.
        for other in NSApp.windows where !(other is KeyableWindow) { other.orderOut(nil) }
        let host = NSHostingView(rootView: content)
        window.contentView = host
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for _ in 0..<20 where !(NSApp.isActive && window.isKeyWindow) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        host.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }
}

/// Borderless windows cannot become key by default, which draws controls in
/// their inactive state; the snapshot should show the active look.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// A fake machine under a fresh temporary directory, laid out like the test
/// fixture (Tests/ShadowCoreTests/Fixture.swift): home, Homebrew prefixes and
/// system directories all live under `root`, and every binary is a script that
/// prints a version line.
struct SnapshotFixture {
    let root: String
    var home: String { root + "/Users/demo" }
    var projectDirectory: String { home + "/Code/storefront" }
    var javaHome: String { root + "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home" }

    var layout: ShadowCore.Layout {
        ShadowCore.Layout(
            home: home,
            homebrewPrefixes: [root + "/opt/homebrew", root + "/usr/local"],
            systemDirectories: [root + "/usr/bin", root + "/bin", root + "/usr/sbin", root + "/sbin"],
            root: root)
    }

    init() throws {
        var template = Array((NSTemporaryDirectory() as NSString)
            .appendingPathComponent("shadow-snapshot-XXXXXX").utf8CString)
        guard let made = mkdtemp(&template) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        root = PathResolver.realPath(String(cString: made)) ?? String(cString: made)
        try build()
    }

    private let nvmBin = "/.nvm/versions/node/v20.15.0/bin"

    /// PATH per context. zsh -il gets nvm from .zshrc; zsh -l and bash only
    /// get what their profiles add; GUI apps get the launchd default.
    var contexts: [ContextPath] {
        let system = ["/usr/local/bin", "/usr/local/go/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].map { root + $0 }
        let brew = [root + "/opt/homebrew/bin", root + "/opt/homebrew/sbin"]
        let pyenv = home + "/.pyenv/shims"
        let interactive = [home + "/.local/bin", home + nvmBin, pyenv] + brew + system + [root + "/opt/homebrew/bin"]
        let login = [pyenv] + brew + system
        let bash = brew + system
        let gui = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"].map { root + $0 }
        func joined(_ entries: [String]) -> String { entries.joined(separator: ":") }
        return [
            ContextPath(context: .zshInteractive, path: joined(interactive)),
            ContextPath(context: .zshLogin, path: joined(login)),
            ContextPath(context: .bashInteractive, path: joined(bash)),
            ContextPath(context: .gui, path: joined(gui)),
        ]
    }

    private func build() throws {
        // node and npm: nvm (default v20) and Homebrew (22).
        try tool(home + nvmBin + "/node", prints: "v20.15.0")
        try tool(home + nvmBin + "/npm", prints: "10.7.0")
        try brewKeg("node", "22.3.0", tools: ["node": "v22.3.0", "npm": "10.8.1"])

        // python3 and pip3: pyenv shim (3.11.9), Homebrew (3.12.4), macOS (3.9.6).
        try tool(home + "/.pyenv/shims/python3", prints: "Python 3.11.9")
        try tool(home + "/.pyenv/shims/pip3", prints: "pip 24.0 from /pyenv/versions/3.11.9 (python 3.11)")
        try tool(home + "/.pyenv/versions/3.11.9/bin/python3", prints: "Python 3.11.9")
        try brewKeg("python@3.12", "3.12.4", tools: ["python3": "Python 3.12.4",
                                                     "pip3": "pip 24.0 from /python@3.12 (python 3.12)"])
        try tool(root + "/usr/bin/python3", prints: "Python 3.9.6")
        try tool(root + "/usr/bin/pip3", prints: "pip 21.2.4 from /Library (python 3.9)")

        // ruby: Homebrew (3.3.3) and macOS (2.6.10).
        try brewKeg("ruby", "3.3.3", tools: ["ruby": "ruby 3.3.3 (2024-06-12 revision f1c7b6f435) [arm64-darwin23]"])
        try tool(root + "/usr/bin/ruby", prints: "ruby 2.6.10p210 (2022-04-12 revision 67958) [universal.arm64e-darwin23]")

        // go: the go.dev installer in /usr/local/go.
        try tool(root + "/usr/local/go/bin/go", prints: "go version go1.22.4 darwin/arm64")

        // java: the macOS stub dispatching to a Temurin JDK.
        try tool(javaHome + "/bin/java", prints: "openjdk version \"21.0.3\" 2024-04-16 LTS")
        try write(root + "/usr/bin/java", "#!/bin/sh\n# JavaVM launcher stub\nexit 1\n", mode: 0o755)

        // git and brew.
        try brewKeg("git", "2.45.2", tools: ["git": "git version 2.45.2"])
        try tool(root + "/usr/bin/git", prints: "git version 2.39.3 (Apple Git-146)")
        try tool(root + "/opt/homebrew/bin/brew", prints: "Homebrew 4.3.8")
        try mkdir(root + "/opt/homebrew/sbin")
        try mkdir(root + "/usr/local/bin")
        try mkdir(root + "/bin")
        try mkdir(root + "/usr/sbin")
        try mkdir(root + "/sbin")

        // Startup files.
        try write(root + "/etc/paths", ["/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .map { root + $0 }.joined(separator: "\n") + "\n")
        try write(root + "/etc/paths.d/go", root + "/usr/local/go/bin\n")
        try write(home + "/.zprofile", """
            eval "$(/opt/homebrew/bin/brew shellenv)"
            export PYENV_ROOT="$HOME/.pyenv"
            eval "$(pyenv init --path)"

            """)
        try write(home + "/.zshrc", """
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
            export PATH="$HOME/.local/bin:$PATH"

            """)
        try write(home + "/.bash_profile", """
            eval "$(/opt/homebrew/bin/brew shellenv)"

            """)
        try write(projectDirectory + "/.nvmrc", "22\n")
        try write(projectDirectory + "/package.json", "{ \"name\": \"storefront\", \"private\": true }\n")
    }

    /// A Homebrew keg with one script per tool, linked into opt/homebrew/bin.
    private func brewKeg(_ formula: String, _ version: String, tools: [String: String]) throws {
        for (name, output) in tools {
            let relative = "Cellar/\(formula)/\(version)/bin/\(name)"
            try tool(root + "/opt/homebrew/" + relative, prints: output)
            try symlink(root + "/opt/homebrew/bin/" + name, to: "../" + relative)
        }
    }

    private func write(_ path: String, _ contents: String, mode: mode_t = 0o644) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        chmod(path, mode)
    }

    private func tool(_ path: String, prints output: String) throws {
        let quoted = output.replacingOccurrences(of: "'", with: "'\\''")
        try write(path, "#!/bin/sh\nprintf '%s\\n' '\(quoted)'\n", mode: 0o755)
    }

    private func mkdir(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func symlink(_ path: String, to destination: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
    }
}
