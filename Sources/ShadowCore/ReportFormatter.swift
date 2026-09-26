import Foundation

/// Human-readable and JSON renderings of a Report, shared by the CLI and the app.
public struct ReportFormatter {
    public var color: Bool
    /// Shows tools that are not on any captured PATH.
    public var includeMissing: Bool
    public var layout: Layout

    public init(color: Bool = false, includeMissing: Bool = false, layout: Layout = .live()) {
        self.color = color
        self.includeMissing = includeMissing
        self.layout = layout
    }

    // MARK: - JSON

    public static func json(_ report: Report) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Text

    private func paint(_ text: String, _ code: String) -> String {
        color ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
    private func bold(_ s: String) -> String { paint(s, "1") }
    private func dim(_ s: String) -> String { paint(s, "2") }
    private func green(_ s: String) -> String { paint(s, "32") }
    private func yellow(_ s: String) -> String { paint(s, "33") }
    private func red(_ s: String) -> String { paint(s, "31") }
    private func cyan(_ s: String) -> String { paint(s, "36") }

    private func severityTag(_ severity: Severity) -> String {
        switch severity {
        case .error: return red("[error]")
        case .warning: return yellow("[warning]")
        case .info: return cyan("[info]")
        }
    }

    private func short(_ path: String) -> String { layout.shorten(path) }

    /// Replaces every occurrence of the home directory in free text with "~".
    public func shortenText(_ text: String) -> String {
        text.replacingOccurrences(of: layout.home + "/", with: "~/")
    }

    private func copyLine(_ copy: Copy) -> String {
        var parts = [short(copy.path)]
        parts.append(copy.version ?? dim("version unknown"))
        var label = copy.managerLabel
        if copy.isShim { label += ", shim" }
        parts.append(label)
        if let target = copy.shimTarget { parts.append("-> " + short(target)) }
        if copy.realPath != copy.path && !copy.isShim && copy.shimTarget == nil {
            parts.append(dim("-> " + short(copy.realPath)))
        }
        return parts.joined(separator: "  ")
    }

    public func explanationText(_ explanation: Explanation) -> String {
        var text = "\(short(explanation.file)):\(explanation.line) \(explanation.text)"
        if let note = explanation.note { text += "  (\(note))" }
        return text
    }

    /// The block printed for one tool.
    public func toolBlock(_ tool: ToolReport, primary: ShellContext) -> String {
        var lines: [String] = []
        let marker = tool.findings.contains { $0.severity >= .warning } ? yellow("!") : (tool.isFound ? green("*") : dim("-"))
        lines.append("\(marker) \(bold(tool.tool))")
        guard tool.isFound else {
            lines.append("    " + dim("not found on any captured PATH"))
            return lines.joined(separator: "\n")
        }
        if let winner = tool.winner {
            lines.append("    winner   " + copyLine(winner))
        } else {
            lines.append("    winner   " + dim("none on \(primary.label) PATH"))
        }
        let shadowed = tool.shadowed
        if !shadowed.isEmpty {
            lines.append("    shadowed")
            for copy in shadowed {
                var line = "      " + copyLine(copy)
                if !copy.presentIn.contains(primary) {
                    line += "  " + dim("(only on: " + copy.presentIn.map(\.label).joined(separator: ", ") + ")")
                }
                lines.append(line)
            }
        }
        if tool.winner != nil {
            if let because = tool.because {
                lines.append("    because: " + explanationText(because))
            } else {
                lines.append("    because: " + dim("no rc-file line found (inherited from the parent environment or set by a tool)"))
            }
        }
        let differences = tool.differences
        if !differences.isEmpty {
            lines.append("    shells")
            for diff in differences {
                let where_ = diff.path.map(short) ?? dim("not found")
                lines.append("      " + diff.context.label.padding(toLength: 9, withPad: " ", startingAt: 0) + where_)
            }
        }
        for finding in tool.findings {
            lines.append("    " + severityTag(finding.severity) + " " + shortenText(finding.message))
        }
        return lines.joined(separator: "\n")
    }

    public func render(_ report: Report) -> String {
        var out: [String] = []
        let captured = report.contexts.filter { $0.path != nil }.map(\.context.label).joined(separator: ", ")
        out.append(bold("Shadow \(report.shadowVersion)") + dim("  primary: \(report.primaryContext.label)  contexts: \(captured)"))
        out.append(dim("directory: \(short(report.directory))"))
        if !report.versionFiles.isEmpty {
            let files = report.versionFiles.map { "\($0.name)=\($0.value)" + ($0.name == ".tool-versions" ? " (\($0.language))" : "") }
            out.append(dim("version files: " + files.joined(separator: ", ")))
        }
        out.append("")

        for tool in report.tools where tool.isFound || includeMissing {
            out.append(toolBlock(tool, primary: report.primaryContext))
            out.append("")
        }

        if !report.findings.isEmpty {
            out.append(bold("PATH"))
            for finding in report.findings {
                out.append("    " + severityTag(finding.severity) + " " + shortenText(finding.message))
            }
            out.append("")
        }

        let c = report.counts
        out.append("\(c.toolsChecked) tools checked, \(c.toolsFound) found, \(c.shadowedCopies) shadowed "
            + (c.shadowedCopies == 1 ? "copy" : "copies") + "; "
            + "\(c.errors) errors, \(c.warnings) warnings, \(c.infos) info")
        return out.joined(separator: "\n")
    }
}
