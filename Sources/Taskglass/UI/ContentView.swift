import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var monitor: Monitor
    var pane: ResourcePane { monitor.pane ?? .overview }
    var body: some View {
        NavigationSplitView {
            List(selection: $monitor.pane) {
                Label("Overview", systemImage: ResourcePane.overview.icon).foregroundStyle(Color(white: 0.88)).tag(ResourcePane.overview)
                Label("Processes", systemImage: ResourcePane.processes.icon).foregroundStyle(Color(white: 0.88)).tag(ResourcePane.processes)
                Section("Resources") {
                    ForEach(ResourcePane.allCases.filter { $0 != .overview && $0 != .processes && ($0 != .battery || monitor.batteryPresent) }) { resource in
                        ResourceRailRow(monitor: monitor, pane: resource).tag(resource)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 270)
            .navigationTitle("Taskglass")
        } detail: {
            VStack(spacing: 0) {
                if pane == .processes { ProcessWorkspace(monitor: monitor) }
                else { PerformanceWorkspace(monitor: monitor, pane: pane) }
            }
            .background(Color.black)
            .navigationTitle(pane.title)
            .modifier(WindowSubtitle(monitor: monitor, pane: pane))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if pane == .processes {
                        Menu {
                            Picker("Show", selection: $monitor.scope) {
                                Text("All processes").tag(0); Text("My processes").tag(1); Text("Applications").tag(2)
                            }
                            Divider()
                            Section("Columns") {
                                Toggle("GPU time", isOn: $monitor.showGPU)
                                Toggle("Neural Engine memory", isOn: $monitor.showNeuralMemory)
                                Toggle("Resident memory", isOn: $monitor.showResident)
                                Toggle("Disk activity", isOn: $monitor.showDisk)
                                Toggle("User", isOn: $monitor.showUser)
                            }
                        } label: {
                            Image(systemName: monitor.scope == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                        .help(monitor.scope == 0 ? "Filter processes and choose columns" : "Filtered: \(scopeName). Choose columns")
                        .accessibilityLabel("Filter and columns")
                        NativeSearch(monitor: monitor).frame(width: 180)
                        Button { monitor.showingInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                            .help(monitor.showingInspector ? "Hide inspector" : "Show inspector")
                            .accessibilityLabel("Inspector")
                    } else {
                        Menu {
                            Picker("History window", selection: $monitor.historySeconds) {
                                Text("1 minute").tag(60.0); Text("3 minutes").tag(180.0); Text("10 minutes").tag(600.0)
                            }
                        } label: { Label("\(Int(monitor.historySeconds / 60)) min", systemImage: "clock").labelStyle(.titleAndIcon) }
                            .help("History window: \(windowName(monitor.historySeconds))")
                    }
                    Button { monitor.paused.toggle() } label: { Image(systemName: monitor.paused ? "play" : "pause") }
                        .help(monitor.paused ? "Resume monitoring (⇧⌘P)" : "Pause monitoring (⇧⌘P)")
                        .accessibilityLabel(monitor.paused ? "Resume monitoring" : "Pause monitoring")
                    Menu {
                        Picker("Update frequency", selection: $monitor.interval) {
                            Text("Every second").tag(1.0); Text("Every 2 seconds").tag(2.0); Text("Every 5 seconds").tag(5.0)
                        }
                        Divider()
                        Button("About These Measurements…") { monitor.inspect = true }
                    } label: { Image(systemName: "ellipsis") }
                        .help("Monitoring options")
                        .accessibilityLabel("Monitoring options")
                }
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.black, for: .windowToolbar)
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $monitor.showingInspector) {
            ProcessInspector(monitor: monitor).inspectorColumnWidth(min: 250, ideal: 280, max: 340)
        }
        .onChange(of: monitor.search) { monitor.arrange() }
        .onChange(of: monitor.historySeconds) {
            let cutoff = ProcessInfo.processInfo.systemUptime - monitor.historySeconds
            monitor.history.removeAll { $0.time < cutoff }
        }
        .onChange(of: monitor.scope) { monitor.arrange() }
        // No re-rank on a ranking change: resourceLeaders is an unsorted source the outline orders itself.
        // Restore this pane's remembered ranking and load its rows.
        .onChange(of: monitor.pane) { monitor.activatePane(pane) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in monitor.visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in monitor.visible = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in monitor.visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in monitor.visible = true }
        .sheet(isPresented: $monitor.inspect) { MeasurementNotes { monitor.inspect = false } }
    }

    private var scopeName: String { monitor.scope == 1 ? "My processes" : monitor.scope == 2 ? "Applications" : "All processes" }
}

/// Keep live subtitle counts out of the window's navigation/toolbar body.
private struct WindowSubtitle: ViewModifier {
    let monitor: Monitor
    let pane: ResourcePane
    func body(content: Content) -> some View { content.navigationSubtitle(subtitle) }
    private var subtitle: String {
        if monitor.paused { return "Paused" }
        guard pane == .processes else { return monitor.chipName }
        let shown = monitor.rows.count, total = monitor.accessibleProcessCount
        if total > 0 && shown != total { return "\(shown) of \(total) processes" }
        return "\(shown) processes, \(monitor.threadCount.formatted()) threads"
    }
}

private struct ProcessWorkspace: View {
    @Bindable var monitor: Monitor
    var body: some View {
        ProcessTable(monitor: monitor)
            .overlay {
                if monitor.rows.isEmpty {
                    VStack(spacing: 10) {
                        Text(emptyTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            if !monitor.search.isEmpty { Button("Clear Search") { monitor.search = "" } }
                            if monitor.scope != 0 && monitor.accessibleProcessCount > 0 { Button("Show All Processes") { monitor.scope = 0 } }
                        }.controlSize(.small)
                    }
                    .padding(24)
                }
            }
    }
    var emptyTitle: String {
        if monitor.accessibleProcessCount == 0 { return "Reading processes" }
        if !monitor.search.isEmpty { return "No processes match “\(monitor.search)”" }
        return "No \(scopeName.lowercased())"
    }
    var scopeName: String { monitor.scope == 1 ? "My processes" : monitor.scope == 2 ? "Applications" : "All processes" }

}

/// Each rail row observes its own displayed readings. Updating a thumbnail
/// does not rebuild NavigationSplitView, the toolbar or unrelated controls.
private struct ResourceRailRow: View {
    let monitor: Monitor
    let pane: ResourcePane
    private var h: HardwareMetrics { monitor.snapshot.hardware }
    var body: some View {
        let scale = railScale(pane)
        return HStack(spacing: 10) {
            TelemetryPlot(points: monitor.history, layers: [PlotLayer(series: pane.series, color: pane.color, filled: true)],
                          floor: scale.floor, ceiling: scale.ceiling, window: monitor.historySeconds, unit: pane.unit, style: .micro)
                .frame(width: 44, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(pane.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(white: 0.88)).lineLimit(1)
                let value = railValue(pane)
                Text(value).font(.caption11).monospacedDigit().lineLimit(1)
                    .foregroundStyle(Color(white: value == "—" || value == "Not reported" ? 0.48 : 0.64))
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
    func railScale(_ pane: ResourcePane) -> (floor: Double, ceiling: Double) {
        switch pane {
        case .neural: (0, monitor.ceiling([.ane], minimum: 0.1))
        case .storage: (0, monitor.rateCeiling([.diskTotal]))
        case .network: (0, monitor.rateCeiling([.networkTotal]))
        case .temperatures: monitor.temperatureScale
        default: (0, 100)
        }
    }
    func railValue(_ pane: ResourcePane) -> String {
        switch pane {
        case .cpu: percent(monitor.snapshot.cpu)
        case .memory: bytes(monitor.snapshot.used)
        case .gpu: percent(h.gpuUsage)
        case .neural: h.aneWatts == nil ? "Not reported" : power(h.aneWatts)
        case .storage: rate(sum(h.diskRead, h.diskWrite))
        case .network: rate(sum(monitor.snapshot.download, monitor.snapshot.upload))
        case .battery: percent(h.batteryPercent)
        case .temperatures: h.cpuTemperature == nil ? "\(h.temperatures.count) sensors" : "CPU \(temperature(h.cpuTemperature))"
        default: ""
        }
    }
}
