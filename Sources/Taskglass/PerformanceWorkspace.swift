import SwiftUI
import AppKit

struct ChartKey: Identifiable {
    let title: String
    let value: String
    let layer: PlotLayer
    var id: String { title }
}

/// What a pane's primary chart plots and on which scale.
struct ChartSpec {
    let keys: [ChartKey]
    var floor: Double = 0
    var ceiling: Double = 100
    var unit: PlotUnit = .percent
}

/// Shared structure for every resource pane: readout line, one chart band whose secondary figures
/// sit beneath the plot, then titled sections. The pane title lives in the toolbar, so it is not repeated.
struct PaneScaffold<Content: View>: View {
    let title: String
    let value: String
    let caption: String
    let subtitle: String
    let about: [String]
    let chart: ChartSpec?
    let stats: [Stat]
    let points: [Point]
    let window: Double
    let paused: Bool
    let content: Content
    init(title: String, value: String, caption: String, subtitle: String, about: [String], chart: ChartSpec?, stats: [Stat],
         points: [Point], window: Double, paused: Bool, @ViewBuilder content: () -> Content) {
        self.title = title; self.value = value; self.caption = caption; self.subtitle = subtitle; self.about = about
        self.chart = chart; self.stats = stats; self.points = points; self.window = window; self.paused = paused; self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Readout(text: value, size: 28, weight: .regular)
                    Text(caption).font(.body12).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 16)
                    HStack(spacing: 8) {
                        Text(subtitle).font(.body12).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        InfoButton("About \(title) measurements", notes: about)
                    }
                }
                if let chart {
                    Band {
                        VStack(alignment: .leading, spacing: 14) {
                            LegendFlow(spacing: 20) {
                                ForEach(chart.keys) { SeriesKey(title: $0.title, value: $0.value, tint: $0.layer.color, dashed: $0.layer.dashed) }
                            }
                            TelemetryPlot(points: points, layers: chart.keys.map(\.layer), floor: chart.floor, ceiling: chart.ceiling, window: window,
                                          unit: chart.unit, style: .detailed, label: chart.keys.map(\.title).joined(separator: ", ") + " history", paused: paused)
                                .frame(height: 196)
                            if !stats.isEmpty { StatStrip(stats: stats).padding(.top, 14).bandDivider() }
                        }.cellLayout()
                    }
                } else if !stats.isEmpty {
                    Band { StatStrip(stats: stats).cellLayout() }
                }
                content
            }
            .padding(.horizontal, Metrics.pagePadding).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: Metrics.paneWidth).frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }
}

/// Titled group within a pane, spaced from the previous group.
struct PaneSection<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content
    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title; self.accessory = accessory(); self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title) { accessory }
            content
        }.padding(.top, 10)
    }
}
extension PaneSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) { self.init(title, accessory: { EmptyView() }, content: content) }
}

struct PerformanceWorkspace: View {
    @Bindable var monitor: Monitor
    let pane: ResourcePane
    var s: Snapshot { monitor.snapshot }
    var h: HardwareMetrics { s.hardware }
    var window: Double { monitor.historySeconds }

    var body: some View {
        switch pane {
        case .overview, .processes: OverviewDashboard(monitor: monitor)
        case .cpu: cpu
        case .memory: memory
        case .gpu: gpu
        case .neural: neural
        case .storage: storage
        case .network: network
        case .battery: battery
        case .temperatures: sensors
        }
    }

    func scaffold<Content: View>(value: String, caption: String, subtitle: String, about: [String], chart: ChartSpec?,
                                 stats: [Stat] = [], @ViewBuilder content: () -> Content) -> some View {
        PaneScaffold(title: pane.title, value: value, caption: caption, subtitle: subtitle, about: about, chart: chart, stats: stats,
                     points: monitor.history, window: window, paused: monitor.paused) {
            content()
            ResourceProcesses(monitor: monitor, pane: pane)
        }
    }
    var windowNote: String { "Last \(windowName(window))" }

    // MARK: CPU

    var cpu: some View {
        scaffold(value: percent(s.cpu), caption: "Total utilization", subtitle: cpuComposition,
                 about: ["Total and system utilization come from kernel CPU tick deltas, normalized so 100% means every core is busy.",
                         "Core types come from the device tree. Each heatmap row is one core over the selected history window.",
                         "Power is experimental CLPC energy telemetry. Temperature averages the CPU sensor group inferred from SMC key prefixes."],
                 chart: ChartSpec(keys: [ChartKey(title: "Total", value: percent(s.cpu), layer: PlotLayer(series: .cpu, color: Palette.cpu, filled: true)),
                                         ChartKey(title: "System", value: percent(s.cpu == nil ? nil : s.systemCPU), layer: PlotLayer(series: .system, color: Palette.cpu.opacity(0.75), dashed: true))]),
                 stats: [Stat("User", percent(s.cpu.map { max(0, $0 - s.systemCPU) })), Stat("Idle", percent(s.cpu.map { max(0, 100 - $0) })),
                         Stat("CPU power", power(h.cpuWatts), note: "Experimental"),
                         Stat("Temperature", temperature(h.cpuTemperature), note: "CPU sensor group"),
                         Stat("Thermal state", thermalStateName, help: "macOS thermal pressure state")]) {
            PaneSection("Core history", accessory: { LoadRamp() }) {
                Band {
                    VStack(alignment: .leading, spacing: 18) {
                        if coreGroups.isEmpty { EmptyRow(text: "Core layout not reported") }
                        ForEach(coreGroups, id: \.self) { group in
                            let indices = h.coreKinds.indices.filter { h.coreKinds[$0] == group }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    SwatchLabel(title: group == "Cores" ? "Cores" : "\(group) cores", tint: Palette.core(group))
                                    Spacer()
                                    Text("\(indices.count) cores, \(percent(average(indices))) average").font(.caption11).foregroundStyle(.secondary).monospacedDigit()
                                }
                                CoreHeatmap(points: monitor.history, indices: indices, prefix: group == "Cores" ? "C" : String(group.prefix(1)), kind: group, window: window)
                                    .frame(height: CoreHeatmap.height(rows: indices.count))
                            }
                        }
                        TimeAxis(window: window, paused: monitor.paused)
                            .padding(.leading, CoreHeatmap.labelWidth).padding(.trailing, CoreHeatmap.valueWidth)
                    }.cellLayout()
                }
            }
        }
    }

    // MARK: Memory

    var memory: some View {
        scaffold(value: bytes(s.used), caption: "of \(memoryCapacity(s.total)) used", subtitle: "Unified memory",
                 about: ["Used memory is app memory (internal minus purgeable pages) plus wired and compressed memory.",
                         "Cached files hold recently read data that macOS reclaims when apps need memory.",
                         "GPU allocations live in this same unified memory and overlap system accounting. They are not a separate VRAM pool."],
                 chart: ChartSpec(keys: [ChartKey(title: "Used", value: percent(Double(s.used) / Double(max(1, s.total)) * 100), layer: PlotLayer(series: .memory, color: Palette.memory, filled: true))]),
                 stats: [Stat("Swap used", bytes(s.swap)),
                         Stat("GPU in use", h.gpuInUse.map(bytes) ?? "—", note: "Part of unified memory"),
                         Stat("GPU allocated", h.gpuAllocated.map(bytes) ?? "—", note: "Not separate VRAM")]) {
            PaneSection("Composition", accessory: { StatusIndicator(label: "Pressure", state: pressureName(s.pressure), tint: pressureColor(s.pressure)) }) {
                Band {
                    VStack(alignment: .leading, spacing: 12) {
                        SegmentedBar(segments: [(Double(appMemory), Palette.memory), (Double(s.wired), Palette.memory.opacity(0.62)),
                                                (Double(s.compressed), Palette.memory.opacity(0.36)), (Double(cachedShown), Color.white.opacity(0.24)),
                                                (Double(freeShown), Color.clear)], height: 10)
                            .accessibilityHidden(true)
                        LegendFlow {
                            SwatchValue(title: "App", value: bytes(appMemory), tint: Palette.memory)
                                .help("Internal memory used by apps, excluding purgeable pages")
                            SwatchValue(title: "Wired", value: bytes(s.wired), tint: Palette.memory.opacity(0.62))
                                .help("Memory the kernel keeps resident; it cannot be compressed or paged out")
                            SwatchValue(title: "Compressed", value: bytes(s.compressed), tint: Palette.memory.opacity(0.36))
                            SwatchValue(title: "Cached files", value: bytes(s.cached), tint: Color.white.opacity(0.24))
                                .help("Reclaimable file cache")
                            SwatchValue(title: "Free", value: bytes(freeShown), tint: Palette.track)
                        }
                    }.cellLayout()
                }
            }
        }
    }
    var appMemory: UInt64 { s.used >= s.wired + s.compressed ? s.used - s.wired - s.compressed : 0 }
    var cachedShown: UInt64 { min(s.cached, s.total > s.used ? s.total - s.used : 0) }
    var freeShown: UInt64 { s.total > s.used + cachedShown ? s.total - s.used - cachedShown : 0 }

    // MARK: GPU

    var gpu: some View {
        scaffold(value: percent(h.gpuUsage), caption: "Device utilization", subtitle: h.gpuCores > 0 ? "\(h.gpuCores) cores, aggregate counters" : "Aggregate counters",
                 about: ["Utilization comes from the AGX driver's PerformanceStatistics counters for the whole GPU. Per-core values are not available and are not inferred.",
                         "Renderer and tiler measure different stages of work. They overlap and should not be added together.",
                         "GPU memory is part of unified memory. Power is experimental CLPC energy telemetry."],
                 chart: ChartSpec(keys: [ChartKey(title: "Device", value: percent(h.gpuUsage), layer: PlotLayer(series: .gpu, color: Palette.gpu, filled: true)),
                                         ChartKey(title: "Renderer", value: percent(h.rendererUsage), layer: PlotLayer(series: .renderer, color: Palette.renderer)),
                                         ChartKey(title: "Tiler", value: percent(h.tilerUsage), layer: PlotLayer(series: .tiler, color: Palette.tiler, dashed: true))]),
                 stats: [Stat("In-use memory", h.gpuInUse.map(bytes) ?? "—", note: "Unified memory"),
                         Stat("Allocated memory", h.gpuAllocated.map(bytes) ?? "—", note: "Unified memory"),
                         Stat("GPU power", power(h.gpuWatts), note: "Experimental"),
                         Stat("Temperature", temperature(h.gpuTemperature), note: "GPU sensor group")]) {
            EmptyView()
        }
    }

    // MARK: Neural Engine

    var neural: some View {
        let measured = monitor.peak(.ane) != nil || h.aneWatts != nil
        return scaffold(value: power(h.aneWatts), caption: "Power draw, not utilization", subtitle: "Experimental energy counter",
                        about: ["Power is energy per second from the Neural Engine's hardware counter. It is not a utilization percentage, and none is estimated.",
                                "CLPC is an undocumented, version-specific source enabled only for recognized drivers. A readable zero stays zero; unavailable samples leave gaps."],
                        chart: measured ? ChartSpec(keys: [ChartKey(title: "Power", value: power(h.aneWatts), layer: PlotLayer(series: .ane, color: Palette.neural, filled: true))],
                                                    ceiling: monitor.ceiling([.ane], minimum: 0.1), unit: .power) : nil,
                        stats: [Stat("Average", power(monitor.mean(.ane)), note: windowNote), Stat("Peak", power(monitor.peak(.ane)), note: windowNote),
                                Stat("CPU power", power(h.cpuWatts)), Stat("GPU power", power(h.gpuWatts)),
                                Stat("Counter source", h.powerSource.isEmpty ? "—" : h.powerSource)]) {
            if !measured {
                Unmeasured(headline: "Neural Engine power isn't available",
                           reason: "This macOS driver did not return a supported energy counter. No usage or power value is inferred.")
            }
        }
    }

    // MARK: Storage

    var storage: some View {
        scaffold(value: rate(sum(h.diskRead, h.diskWrite)), caption: "Read plus write", subtitle: "Physical disk I/O",
                 about: ["Rates add up physical I/O across block-storage drivers. Reads served from the file cache need not touch disk and are not counted.",
                         "Capacity describes the APFS Data volume, not each physical disk."],
                 chart: ChartSpec(keys: [ChartKey(title: "Read", value: rate(h.diskRead), layer: PlotLayer(series: .diskRead, color: Palette.storage, filled: true)),
                                         ChartKey(title: "Write", value: rate(h.diskWrite), layer: PlotLayer(series: .diskWrite, color: Palette.storage.opacity(0.8), dashed: true))],
                                  ceiling: monitor.rateCeiling([.diskRead, .diskWrite]), unit: .rate),
                 stats: [Stat("Read operations", iops(h.diskReadIOPS)), Stat("Write operations", iops(h.diskWriteIOPS)),
                         Stat("Peak read", rate(monitor.peak(.diskRead)), note: windowNote), Stat("Peak write", rate(monitor.peak(.diskWrite)), note: windowNote)]) {
            if let total = h.diskTotal, let available = h.diskAvailable, total > 0 {
                let used = total - min(total, available)
                PaneSection("Data volume", accessory: { Text("\(bytes(total)) capacity").monospacedDigit() }) {
                    Band {
                        VStack(alignment: .leading, spacing: 10) {
                            LevelBar(fraction: Double(used) / Double(total), tint: Palette.storage, height: 8)
                            HStack {
                                SwatchValue(title: "Used", value: bytes(used), tint: Palette.storage)
                                Spacer()
                                SwatchValue(title: "Available", value: bytes(available), tint: Palette.track)
                            }
                        }.cellLayout()
                    }
                }
            }
        }
    }

    // MARK: Network

    var network: some View {
        scaffold(value: rate(sum(s.download, s.upload)), caption: "Receiving plus sending",
                 subtitle: s.interfaces.count == 1 ? "1 physical interface" : "\(s.interfaces.count) physical interfaces",
                 about: ["Rates add up active physical interfaces and include local network traffic. Virtual tunnel and bridge interfaces are excluded to reduce double counting.",
                         "Received and sent totals are interface counters. They reset when an interface restarts."],
                 chart: ChartSpec(keys: [ChartKey(title: "Receiving", value: rate(s.download), layer: PlotLayer(series: .download, color: Palette.network, filled: true)),
                                         ChartKey(title: "Sending", value: rate(s.upload), layer: PlotLayer(series: .upload, color: Palette.network.opacity(0.8), dashed: true))],
                                  ceiling: monitor.rateCeiling([.download, .upload]), unit: .rate),
                 stats: [Stat("Peak receiving", rate(monitor.peak(.download)), note: windowNote), Stat("Peak sending", rate(monitor.peak(.upload)), note: windowNote),
                         Stat("Received", bytes(s.received), note: "Interface counters"), Stat("Sent", bytes(s.sent), note: "Interface counters")]) {
            PaneSection("Interfaces") {
                Band {
                    VStack(spacing: 0) {
                        let columns = [ColumnSpec(title: "Interface", width: nil), ColumnSpec(title: "Receiving", width: 104, trailing: true),
                                       ColumnSpec(title: "Sending", width: 104, trailing: true), ColumnSpec(title: "Received", width: 96, trailing: true),
                                       ColumnSpec(title: "Sent", width: 96, trailing: true)]
                        DataHeader(columns: columns)
                        if s.interfaces.isEmpty { EmptyRow(text: "No active physical interfaces") }
                        ForEach(s.interfaces) { interface in
                            DataRow(columns: columns, values: [interface.id, rate(interface.download), rate(interface.upload), bytes(interface.received), bytes(interface.sent)])
                        }
                    }.cellLayout()
                }
            }
        }
    }

    // MARK: Battery

    var battery: some View {
        let flow = batteryFlow(h.batteryWatts)
        return scaffold(value: percent(h.batteryPercent), caption: h.batteryState, subtitle: "Internal battery",
                        about: ["Charging and discharging rates are the battery's net power, refreshed every 10 seconds.",
                                "Full / design capacity compares the reported full-charge capacity with the design capacity. It can differ from Apple's battery-health estimate.",
                                "Time remaining is macOS's average time-to-empty estimate. It changes with load and is reported only on battery power. No time-to-full estimate is shown."],
                        chart: ChartSpec(keys: [ChartKey(title: "Charge", value: percent(h.batteryPercent), layer: PlotLayer(series: .battery, color: Palette.battery, filled: true))]),
                        stats: [Stat(flow.label, flow.value),
                                // AvgTimeToEmpty, discharging only. Never relabelled as a time to full charge.
                                Stat("Time remaining", duration(h.batteryMinutes), note: h.batteryMinutes == nil && h.batteryExternal ? "On battery only" : nil,
                                     help: "macOS's average time-to-empty estimate, reported only while discharging"),
                                Stat("Cycles", h.batteryCycles > 0 ? String(h.batteryCycles) : "—"),
                                Stat("Full / design capacity", percent(h.batteryCapacityRatio), help: "May differ from Apple's battery-health estimate"),
                                Stat("Temperature", temperature(h.batteryTemperature)),
                                Stat("Voltage", h.batteryVoltage.map { decimal($0, places: 2) + " V" } ?? "—")]) {
            EmptyView()
        }
    }
    func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes >= 0 else { return "—" }
        let total = Int(minutes.rounded())
        let remainder = total % 60
        return total < 60 ? "\(total) min" : "\(total / 60) h \(remainder < 10 ? "0" : "")\(remainder) min"
    }

    // MARK: Temperatures

    var sensors: some View {
        let scale = monitor.temperatureScale
        let hottest = h.temperatures.max { $0.celsius < $1.celsius }
        return scaffold(value: temperature(h.cpuTemperature), caption: "CPU sensor group average",
                        subtitle: h.temperatures.count == 1 ? "1 sensor" : "\(h.temperatures.count) sensors",
                        about: ["CPU and GPU groups are inferred from SMC key prefixes. They are not a documented junction-temperature API. Every reading keeps its original sensor name.",
                                "Invalid and out-of-range readings are excluded. Sensors, fans and battery values refresh every 10 seconds.",
                                "Fans are read only. Taskglass never changes fan speed."],
                        chart: ChartSpec(keys: [ChartKey(title: "CPU group", value: temperature(h.cpuTemperature), layer: PlotLayer(series: .temperature, color: Palette.cpu)),
                                                ChartKey(title: "GPU group", value: temperature(h.gpuTemperature), layer: PlotLayer(series: .gpuTemperature, color: Palette.gpu)),
                                                ChartKey(title: "Battery", value: temperature(h.batteryTemperature), layer: PlotLayer(series: .batteryTemperature, color: Palette.battery, dashed: true))],
                                         floor: scale.floor, ceiling: scale.ceiling, unit: .celsius),
                        stats: [Stat("Hottest sensor", temperature(hottest?.celsius), note: hottest?.name),
                                Stat("Thermal state", thermalStateName, help: "macOS thermal pressure state")]) {
            PaneSection("Fans") {
                Band {
                    VStack(spacing: 8) { FanList(hardware: h).equatable() }
                        .frame(maxWidth: 520, alignment: .leading).cellLayout()
                }
                .help("Fan speeds are read only. Taskglass never changes them.")
            }
            SensorSection(monitor: monitor, readings: h.temperatures).equatable()
        }
    }

    static let sensorOrder = ["CPU", "GPU", "Storage", "Battery", "PMU / other"]

    // MARK: Derived values

    var cpuComposition: String {
        let total = h.tier0Count + h.tier1Count
        guard total > 0 else { return "\(ProcessInfo.processInfo.activeProcessorCount) cores" }
        return h.tier1Count > 0 ? "\(h.tier0Count) \(h.tier0) and \(h.tier1Count) \(h.tier1) cores" : "\(h.tier0Count) \(h.tier0) cores"
    }
    var coreGroups: [String] {
        Array(Set(h.coreKinds)).sorted { rank($0) < rank($1) }
    }
    func rank(_ kind: String) -> Int { kind == "Super" ? 0 : kind == "Performance" ? 1 : kind == "Efficiency" ? 2 : 3 }
    func average(_ indices: [Int]) -> Double? {
        let values = indices.compactMap { s.cores.indices.contains($0) ? s.cores[$0] : nil }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// The filter and table depend on slow sensor samples, not each new CPU/history sample.
private struct SensorSection: View, Equatable {
    let monitor: Monitor
    let readings: [TemperatureReading]
    nonisolated static func == (a: Self, b: Self) -> Bool { a.monitor === b.monitor && a.readings == b.readings }
    var body: some View {
        @Bindable var monitor = monitor
        let rows = SensorRows.rows(readings, scope: monitor.sensorScope)
        let present = Set(readings.map(\.group))
        let groups = ["All"] + PerformanceWorkspace.sensorOrder.filter(present.contains)
        PaneSection("Sensors", accessory: {
            HStack(spacing: 12) {
                Text("\(rows.count) of \(readings.count)").monospacedDigit()
                Picker("Sensor group", selection: $monitor.sensorScope) {
                    ForEach(groups, id: \.self) { Text($0 == "PMU / other" ? "Other" : $0).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
        }) {
            SensorTable(readings: rows).equatable()
        }
    }
}

/// Filtered, ordered sensor rows. Readings refresh every 10 s at most, so most samples reuse the last
/// order instead of re-sorting ~130 names with a localized compare. Holds one list.
@MainActor enum SensorRows {
    private static var input: [TemperatureReading] = []
    private static var scope = ""
    private static var output: [TemperatureReading] = []
    static func rows(_ readings: [TemperatureReading], scope next: String) -> [TemperatureReading] {
        let same = next == scope && readings == input
        guard !same else { return output }
        let order = PerformanceWorkspace.sensorOrder
        input = readings; scope = next
        output = readings.filter { next == "All" || $0.group == next }.sorted {
            let a = order.firstIndex(of: $0.group) ?? 9, b = order.firstIndex(of: $1.group) ?? 9
            if a != b { return a < b }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        return output
    }
}

/// Named sensor readings. Only re-rendered when a reading changes, which happens every 10 s at most.
struct SensorTable: View, Equatable {
    let readings: [TemperatureReading]
    static let columns = [ColumnSpec(title: "Sensor", width: nil), ColumnSpec(title: "Source", width: 90),
                          ColumnSpec(title: "Group", width: 100), ColumnSpec(title: "Temperature", width: 96, trailing: true)]
    nonisolated static func == (a: SensorTable, b: SensorTable) -> Bool {
        a.readings == b.readings
    }
    var body: some View {
        Band {
            VStack(spacing: 0) {
                DataHeader(columns: Self.columns)
                if readings.isEmpty { EmptyRow(text: "No readable sensors in this group") }
                LazyVStack(spacing: 0) {
                    ForEach(readings) { sensor in
                        DataRow(columns: Self.columns, values: [sensor.name, sensor.source, sensor.group == "PMU / other" ? "Other" : sensor.group, temperature(sensor.celsius)])
                    }
                }
            }.cellLayout()
        }
    }
}
