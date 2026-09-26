import SwiftUI
import ShadowCore

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            DetailColumn()
        }
    }
}

/// Toolbar, the selected tool or the PATH overview, and the status bar.
struct DetailColumn: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ToolbarRow()
            Divider()
            Group {
                if state.report == nil {
                    ScanningPlaceholder()
                } else if let tool = state.selectedTool {
                    ToolDetailView(tool: tool)
                } else {
                    PathOverviewView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            StatusBar()
        }
        .background(Theme.background)
    }
}

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List(selection: $state.selection) {
            Section("Overview") {
                Label {
                    HStack {
                        Text("PATH")
                        Spacer()
                        if let count = state.report?.findings.count, count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                }
                .tag(SidebarItem.path)
            }
            Section("Tools") {
                ForEach(state.visibleTools) { tool in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.dotColor(tool))
                            .frame(width: 8, height: 8)
                        Text(tool.tool)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if let version = tool.winner?.version {
                            Text(version)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(SidebarItem.tool(tool.tool))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Toggle("Show tools not found", isOn: $state.showMissing)
                .toggleStyle(.checkbox)
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ToolbarRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Text("Shadow")
                .font(.system(size: 13, weight: .semibold))
            Spacer()

            Picker("Shell", selection: Binding(
                get: { state.primary },
                set: { state.setPrimary($0) }
            )) {
                ForEach(state.availableContexts, id: \.self) { context in
                    Text(context.label).tag(context)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
            .disabled(state.availableContexts.isEmpty || state.isScanning)
            .help("Which context's winner to show")

            Button(action: state.chooseDirectory) {
                Label(state.shorten(state.directory), systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 220)
            .help("Working directory for version files and shims")
            .disabled(state.isScanning)

            Button(action: state.copyReport) {
                Label("Copy report", systemImage: "doc.on.doc")
            }
            .disabled(state.report == nil)

            Button(action: state.rescan) {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(state.isScanning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct StatusBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            if state.isScanning {
                ProgressView().controlSize(.small)
            }
            Text(state.status)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("Read-only. Shadow never edits rc files or PATH.")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("v\(AppVersion.short)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

struct ScanningPlaceholder: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(state.status.isEmpty ? "Scanning..." : state.status)
                .foregroundColor(.secondary)
            Text("Shadow starts zsh, bash, sh and fish the way a terminal would to capture each PATH.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// A rounded card used by the detail views.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cardBorder))
    }
}

struct FindingRow: View {
    @EnvironmentObject var state: AppState
    let finding: Finding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(finding.severity.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.color(for: finding.severity).opacity(0.25)))
                .foregroundColor(Theme.color(for: finding.severity))
            Text(state.shortenText(finding.message))
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
