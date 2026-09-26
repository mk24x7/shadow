import SwiftUI
import AppKit
import ShadowCore

@main
struct ShadowApp: App {
    @StateObject private var state = Snapshot.directory != nil ? Snapshot.makeState() : AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .frame(minWidth: 860, minHeight: 540)
                .task {
                    if Snapshot.directory != nil {
                        await Snapshot.run(state: state)
                    } else {
                        state.rescan()
                    }
                }
        }
        .defaultSize(width: 1080, height: 700)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan") { state.rescan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Copy Report") { state.copyReport() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(state.report == nil)
            }
        }
    }
}

enum AppVersion {
    /// CFBundleShortVersionString of the running app, or the library version under `swift run`.
    static var short: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ShadowVersion.current
    }
}

enum Theme {
    static let background = Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
    static let card = Color.white.opacity(0.05)
    static let cardBorder = Color.white.opacity(0.08)

    static func color(for severity: Severity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
