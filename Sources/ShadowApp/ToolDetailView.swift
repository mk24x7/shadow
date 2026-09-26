import SwiftUI
import ShadowCore

struct ToolDetailView: View {
    @EnvironmentObject var state: AppState
    let tool: ToolReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let winner = tool.winner {
                    WinnerCard(tool: tool, winner: winner)
                } else {
                    Card(title: "Winner") {
                        Text(tool.isFound
                             ? "\(tool.tool) is not on the \(state.primary.label) PATH; other contexts have it."
                             : "\(tool.tool) is not on any captured PATH.")
                            .foregroundColor(.secondary)
                    }
                }
                if !tool.copies.isEmpty {
                    CopiesTable(tool: tool)
                }
                if !tool.differences.isEmpty {
                    Card(title: "Where contexts disagree") {
                        ForEach(tool.contextWinners, id: \.context) { winner in
                            HStack(alignment: .firstTextBaseline) {
                                Text(winner.context.label)
                                    .font(.system(.callout, design: .monospaced))
                                    .frame(width: 80, alignment: .leading)
                                Text(winner.path.map(state.shorten) ?? "not found")
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundColor(winner.path == tool.winner?.path ? .primary : .orange)
                                    .textSelection(.enabled)
                                Spacer()
                                Text(winner.context.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Card(title: "Findings") {
                    if tool.findings.isEmpty {
                        Text("Nothing to report: every context agrees and nothing is shadowed unexpectedly.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(tool.findings.enumerated()), id: \.offset) { _, finding in
                            FindingRow(finding: finding)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(state.dotColor(tool)).frame(width: 10, height: 10)
            Text(tool.tool)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
            Text(tool.language)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(tool.copies.count) " + (tool.copies.count == 1 ? "copy" : "copies"))
                .foregroundColor(.secondary)
        }
    }
}

struct WinnerCard: View {
    @EnvironmentObject var state: AppState
    let tool: ToolReport
    let winner: Copy

    var body: some View {
        Card(title: "Winner in \(state.primary.label)") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(winner.version ?? "version unknown")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(winner.managerLabel)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    if winner.isShim {
                        Text("SHIM")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.3)))
                    }
                }
                Text(state.shorten(winner.path))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                if let target = winner.shimTarget {
                    Text("dispatches to " + state.shorten(target))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                } else if winner.realPath != winner.path && !winner.isShim {
                    Text("resolves to " + state.shorten(winner.realPath))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                if let error = winner.versionError {
                    Text("version: " + error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Divider().padding(.vertical, 4)
                if let because = tool.because {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("because")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(state.shorten(because.file)):\(because.line)")
                                .font(.system(.callout, design: .monospaced))
                            Text(because.text)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.green)
                                .textSelection(.enabled)
                            if let note = because.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Reveal rc file") { state.reveal(because.file) }
                    }
                    if !tool.alsoMentioned.isEmpty {
                        DisclosureGroup("Also mentioned in \(tool.alsoMentioned.count) other line(s)") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(tool.alsoMentioned.enumerated()), id: \.offset) { _, line in
                                    Text("\(state.shorten(line.file)):\(line.line)  \(line.text)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                    }
                } else {
                    Text("No rc-file line adds \(state.shorten(winner.directory)); it is inherited from the parent environment or set by a tool.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct CopiesTable: View {
    @EnvironmentObject var state: AppState
    let tool: ToolReport

    var body: some View {
        Card(title: "All copies (PATH order)") {
            Table(tool.copies) {
                TableColumn("Path") { copy in
                    HStack(spacing: 6) {
                        if copy.path == tool.winner?.path {
                            Image(systemName: "crown.fill").foregroundColor(.yellow).font(.caption2)
                        }
                        Text(state.shorten(copy.path))
                            .font(.system(.callout, design: .monospaced))
                            .help(copy.realPath)
                    }
                }
                .width(min: 220, ideal: 320)
                TableColumn("Version") { copy in
                    Text(copy.version ?? "-")
                        .help(copy.versionLine ?? copy.versionError ?? "")
                }
                .width(min: 60, ideal: 80)
                TableColumn("Manager") { copy in
                    Text(copy.managerLabel)
                }
                .width(min: 100, ideal: 160)
                TableColumn("Shim") { copy in
                    Text(copy.isShim ? "yes" : "")
                }
                .width(40)
                TableColumn("Wins in") { copy in
                    Text(copy.winsIn.isEmpty ? "shadowed" : copy.winsIn.map(\.label).joined(separator: ", "))
                        .foregroundColor(copy.winsIn.isEmpty ? .secondary : .primary)
                        .help("On PATH in: " + copy.presentIn.map(\.label).joined(separator: ", "))
                }
                .width(min: 100, ideal: 200)
            }
            .frame(height: CGFloat(min(tool.copies.count, 8)) * 26 + 32)
        }
    }
}

struct PathOverviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("PATH overview")
                    .font(.system(size: 22, weight: .semibold))
                if let report = state.report {
                    Card(title: "Summary") {
                        let c = report.counts
                        HStack(spacing: 28) {
                            stat("\(c.toolsFound)/\(c.toolsChecked)", "tools found")
                            stat("\(c.shadowedCopies)", "shadowed copies")
                            stat("\(c.warnings)", "warnings")
                            stat("\(c.infos)", "info")
                        }
                        if !report.versionFiles.isEmpty {
                            Text("Version files: " + report.versionFiles.map { "\($0.name) = \($0.value)" }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Card(title: "Contexts") {
                        ForEach(report.contexts, id: \.context) { context in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(context.context.label)
                                        .font(.system(.callout, design: .monospaced))
                                        .frame(width: 80, alignment: .leading)
                                    Text(context.context.summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(context.path == nil ? (context.error ?? "failed") : "\(context.entries.count) entries")
                                        .font(.caption)
                                        .foregroundColor(context.path == nil ? .orange : .secondary)
                                }
                            }
                        }
                    }
                    Card(title: "PATH findings") {
                        if report.findings.isEmpty {
                            Text("No missing or duplicated PATH entries.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                                FindingRow(finding: finding)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}
