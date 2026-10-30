import SwiftUI
import AppKit

struct SamplingConfiguration: Equatable {
    let inactive: Bool
    let page: Int
    let interval: Double
    let sensorDetails: Bool
}

@main struct TaskglassApp: App {
    // Explicit State storage also builds with Command Line Tools SDKs that
    // do not ship the newer SwiftUI State macro plugin.
    private let monitorState = SwiftUI.State(initialValue: Monitor())
    private var monitor: Monitor { monitorState.wrappedValue }
    init() {
        // Refresh the Dock icon even when Launch Services still has a cached
        // development bundle at this path. The resource is also declared in Info.plist.
        if let url = Bundle.main.url(forResource: "Taskglass", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }
    var body: some Scene {
        Window("Taskglass", id: "main") {
            ContentView(monitor: monitor)
                .background(MonitoringVisibility(monitor: monitor).frame(width: 0, height: 0))
                .frame(minWidth: 1000, minHeight: 660)
                .task(id: SamplingConfiguration(
                    inactive: monitor.paused || !monitor.visible,
                    page: monitor.page,
                    interval: monitor.interval,
                    sensorDetails: monitor.pane == .temperatures
                )) {
                    await monitor.run()
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .help) {
                Link("Taskglass on GitHub", destination: URL(string: "https://github.com/KushagraBharti/taskglass")!)
                Link("Releases and updates", destination: URL(string: "https://github.com/KushagraBharti/taskglass/releases")!)
                Link("Report an issue", destination: URL(string: "https://github.com/KushagraBharti/taskglass/issues/new/choose")!)
                Button("Licenses and acknowledgements") {
                    if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            CommandGroup(after: .toolbar) {
                Button(monitor.paused ? "Resume monitoring" : "Pause monitoring") { monitor.paused.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}
