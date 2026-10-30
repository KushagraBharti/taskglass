import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: Monitor
    var body: some View {
        VStack(spacing: 0) {
            if monitor.page == 0 {
                ProcessTable(monitor: monitor)
                Divider()
                summary
            } else { performance }
            status
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $monitor.page) { Text("Processes").tag(0); Text("Performance").tag(1) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if monitor.page == 0 {
                    Menu {
                        Picker("Show", selection: $monitor.scope) {
                            Text("All processes").tag(0); Text("My processes").tag(1); Text("Applications").tag(2)
                        }
                        Divider()
                        Section("Columns") {
                            Toggle("Resident memory", isOn: $monitor.showResident)
                            Toggle("Disk activity", isOn: $monitor.showDisk)
                            Toggle("User ID", isOn: $monitor.showUser)
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .help("Filter processes and choose columns")
                    NativeSearch(monitor: monitor).frame(width: 180)
                }
                Button { monitor.paused.toggle() } label: { Image(systemName: monitor.paused ? "play" : "pause") }
                    .help(monitor.paused ? "Resume monitoring" : "Pause monitoring")
                Button { monitor.showingInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help("Show process inspector").disabled(monitor.page != 0)
                Menu {
                    Picker("Update frequency", selection: $monitor.interval) {
                        Text("Every second").tag(1.0); Text("Every 2 seconds").tag(2.0); Text("Every 5 seconds").tag(5.0)
                    }
                    Divider()
                    Button("About these measurements") { monitor.inspect = true }
                } label: { Image(systemName: "ellipsis") }.help("Monitoring options")
            }
        }
        .inspector(isPresented: $monitor.showingInspector) { inspector.inspectorColumnWidth(min: 250, ideal: 270, max: 340) }
        .onChange(of: monitor.search) { monitor.arrange() }
        .onChange(of: monitor.scope) { monitor.arrange() }
        .onChange(of: monitor.page) {
            if monitor.page == 0 { monitor.arrange() }
            else { monitor.showingInspector = false; monitor.rows = [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in monitor.visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in monitor.visible = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in monitor.visible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in monitor.visible = true }
        .sheet(isPresented: $monitor.inspect) { details }
    }
    var status: some View {
        HStack(spacing: 6) {
            if monitor.paused || !monitor.visible { Image(systemName: "pause.circle"); Text("Paused") }
            else if monitor.page == 0 { Text("\(monitor.rows.count) of \(monitor.snapshot.processes.count) accessible processes") }
            else { Text("System performance") }
            Spacer()
            if monitor.page == 0 { Text("\(monitor.threadCount) threads") }
            else { Text("\(ProcessInfo.processInfo.activeProcessorCount) logical cores") }
            Text("·")
            Text("\(Int(monitor.interval))s updates")
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 28)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    var summary: some View {
        GeometryReader { geometry in
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                if geometry.size.width > 760 { Sparkline(points: monitor.history, memory: false, color: .accentColor).frame(width: 80, height: 34) }
                VStack(alignment: .leading, spacing: 5) {
                    Text("CPU").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(percent(monitor.snapshot.cpu)).font(.system(size: 16, weight: .medium)).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            Divider().frame(height: 36)
            HStack(spacing: 16) {
                if geometry.size.width > 760 { Sparkline(points: monitor.history, memory: true, color: .accentColor).frame(width: 80, height: 34) }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Memory").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(memoryValue) of \(bytes(monitor.snapshot.total))").font(.system(size: 13, weight: .medium)).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            Divider().frame(height: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("Network").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Label(rate(monitor.snapshot.download), systemImage: "arrow.down")
                    Label(rate(monitor.snapshot.upload), systemImage: "arrow.up")
                }.font(.system(size: 12)).monospacedDigit()
            }.frame(minWidth: 170, alignment: .leading)
        }.padding(.horizontal, 20).frame(maxHeight: .infinity)
        }.frame(height: 78).background(Color(nsColor: .windowBackgroundColor))
    }
    var performance: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline) {
                    Text("This Mac").font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Text("\(ProcessInfo.processInfo.activeProcessorCount) cores · \(bytes(monitor.snapshot.total)) memory").foregroundStyle(.secondary).font(.callout)
                }
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        metricHeading("CPU", percent(monitor.snapshot.cpu))
                        HistoryGraph(points: monitor.history, memory: false).frame(height: 130)
                        HStack { detail("User", percent(monitor.snapshot.cpu.map { max(0, $0 - monitor.snapshot.systemCPU) })); Spacer(); detail("System", percent(monitor.snapshot.cpu == nil ? nil : monitor.snapshot.systemCPU)); Spacer(); detail("Idle", percent(monitor.snapshot.cpu.map { 100 - $0 })) }
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 16) {
                        metricHeading("Memory", memoryValue)
                        HistoryGraph(points: monitor.history, memory: true).frame(height: 130)
                        HStack { detail("Pressure", pressureName); Spacer(); detail("Compressed", bytes(monitor.snapshot.compressed)); Spacer(); detail("Swap", bytes(monitor.snapshot.swap)) }
                    }.frame(maxWidth: .infinity)
                }
                Divider()
                HStack { Text("Core activity").font(.headline); Spacer(); Text("Utilization per logical core").font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 6), spacing: 18) {
                    ForEach(Array(monitor.snapshot.cores.enumerated()), id: \.offset) { index, usage in
                        VStack(spacing: 7) {
                            HStack { Text("\(index + 1)").foregroundStyle(.secondary); Spacer(); Text(percent(usage)) }.font(.system(size: 11)).monospacedDigit()
                            ProgressView(value: usage, total: 100).tint(.accentColor)
                        }
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Memory allocation").font(.headline)
                        stat("Wired", bytes(monitor.snapshot.wired)); stat("Compressed", bytes(monitor.snapshot.compressed))
                        stat("Cached files", bytes(monitor.snapshot.cached)); stat("Swap used", bytes(monitor.snapshot.swap))
                    }.frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("System").font(.headline)
                        stat("Network received", rate(monitor.snapshot.download)); stat("Network sent", rate(monitor.snapshot.upload))
                        stat("Thermal state", thermal); stat("Uptime", "\(Int(ProcessInfo.processInfo.systemUptime / 3600)) hours")
                    }.frame(maxWidth: .infinity)
                }.font(.callout)
                Text("Up to 90 samples. Graphs use a fixed 0–100% scale.").font(.caption).foregroundStyle(.tertiary)
            }.padding(30)
        }
    }
    var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let row = monitor.selection {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "app").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                    Text(row.name).font(.headline).textSelection(.enabled)
                    Text("Process \(row.id)").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
                Divider()
                stat("CPU", percent(row.cpu)); stat("Memory", row.footprint.map(bytes) ?? "Unavailable")
                stat("Resident", bytes(row.resident)); stat("Threads", String(row.threads))
                stat("Disk read", rate(row.readRate)); stat("Disk write", rate(row.writeRate))
                stat("Parent PID", String(row.parent)); stat("User ID", String(row.uid))
                if let path = row.path {
                    Divider()
                    Text("Executable").font(.caption).foregroundStyle(.secondary)
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(5).truncationMode(.middle)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                }
                Spacer()
                HStack { Button("Quit") { monitor.requestQuit(force: false) }; Button("Force quit") { monitor.requestQuit(force: true) } }
                    .disabled(row.uid != getuid() || row.id == getpid())
            } else {
                Spacer(); Text("Select a process to inspect it.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity); Spacer()
            }
        }.font(.system(size: 12)).padding(20)
    }
    func metricHeading(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(name).font(.headline); Spacer(); Text(value).font(.system(size: 24, weight: .medium)).monospacedDigit() }
    }
    func detail(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).monospacedDigit() }
    }
    func stat(_ name: String, _ value: String) -> some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
    var memoryValue: String { monitor.snapshot.valid ? bytes(monitor.snapshot.used) : "—" }
    var pressureName: String { switch monitor.snapshot.pressure { case 1: "Normal"; case 2: "Elevated"; case 4: "Critical"; default: "Unavailable" } }
    var thermal: String {
        switch ProcessInfo.processInfo.thermalState { case .nominal: "Nominal"; case .fair: "Fair"; case .serious: "Serious"; case .critical: "Critical"; @unknown default: "Unknown" }
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
