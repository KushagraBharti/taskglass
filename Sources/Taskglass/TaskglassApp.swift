import SwiftUI
import AppKit

struct SamplingConfiguration: Equatable {
    let inactive: Bool
    let page: Int
    let interval: Double
}

@main struct TaskglassApp: App {
    @StateObject private var monitor = Monitor()
    init() {
        // Per-launch appearance override for visual QA. Never changes system preferences.
        if CommandLine.arguments.contains("--preview-light") {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
    }
    var body: some Scene {
        Window("Taskglass", id: "main") {
            ContentView(monitor: monitor).frame(minWidth: 840, minHeight: 560).task(id: SamplingConfiguration(inactive: monitor.paused || !monitor.visible, page: monitor.page, interval: monitor.interval)) { await monitor.run() }
        }
        .defaultSize(width: 1060, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .commands { CommandGroup(after: .toolbar) { Button(monitor.paused ? "Resume monitoring" : "Pause monitoring") { monitor.paused.toggle() }.keyboardShortcut("p", modifiers: [.command, .shift]) } }
    }
}
