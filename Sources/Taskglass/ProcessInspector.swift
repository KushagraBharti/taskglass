import SwiftUI
import AppKit

/// Trailing inspector for the selected process: identity first, then activity with short CPU and memory
/// trends, then the executable. Quit actions stay pinned at the bottom and are disabled, with a reason,
/// for processes the user doesn't own and for any process missing from the latest sample.
struct ProcessInspector: View {
    @ObservedObject var monitor: Monitor
    /// Bumped when a background account-name lookup finishes, so the User row replaces the UID.
    private let names = SwiftUI.State(initialValue: 0)

    var body: some View {
        Group {
            // `selection` is current and readable; `selectedProcessRecord` falls back to the last observed record.
            if let row = monitor.selectedProcessRecord { detail(row, current: monitor.selection != nil) } else { placeholder }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserNames.didResolve)) { _ in names.wrappedValue &+= 1 }
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
        let owned = row.uid == getuid() && row.id != getpid()
        // Footprint and disk rates share one rusage source: no footprint means none of them are readable.
        let readable = row.footprint != nil
        let pending = current ? "Measuring" : "—"
        let points = monitor.processHistory
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(nsImage: ProcessIcons.icon(for: row)).resizable().interpolation(.high)
                            .frame(width: 40, height: 40).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                            Text("PID \(String(row.id))").font(.caption11).foregroundStyle(.secondary).monospacedDigit().textSelection(.enabled)
                        }
                    }
                    if !current {
                        Notice("Not in the latest sample. It may have exited, or macOS may no longer allow access. Values are the last observed.")
                    }
                    InspectorSection(current ? "Activity" : "Last observed", note: monitor.paused ? "Paused" : "Trends: last \(windowName(trendWindow))") {
                        InspectorRow("CPU", row.cpu.map { percent($0) } ?? pending, help: TableKit.cpuHelp)
                        ProcessTrend(points: points, series: .processCPU, tint: Palette.cpu, unit: .percent,
                                     ceiling: Self.cpuCeiling(points), window: trendWindow, label: "\(row.name) CPU")
                        InspectorRow("Memory", row.footprint.map(bytes) ?? "Not readable", help: TableKit.footprintHelp)
                        ProcessTrend(points: points, series: .processMemory, tint: Palette.memory, unit: .bytes,
                                     ceiling: Self.memoryCeiling(points), window: trendWindow, label: "\(row.name) memory")
                        InspectorRow("Resident", bytes(row.resident), help: "Includes pages shared with other processes")
                        InspectorRow("Threads", String(row.threads))
                        InspectorRow("Disk read", readable ? row.readRate.map { rate($0) } ?? pending : "Not readable", help: TableKit.diskHelp)
                        InspectorRow("Disk write", readable ? row.writeRate.map { rate($0) } ?? pending : "Not readable", help: TableKit.diskHelp)
                    }
                    InspectorSection("Process") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Parent").foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            if let parent {
                                Button("\(parent.name) (\(String(parent.id)))") { monitor.selected = parent.id }
                                    .buttonStyle(.link).lineLimit(1).truncationMode(.middle)
                                    .help("Select the parent process")
                            } else {
                                Text(String(row.parent)).monospacedDigit().textSelection(.enabled)
                            }
                        }.font(.body12).frame(minHeight: 20)
                        InspectorRow("User", userText(row.uid))
                        if let application = row.application {
                            InspectorRow("Application", application.name)
                        }
                    }
                    if let path = row.path {
                        InspectorSection("Executable") {
                            Text(path).font(.caption11).foregroundStyle(.secondary).textSelection(.enabled)
                                .lineLimit(4).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
                            Button("Show in Finder") { revealInFinder(path) }.controlSize(.small).padding(.top, 2)
                        }
                    }
                }
                .padding(20)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Quit…") { monitor.requestQuit(force: false) }
                    Button("Force Quit…", role: .destructive) { monitor.requestQuit(force: true) }
                }
                // Never offered on a last-observed record: its PID may already belong to something else.
                .disabled(!current || !owned)
                if !current || !owned {
                    Text(!current ? "Unavailable in the latest sample." : row.id == getpid() ? "Taskglass can't quit itself." : "Owned by another user.")
                        .font(.caption11).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Palette.keyline.frame(height: Metrics.hairline) }
        }
        .font(.body12)
    }

    /// "account (501)" once the account name is known; the UID alone until then, or if the directory has none.
    func userText(_ uid: UInt32) -> String {
        _ = names.wrappedValue
        return UserNames.resolved(uid).map { "\($0) (\(uid))" } ?? String(uid)
    }
    /// 100% (one core) unless the process used more, then whole cores.
    static func cpuCeiling(_ points: [Point]) -> Double {
        let peak = points.compactMap(MetricSeries.processCPU.value).max() ?? 0
        return max(100, (peak / 100).rounded(.up) * 100)
    }
    /// Power-of-two bytes from a 16 MB floor, so the label reads 64 MB, 512 MB, 2 GB…
    static func memoryCeiling(_ points: [Point]) -> Double {
        binaryCeiling(points.compactMap(MetricSeries.processMemory.value).max() ?? 0, minimum: 16_777_216)
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
        ("GPU, Neural Engine and power", "GPU utilization comes from whole-GPU AGX driver counters. CPU, GPU and Neural Engine power comes from experimental CLPC counters on supported drivers. Watts are not utilization, and chip power is not total system power. Per-process GPU, Neural Engine and network use is not measured."),
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
