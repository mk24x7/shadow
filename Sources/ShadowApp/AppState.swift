import Foundation
import SwiftUI
import AppKit
import ShadowCore

/// Sidebar selection: one tool, or the PATH overview.
enum SidebarItem: Hashable {
    case path
    case tool(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var report: Report?
    @Published var isScanning = false
    @Published var status = ""
    @Published var selection: SidebarItem? = .path
    @Published var showMissing = false
    /// The context whose winner the detail pane shows.
    @Published var primary: ShellContext = .zshInteractive
    @Published var availableContexts: [ShellContext] = []
    @Published var directory: String = NSHomeDirectory()

    private var captured: [ContextPath] = []
    private let analyzer: Analyzer
    private let layout: ShadowCore.Layout
    private var generation = 0
    /// Snapshot mode only: PATHs to analyse instead of starting shells, and a
    /// fixture root stripped from displayed paths.
    private let fixedContexts: [ContextPath]?
    private let displayRoot: String?

    init() {
        analyzer = Analyzer()
        layout = ShadowCore.Layout.live()
        fixedContexts = nil
        displayRoot = nil
    }

    /// A state that analyses `contexts` against `analyzer` instead of
    /// capturing live shells, showing paths under `displayRoot` as if they
    /// were at the top of the file system. Used by snapshot mode.
    init(analyzer: Analyzer, contexts: [ContextPath], primary: ShellContext,
         directory: String, displayRoot: String) {
        self.analyzer = analyzer
        layout = analyzer.layout
        fixedContexts = contexts
        self.displayRoot = PathResolver.trimSlash(displayRoot)
        self.primary = primary
        self.directory = directory
    }

    var visibleTools: [ToolReport] {
        guard let report else { return [] }
        return report.tools.filter { showMissing || $0.isFound }
    }

    var selectedTool: ToolReport? {
        guard case .tool(let name) = selection else { return nil }
        return report?.tools.first { $0.tool == name }
    }

    func shorten(_ path: String) -> String {
        displayText(layout.shorten(path))
    }

    func shortenText(_ text: String) -> String {
        displayText(text.replacingOccurrences(of: layout.home + "/", with: "~/"))
    }

    /// Strips the snapshot fixture root; returns `text` unchanged otherwise.
    func displayText(_ text: String) -> String {
        guard let displayRoot else { return text }
        return text.replacingOccurrences(of: displayRoot + "/", with: "/")
    }

    /// Captures every shell's PATH again, then analyses.
    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        status = "Starting shells to capture PATH..."
        generation += 1
        let token = generation
        let capture = ShellCapture()
        let contexts = capture.availableContexts
        let analyzer = self.analyzer
        let directory = self.directory
        let fixed = fixedContexts
        let requested = primary
        analyzer.probe.clear()
        Task.detached(priority: .userInitiated) { [weak self] in
            let captured = fixed ?? capture.capture(contexts)
            let usable = captured.filter { $0.path != nil }.map(\.context)
            let primary = fixed != nil && usable.contains(requested)
                ? requested
                : Analyzer.defaultPrimary(loginShell: Analyzer.loginShell(), available: usable)
            await MainActor.run { [weak self] in
                self?.status = "Resolving tools and reading versions..."
            }
            let report = analyzer.analyze(contexts: captured, tools: Tools.defaultSet, directory: directory, primary: primary)
            await MainActor.run { [weak self] in
                guard let self, token == self.generation else { return }
                self.captured = captured
                self.availableContexts = usable
                self.primary = report.primaryContext
                self.apply(report)
                self.isScanning = false
            }
        }
    }

    /// Re-analyses the already captured PATHs (shell or directory changed).
    func reanalyze() {
        guard !captured.isEmpty else { return rescan() }
        isScanning = true
        status = "Resolving tools and reading versions..."
        generation += 1
        let token = generation
        let captured = self.captured
        let analyzer = self.analyzer
        let directory = self.directory
        let primary = self.primary
        Task.detached(priority: .userInitiated) { [weak self] in
            let report = analyzer.analyze(contexts: captured, tools: Tools.defaultSet, directory: directory, primary: primary)
            await MainActor.run { [weak self] in
                guard let self, token == self.generation else { return }
                self.apply(report)
                self.isScanning = false
            }
        }
    }

    private func apply(_ report: Report) {
        self.report = report
        let c = report.counts
        status = "\(c.toolsFound) of \(c.toolsChecked) tools found, \(c.shadowedCopies) shadowed, \(c.warnings) warnings"
        if case .tool(let name) = selection,
           !report.tools.contains(where: { $0.tool == name && ($0.isFound || showMissing) }) {
            selection = .path
        }
    }

    func setPrimary(_ context: ShellContext) {
        guard context != primary else { return }
        primary = context
        reanalyze()
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Shadow reads version files (.nvmrc, .python-version, .tool-versions) in this folder and runs shims from it."
        panel.directoryURL = URL(fileURLWithPath: directory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        directory = url.path
        analyzer.probe.clear()
        reanalyze()
    }

    func copyReport() {
        guard let report else { return }
        let text = ReportFormatter(color: false, includeMissing: showMissing, layout: layout).render(report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Report copied to the clipboard"
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Dot colour for a tool: grey when missing, orange with warnings, green otherwise.
    func dotColor(_ tool: ToolReport) -> Color {
        if !tool.isFound { return .gray }
        if tool.findings.contains(where: { $0.severity >= .warning }) { return .orange }
        return .green
    }
}
