import SwiftUI
import AppKit
import SystemProbe

@MainActor final class Monitor: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var history: [Point] = []
    @Published var search = ""
    @Published var interval = 2.0
    @Published var paused = false
    @Published var selected: Int32?
    @Published var scope = 0
    @Published var sort = "memory"
    @Published var ascending = false
    @Published var rows: [ProcessRow] = []
    @Published var inspect = false
    @Published var page = 0
    let sampler = Sampler()
    @Published var visible = true
    func arrange() {
        let uid = getuid()
        let appIDs = scope == 2 ? Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)) : []
        rows = snapshot.processes.filter {
            (scope != 1 || $0.uid == uid) && (scope != 2 || appIDs.contains($0.id)) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.id).contains(search))
        }.sorted { a, b in
            let comparison: Bool
            switch sort {
            case "name": comparison = a.name == b.name ? a.id < b.id : a.name.localizedStandardCompare(b.name) == .orderedAscending
            case "pid": comparison = a.id < b.id
            case "cpu": comparison = (a.cpu ?? -1) == (b.cpu ?? -1) ? a.id < b.id : (a.cpu ?? -1) < (b.cpu ?? -1)
            case "uid": comparison = a.uid == b.uid ? a.id < b.id : a.uid < b.uid
            case "read": comparison = (a.readRate ?? -1) == (b.readRate ?? -1) ? a.id < b.id : (a.readRate ?? -1) < (b.readRate ?? -1)
            case "write": comparison = (a.writeRate ?? -1) == (b.writeRate ?? -1) ? a.id < b.id : (a.writeRate ?? -1) < (b.writeRate ?? -1)
            case "resident": comparison = a.resident == b.resident ? a.id < b.id : a.resident < b.resident
            case "threads": comparison = a.threads == b.threads ? a.id < b.id : a.threads < b.threads
            default: comparison = (a.footprint ?? 0) == (b.footprint ?? 0) ? a.id < b.id : (a.footprint ?? 0) < (b.footprint ?? 0)
            }
            return ascending ? comparison : (a == b ? false : !comparison)
        }
    }
    func run() async {
        guard !paused && visible else { await sampler.reset(); return }
        while !Task.isCancelled {
            if !paused && visible {
                let next = await sampler.read()
                guard !Task.isCancelled else { return }
                snapshot = next
                if let cpu = snapshot.cpu {
                    history.append(Point(cpu: cpu, memory: Double(snapshot.used) / Double(max(1, snapshot.total)) * 100))
                    if history.count > 90 { history.removeFirst(history.count - 90) }
                }
                arrange()
            } else { await sampler.reset() }
            do { try await Task.sleep(for: .seconds(interval)) } catch { break }
        }
    }
    var selection: ProcessRow? { snapshot.processes.first { $0.id == selected } }
    func requestQuit(force: Bool) {
        guard let row = selection, row.id != getpid(), row.uid == getuid() else { return }
        let app = NSRunningApplication(processIdentifier: row.id)
        let alert = NSAlert()
        alert.messageText = "\(force ? "Force quit" : "Quit") \(row.name)?"
        alert.informativeText = force ? "Unsaved changes may be lost." : app == nil ? "This process will receive SIGTERM. Unsaved work may be lost." : "The app will receive a request to quit normally."
        alert.addButton(withTitle: force ? "Force quit" : "Quit"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            // Recheck the process identity after confirmation to avoid PID reuse.
            guard selection?.birth == row.birth, tg_matches(row.id, row.birth) != 0 else { return }
            let success: Bool
            if let app { success = force ? app.forceTerminate() : app.terminate() }
            else { success = tg_terminate(row.id, row.birth, force ? 1 : 0) != 0 }
            if !success { let failure = NSAlert(); failure.messageText = "macOS could not quit this app."; failure.runModal() }
        }
    }
}

@main struct TaskglassApp: App {
    @StateObject private var monitor = Monitor()
    var body: some Scene {
        Window("Taskglass", id: "main") {
            ContentView(monitor: monitor).frame(minWidth: 960, minHeight: 620).task(id: monitor.paused || !monitor.visible) { await monitor.run() }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .commands { CommandGroup(after: .toolbar) { Button(monitor.paused ? "Resume monitoring" : "Pause monitoring") { monitor.paused.toggle() }.keyboardShortcut("p", modifiers: [.command, .shift]) } }
    }
}

struct ContentView: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("View", selection: $monitor.page) { Text("Processes").tag(0); Text("Performance").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                        Text(monitor.page == 0 ? "\(monitor.rows.count) shown of \(monitor.snapshot.processes.count) accessible processes" : "Live system metrics").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if monitor.page == 0 {
                    Picker("Show", selection: $monitor.scope) {
                        Text("All processes").tag(0); Text("My processes").tag(1); Text("Apps").tag(2)
                    }.labelsHidden().frame(width: 160)
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search name or PID", text: $monitor.search).textFieldStyle(.plain)
                    }.padding(8).frame(width: 185).glassEffect(.regular, in: Capsule())
                    }
                }.padding(20)
                if monitor.page == 0 {
                    ProcessTable(monitor: monitor)
                    if let row = monitor.selection { inspector(row) }
                } else { performance }
                HStack(spacing: 7) {
                    Circle().fill(monitor.paused || !monitor.visible ? .orange : .green).frame(width: 6, height: 6)
                    Text(monitor.paused ? "Paused" : !monitor.visible ? "Sleeping" : "Live")
                    Spacer()
                    Text("\(monitor.snapshot.processes.reduce(0) { $0 + Int($1.threads) }) threads")
                    Text("·"); Text("Updated \(monitor.snapshot.date.formatted(date: .omitted, time: .standard))")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 34).background(.bar)
            }.background(Color(nsColor: .textBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .principal) { Label("Taskglass", systemImage: "waveform.path.ecg").font(.headline) }
            ToolbarItem { Picker("Refresh interval", selection: $monitor.interval) { Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0) }.labelsHidden().frame(width: 110).help("Sampling interval. Longer intervals reduce overhead.") }
            ToolbarItem { Button { monitor.paused.toggle() } label: { Image(systemName: monitor.paused ? "play.fill" : "pause.fill") }.help(monitor.paused ? "Resume" : "Pause") }
            ToolbarItem { Button { monitor.inspect.toggle() } label: { Image(systemName: "info.circle") }.help("Measurement details") }
        }
        .onChange(of: monitor.search) { monitor.arrange() }
        .onChange(of: monitor.scope) { monitor.arrange() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in monitor.visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in monitor.visible = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in monitor.visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in monitor.visible = true }
        .sheet(isPresented: $monitor.inspect) { details }
    }
    var performance: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("CPU").font(.title2.weight(.semibold)); Spacer(); Text(percent(monitor.snapshot.cpu)).font(.title2.monospacedDigit()) }
                Sparkline(points: monitor.history, memory: false, color: .indigo).frame(height: 130)
                HStack { Text("Logical cores").font(.headline); Spacer(); Text("0–100% per core").foregroundStyle(.secondary).font(.caption) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Array(monitor.snapshot.cores.enumerated()), id: \.offset) { index, usage in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text("\(index + 1)").foregroundStyle(.secondary); Spacer(); Text(percent(usage)) }.font(.caption).monospacedDigit()
                            ProgressView(value: usage, total: 100).tint(.indigo)
                        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Divider()
                HStack { Text("Memory").font(.title2.weight(.semibold)); Spacer(); Text("\(bytes(monitor.snapshot.used)) / \(bytes(monitor.snapshot.total))").font(.title3.monospacedDigit()) }
                Sparkline(points: monitor.history, memory: true, color: .teal).frame(height: 110)
                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 8) { Text("Wired").foregroundStyle(.secondary); Text(bytes(monitor.snapshot.wired)) }
                    VStack(alignment: .leading, spacing: 8) { Text("Compressed").foregroundStyle(.secondary); Text(bytes(monitor.snapshot.compressed)) }
                    VStack(alignment: .leading, spacing: 8) { Text("Cached files").foregroundStyle(.secondary); Text(bytes(monitor.snapshot.cached)) }
                    VStack(alignment: .leading, spacing: 8) { Text("Swap used").foregroundStyle(.secondary); Text(bytes(monitor.snapshot.swap)) }
                }.font(.callout).monospacedDigit()
                Text("History retains up to 90 samples at the selected interval. Both graphs use a fixed 0–100% scale.").font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "desktopcomputer").foregroundStyle(.secondary); Text("Performance").font(.headline); Spacer() }
            resource("CPU", symbol: "cpu", value: percent(monitor.snapshot.cpu), color: .indigo, memory: false) {
                Text("System \(percent(monitor.snapshot.systemCPU))")
                Text("\(ProcessInfo.processInfo.activeProcessorCount) logical cores")
            }
            resource("Memory", symbol: "memorychip", value: bytes(monitor.snapshot.used), color: .teal, memory: true) {
                Text("\(bytes(monitor.snapshot.total)) installed")
                HStack { Circle().fill(pressureColor).frame(width: 6, height: 6); Text("\(pressureName) pressure") }
            }
            VStack(spacing: 9) {
                stat("Wired", bytes(monitor.snapshot.wired)); stat("Compressed", bytes(monitor.snapshot.compressed))
                stat("Cached files", bytes(monitor.snapshot.cached)); stat("Swap used", bytes(monitor.snapshot.swap))
            }.font(.caption).padding(.horizontal, 4)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label("Network", systemImage: "network").font(.callout.weight(.medium))
                stat("↓ Receiving", rate(monitor.snapshot.download)); stat("↑ Sending", rate(monitor.snapshot.upload))
                Text("Active physical interfaces").font(.caption2).foregroundStyle(.tertiary)
            }.font(.caption).padding(.horizontal, 4)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                Text("This Mac").font(.caption.weight(.medium)).lineLimit(1)
                Text("Thermal state: \(thermal)").font(.caption).foregroundStyle(.secondary)
                Text("Uptime \(Int(ProcessInfo.processInfo.systemUptime / 3600))h").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
        }.padding(18).background(.regularMaterial)
    }
    var thermal: String {
        switch ProcessInfo.processInfo.thermalState { case .nominal: "Nominal"; case .fair: "Fair"; case .serious: "Serious"; case .critical: "Critical"; @unknown default: "Unknown" }
    }
    var pressureName: String { switch monitor.snapshot.pressure { case 1: "Normal"; case 2: "Elevated"; case 4: "Critical"; default: "Unknown" } }
    var pressureColor: Color { switch monitor.snapshot.pressure { case 1: .green; case 2: .orange; case 4: .red; default: .secondary } }
    func stat(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
    func resource<Detail: View>(_ name: String, symbol: String, value: String, color: Color, memory: Bool, @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Label(name, systemImage: symbol).font(.callout.weight(.medium)); Spacer() }.foregroundStyle(color)
            Text(monitor.snapshot.valid ? value : "—").font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
            Sparkline(points: monitor.history, memory: memory, color: color).frame(height: 42).accessibilityLabel("\(name) history, up to 90 samples")
            VStack(alignment: .leading, spacing: 4, content: detail).font(.caption).foregroundStyle(.secondary)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.12)))
    }
    func inspector(_ row: ProcessRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Image(systemName: "app").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) { Text(row.name).font(.headline); Text("PID \(row.id) · Parent \(row.parent) · User ID \(row.uid)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if let path = row.path {
                    Button("Show executable") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
                Button("Quit") { monitor.requestQuit(force: false) }.disabled(row.uid != getuid() || row.id == getpid())
                Button("Force quit") { monitor.requestQuit(force: true) }.disabled(row.uid != getuid() || row.id == getpid())
            }.padding(.horizontal, 18)
            HStack(spacing: 25) {
                Label("\(percent(row.cpu)) CPU", systemImage: "cpu")
                Label("\(row.footprint.map(bytes) ?? "Unavailable") footprint", systemImage: "memorychip")
                Text("\(bytes(row.resident)) resident"); Text("\(row.threads) threads")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18)
            if let path = row.path { Text(path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).textSelection(.enabled).padding(.horizontal, 18) }
            Spacer().frame(height: 1)
        }
    }
    var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About these measurements").font(.title2.weight(.semibold))
            Text("CPU uses the difference between kernel counters at each sample. System CPU is normalized to 100%. Process CPU reaches 100% per logical core and can exceed 100%.")
            Text("Memory shows physical footprint when macOS allows access. A dash means access is unavailable. Resident memory is a separate column and may include shared pages. The system's used memory is internal pages minus purgeable pages, plus wired and compressed memory.")
            Text("Process disk rates use physical disk I/O counters. Cached file access is not disk I/O. Scroll the table horizontally for disk and user columns.")
            Text("Network rates sum active en interfaces, avoiding virtual interfaces that can count traffic twice. They include local traffic. GPU, temperatures, energy impact and per-process network activity are not exposed here.")
            Text("Sampling pauses while minimized, hidden, or manually paused. Graphs retain up to 90 samples in memory. No telemetry or history files are written.")
            HStack { Spacer(); Button("Done") { monitor.inspect = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 540).font(.callout)
    }
}

struct PlotShape: Shape {
    let points: [Point]
    let memory: Bool
    let filled: Bool
    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        var line = Path()
        for (index, p) in points.enumerated() {
            let point = CGPoint(x: rect.width * Double(index) / Double(points.count - 1), y: rect.height * (1 - min(100, max(0, memory ? p.memory : p.cpu)) / 100))
            if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        if filled { line.addLine(to: CGPoint(x: rect.width, y: rect.height)); line.addLine(to: CGPoint(x: 0, y: rect.height)); line.closeSubpath() }
        return line
    }
}
struct Sparkline: View {
    let points: [Point]
    let memory: Bool
    let color: Color
    var body: some View {
        PlotShape(points: points, memory: memory, filled: true)
            .fill(LinearGradient(colors: [color.opacity(0.2), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            .overlay(PlotShape(points: points, memory: memory, filled: false).stroke(color, lineWidth: 1.5))
            .accessibilityLabel(memory ? "Memory history" : "CPU history")
    }
}
