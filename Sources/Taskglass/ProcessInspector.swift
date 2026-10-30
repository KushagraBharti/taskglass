import SwiftUI
import AppKit

/// Trailing inspector for the selected process: identity first, then activity with short CPU and memory
/// trends, then the executable. Quit actions stay pinned at the bottom and are disabled, with a reason,
/// for processes the user doesn't own and for any process missing from the latest sample.
struct ProcessInspector: View {
    let monitor: Monitor

    var body: some View {
        Group {
            // `selection` is current and readable; `selectedProcessRecord` falls back to the last observed record.
            if let row = monitor.selectedProcessRecord { detail(row, current: monitor.selection != nil) } else { placeholder }
        }
    }

    var placeholder: some View {
        VStack(spacing: 6) {
            Text(monitor.selected == nil ? "No process selected" : "Process unavailable").font(.system(size: 13, weight: .medium))
            Text(monitor.selected == nil ? "Select a process to see its details." : "It isn't in the latest sample.")
                .font(.caption11).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Trends cover at most the 3 minutes the monitor keeps for the selection.
    var trendWindow: Double { min(monitor.historySeconds, 180) }

    func detail(_ row: ProcessRow, current: Bool) -> some View {
        let parent = current ? monitor.processRecord(row.parent) : nil
        // Footprint and disk rates share one rusage source: no footprint means none of them are readable.
        let readable = row.footprint != nil
        let pending = current ? "Measuring" : "—"
        let points = monitor.processHistory
        let limits = ProcessTrendLimits(points)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    InspectorIdentity(metadata: row.metadata, pid: row.id).equatable()
                    if !current {
                        Notice("Not in the latest sample. It may have exited, or macOS may no longer allow access. Values are the last observed.")
                    }
                    InspectorSection(current ? "Activity" : "Last observed", note: monitor.paused ? "Paused" : "Trends: last \(windowName(trendWindow))") {
                        InspectorRow("CPU", row.cpu.map { percent($0) } ?? pending, help: TableKit.cpuHelp)
                        ProcessTrend(points: points, series: .processCPU, tint: Palette.cpu, unit: .percent,
                                     ceiling: limits.cpu, window: trendWindow, label: "\(row.name) CPU")
                        InspectorRow("Memory", row.footprint.map(bytes) ?? "Not readable", help: TableKit.footprintHelp)
                        ProcessTrend(points: points, series: .processMemory, tint: Palette.memory, unit: .bytes,
                                     ceiling: limits.memory, window: trendWindow, label: "\(row.name) memory")
                        InspectorRow("GPU time", acceleratorTime(row.gpuTime), help: TableKit.gpuHelp)
                        ProcessTrend(points: points, series: .processGPUTime, tint: Palette.gpu, unit: .millisecondsPerSecond,
                                     ceiling: limits.gpu, window: trendWindow, label: "\(row.name) GPU time")
                        InspectorRow("Neural memory", row.neuralMemory.map(bytes) ?? "Not readable", help: TableKit.neuralHelp)
                        ProcessTrend(points: points, series: .processNeuralMemory, tint: Palette.neural, unit: .bytes,
                                     ceiling: limits.neural, window: trendWindow, label: "\(row.name) Neural Engine memory")
                        InspectorRow("ANE group time", acceleratorTime(row.aneGroupTime), help: TableKit.aneHelp)
                        if let group = row.aneGroup {
                            InspectorRow("Resource group", String(group))
                            Text("Shared with the group's other processes. Individual PID execution time is not available.")
                                .font(.caption11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        InspectorRow("Resident", bytes(row.resident), help: "Includes pages shared with other processes")
                        InspectorRow("Threads", String(row.threads))
                        InspectorRow("Disk read", readable ? row.readRate.map { rate($0) } ?? pending : "Not readable", help: TableKit.diskHelp)
                        InspectorRow("Disk write", readable ? row.writeRate.map { rate($0) } ?? pending : "Not readable", help: TableKit.diskHelp)
                    }
                    InspectorProcessInfo(monitor: monitor, parent: row.parent, parentName: parent?.name,
                                         uid: row.uid, application: row.application?.name).equatable()
                    if let path = row.path { InspectorExecutable(path: path).equatable() }
                }
                .padding(20)
            }
            InspectorActions(monitor: monitor, current: current, pid: row.id, uid: row.uid).equatable()
        }
        .font(.body12)
    }
}

/// Derive all four inspector scales in one pass without filtered temporary arrays.
struct ProcessTrendLimits {
    let cpu: Double, memory: Double, gpu: Double, neural: Double
    init(_ points: [Point]) {
        var cpuPeak = 0.0, memoryPeak = 0.0, gpuPeak = 0.0, neuralPeak = 0.0
        for point in points {
            if let value = MetricSeries.processCPU.value(point) { cpuPeak = max(cpuPeak, value) }
            if let value = MetricSeries.processMemory.value(point) { memoryPeak = max(memoryPeak, value) }
            if let value = MetricSeries.processGPUTime.value(point) { gpuPeak = max(gpuPeak, value) }
            if let value = MetricSeries.processNeuralMemory.value(point) { neuralPeak = max(neuralPeak, value) }
        }
        cpu = max(100, (cpuPeak / 100).rounded(.up) * 100)
        memory = binaryCeiling(memoryPeak, minimum: 16_777_216)
        gpu = niceCeiling(gpuPeak, minimum: 10)
        neural = binaryCeiling(neuralPeak, minimum: 1_048_576)
    }
}

private struct InspectorIdentity: View, Equatable {
    let metadata: ProcessMetadata
    let pid: Int32
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: ProcessIcons.inspectorIcon(for: metadata)).resizable().interpolation(.high)
                .frame(width: 40, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(metadata.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                Text("PID \(String(pid))").font(.caption11).foregroundStyle(.secondary).monospacedDigit().textSelection(.enabled)
            }
        }
    }
}

private struct InspectorProcessInfo: View, Equatable {
    let monitor: Monitor
    let parent: Int32
    let parentName: String?
    let uid: UInt32
    let application: String?
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.monitor === b.monitor && a.parent == b.parent && a.parentName == b.parentName && a.uid == b.uid && a.application == b.application
    }
    var body: some View {
        InspectorSection("Process") {
            HStack(alignment: .firstTextBaseline) {
                Text("Parent").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                if let parentName {
                    Button("\(parentName) (\(String(parent)))") { monitor.selected = parent }
                        .buttonStyle(.link).lineLimit(1).truncationMode(.middle)
                        .help("Select the parent process")
                } else {
                    Text(String(parent)).monospacedDigit().textSelection(.enabled)
                }
            }.font(.body12).frame(minHeight: 20)
            InspectorUser(uid: uid)
            if let application { InspectorRow("Application", application) }
        }
    }
}

private struct InspectorUser: View {
    let uid: UInt32
    private let names = SwiftUI.State(initialValue: 0)
    var body: some View {
        let _ = names.wrappedValue
        InspectorRow("User", UserNames.resolved(uid).map { "\($0) (\(uid))" } ?? String(uid))
            .onReceive(NotificationCenter.default.publisher(for: UserNames.didResolve)) { _ in names.wrappedValue &+= 1 }
    }
}

private struct InspectorExecutable: View, Equatable {
    let path: String
    var body: some View {
        InspectorSection("Executable") {
            Text(path).font(.caption11).foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(4).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
            Button("Show in Finder") { revealInFinder(path) }.controlSize(.small).padding(.top, 2)
        }
    }
}

private struct InspectorActions: View, Equatable {
    let monitor: Monitor
    let current: Bool
    let pid: Int32
    let uid: UInt32
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.monitor === b.monitor && a.current == b.current && a.pid == b.pid && a.uid == b.uid
    }
    var body: some View {
        let owned = uid == getuid() && pid != getpid()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Quit…") { monitor.requestQuit(force: false) }
                Button("Force Quit…", role: .destructive) { monitor.requestQuit(force: true) }
            }
            // The action rechecks the selected process and its birth identity before terminating it.
            .disabled(!current || !owned)
            if !current || !owned {
                Text(!current ? "Unavailable in the latest sample." : pid == getpid() ? "Taskglass can't quit itself." : "Owned by another user.")
                    .font(.caption11).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Palette.keyline.frame(height: Metrics.hairline) }
    }
}

/// A selected process's CPU or memory over its recent samples, on the shared compact plot.
/// Points are recorded only while it is selected, so the start marker shows when tracking began.
struct ProcessTrend: View {
    let points: [Point]
    let series: MetricSeries
    let tint: Color
    let unit: PlotUnit
    let ceiling: Double
    let window: Double
    let label: String
    var body: some View {
        TelemetryPlot(points: points, layers: [PlotLayer(series: series, color: tint, filled: true)], ceiling: ceiling,
                      window: window, unit: unit, style: .compact, label: "\(label) history")
            .frame(height: 40).padding(.top, 2).padding(.bottom, 6)
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    var note: String?
    let content: Content
    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.note = note; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let note { Text(note).font(.caption11).foregroundStyle(Palette.quiet).lineLimit(1) }
            }
            content
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String
    var help: String?
    init(_ label: String, _ value: String, help: String? = nil) { self.label = label; self.value = value; self.help = help }
    /// Dashes and states ("Measuring", "Not readable") recede; measured values stay primary.
    var isState: Bool { value == "—" || value == "Measuring" || value == "Not readable" }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().foregroundStyle(isState ? AnyShapeStyle(Palette.quiet) : AnyShapeStyle(.primary)).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.body12).frame(minHeight: 20)
        .accessibilityElement(children: .combine)
        .help(ifPresent: help)
    }
}

/// The full definitions behind every figure, reachable from the toolbar's options menu.
struct MeasurementNotes: View {
    let done: () -> Void
    static let sections: [(String, String)] = [
        ("CPU", "Utilization uses the difference between kernel counters at each sample. System CPU is normalized to 100%. Process CPU reaches 100% per core and can exceed 100%."),
        ("Memory", "Process memory is the physical footprint when macOS allows access; a dash means access was denied. Resident memory may include shared pages. System used memory is internal pages minus purgeable pages, plus wired and compressed memory. Application totals add up their processes, so shared memory can be counted more than once."),
        ("Disk and network", "Disk rates use physical block-storage counters; reads served from the file cache are not disk I/O. Network rates add up active physical interfaces, including local traffic."),
        ("GPU, Neural Engine and power", "GPU utilization comes from whole-GPU AGX driver counters. CPU, GPU and Neural Engine power comes from experimental CLPC counters on supported drivers. Watts are not utilization, and chip power is not total system power. Process GPU time comes from stable AGX client counters in ms/s, not occupancy percent. Neural Engine time is shared OS resource-group time on recognized macOS 27 layouts. Neural memory is a per-process allocation, not compute activity. Per-process network use is not measured."),
        ("Sensors", "CPU and GPU temperature groups are inferred from SMC key prefixes. Temperatures and fans are read only and refresh every 10 seconds. The full sensor list is read only while Temperatures is open."),
        ("Battery", "Time remaining is macOS's average time-to-empty estimate, reported only while the Mac runs on battery. No time-to-full estimate is shown or computed."),
        ("Sampling and privacy", "Sampling pauses while the window is minimized, hidden or paused. A covered window keeps sampling but doesn't redraw until it is visible again. History, including the selected process's last 3 minutes, stays in memory only. View settings such as the update interval, history window, grouping, columns and rankings are saved; process names, selections, searches and measurements are never saved or sent anywhere.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About these measurements").font(.title3.weight(.semibold)).padding([.horizontal, .top], 24).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.sections, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.0).font(.system(size: 12, weight: .semibold))
                            Text(section.1).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 8)
            }
            HStack { Spacer(); Button("Done", action: done).keyboardShortcut(.defaultAction) }
                .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 520, height: 520)
    }
}
