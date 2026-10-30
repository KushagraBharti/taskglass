import SwiftUI
import AppKit

/// Overview as an instrument rack: four bands whose column keylines line up vertically.
/// Resources (4), environment (4), transport (2), cores and processes (2).
struct OverviewDashboard: View {
    let monitor: Monitor
    var s: Snapshot { monitor.snapshot }
    var h: HardwareMetrics { s.hardware }
    var window: Double { monitor.historySeconds }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.bandGap) {
                header.padding(.bottom, 4)
                Band {
                    resource(.cpu, value: percent(s.cpu), detail: (cpuDetail, "\(cpuCoreCount) cores"), ceiling: 100, first: true)
                    resource(.memory, value: bytes(s.used), detail: ("of \(memoryCapacity(s.total)) unified memory", "of \(memoryCapacity(s.total))"), ceiling: 100)
                    resource(.gpu, value: percent(h.gpuUsage), detail: ("Device utilization", "Utilization"), ceiling: 100)
                    resource(.neural, value: power(h.aneWatts), detail: ("Power draw, not utilization", "Power, not usage"), ceiling: monitor.ceiling([.ane], minimum: 0.1))
                }
                Band {
                    temperatures
                    fans.leadingKeyline()
                    if h.batteryPresent {
                        OverviewBattery(monitor: monitor, charge: h.batteryPercent, watts: h.batteryWatts, state: h.batteryState)
                            .equatable().leadingKeyline()
                    }
                    chipPower.leadingKeyline()
                }
                Band {
                    transport(.storage, accessory: "Physical disks", read: ("Read", h.diskRead, .diskRead), write: ("Write", h.diskWrite, .diskWrite), first: true)
                    transport(.network, accessory: s.interfaces.count == 1 ? "1 interface" : "\(s.interfaces.count) interfaces", read: ("Receiving", s.download, .download), write: ("Sending", s.upload, .upload))
                }
                Band {
                    cores
                    OverviewProcesses(monitor: monitor).leadingKeyline()
                }
                OverviewFooter(monitor: monitor).padding(.top, 4)
            }
            .padding(Metrics.pagePadding)
            .frame(maxWidth: Metrics.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background)
    }

    // MARK: Header and footer

    /// The chip name is already the window subtitle; this line adds only the configuration.
    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(hardwareSummary).font(.body12).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 12)
            StatusIndicator(label: "Memory pressure", state: pressureName(s.pressure), tint: pressureColor(s.pressure))
            StatusIndicator(label: "Thermal state", state: thermalStateName, tint: thermalStateColor)
        }
    }
    // MARK: Resource band

    func resource(_ pane: ResourcePane, value: String, detail: (full: String, short: String), ceiling: Double, first: Bool = false) -> some View {
        BandCellButton(help: "Show \(pane.title) details", leadingEdge: first, trailingEdge: pane == .neural, action: { monitor.pane = pane }) {
            VStack(alignment: .leading, spacing: 0) {
                CellHeader(pane.title, icon: pane.icon, tint: pane.color)
                Readout(text: value).padding(.top, 12)
                FittingText(detail.full, short: detail.short).font(.caption11).foregroundStyle(.secondary).padding(.top, 2)
                TelemetryPlot(points: monitor.history, layers: [PlotLayer(series: pane.series, color: pane.color, filled: true)],
                              ceiling: ceiling, window: window, unit: pane.unit, label: "\(pane.title) history")
                    .frame(height: 60).padding(.top, 14)
            }
        }
        .leadingKeyline(!first)
    }

    // MARK: Environment band

    /// Every environment cell uses 64 pt labels, so bars and values align across the band.
    static let environmentLabel: CGFloat = 64

    var temperatures: some View {
        BandCellButton(help: "Show temperature sensors", leadingEdge: true, action: { monitor.pane = .temperatures }) {
            VStack(alignment: .leading, spacing: 8) {
                CellHeader("Temperatures", icon: "thermometer.medium", tint: Palette.temperature) { Text(thermalStateName) }
                    .padding(.bottom, 4)
                MeterRow("CPU", value: temperature(h.cpuTemperature), labelWidth: Self.environmentLabel) { inlineHistory(.temperature, tint: Palette.cpu) }
                MeterRow("GPU", value: temperature(h.gpuTemperature), labelWidth: Self.environmentLabel) { inlineHistory(.gpuTemperature, tint: Palette.gpu) }
            }
        }
    }
    var fans: some View {
        BandCellButton(help: "Fan speeds are read only. Show fans and temperature sensors", action: { monitor.pane = .temperatures }) {
            VStack(alignment: .leading, spacing: 8) {
                CellHeader("Fans", icon: "fan", tint: Palette.fan).padding(.bottom, 4)
                FanList(hardware: h, labelWidth: Self.environmentLabel).equatable()
            }
        }
    }
    /// Only the three measured components, each always named: the total is not system or wall power,
    /// and a coloured number without its component would be unreadable.
    var chipPower: some View {
        VStack(alignment: .leading, spacing: 8) {
            CellHeader("Chip power", icon: "bolt.fill", tint: Palette.power) { Text("Experimental") }.padding(.bottom, 4)
            MeterRow("Total", value: power(chipTotal), labelWidth: Self.environmentLabel) {
                SegmentedBar(segments: [(h.cpuWatts ?? 0, Palette.cpu), (h.gpuWatts ?? 0, Palette.gpu), (h.aneWatts ?? 0, Palette.neural)])
            }
            // One line when it fits; otherwise each name sits over its value in three equal columns.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ForEach(powerParts, id: \.name) { part in
                        SwatchValue(title: part.name, value: Self.legendPower(part.watts), tint: part.tint)
                            .accessibilityLabel("\(part.spoken) \(power(part.watts))")
                    }
                }.frame(height: Metrics.rowHeight, alignment: .leading)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(powerParts, id: \.name) { part in
                        VStack(alignment: .leading, spacing: 2) {
                            SwatchLabel(title: part.name, tint: part.tint)
                            Text(Self.legendPower(part.watts)).font(.caption11).monospacedDigit()
                                .foregroundStyle(part.watts == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                                .lineLimit(1).minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore).accessibilityLabel("\(part.spoken) \(power(part.watts))")
                    }
                }
            }
        }
        .cellLayout()
        .help("Experimental CLPC energy counters for the CPU, GPU and Neural Engine only. Not total system or wall power. Watts are not utilization.")
    }
    var powerParts: [(name: String, spoken: String, watts: Double?, tint: Color)] {
        [("CPU", "CPU", h.cpuWatts, Palette.cpu), ("GPU", "GPU", h.gpuWatts, Palette.gpu), ("ANE", "Neural Engine", h.aneWatts, Palette.neural)]
    }
    /// One decimal for the legend so all three names fit; the total keeps two.
    static func legendPower(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return abs(value) < 1 ? decimal(value * 1000, places: 0) + " mW" : decimal(value, places: 1) + " W"
    }
    func inlineHistory(_ series: MetricSeries, tint: Color) -> some View {
        let scale = monitor.temperatureScale
        return TelemetryPlot(points: monitor.history, layers: [PlotLayer(series: series, color: tint)], floor: scale.floor, ceiling: scale.ceiling,
                             window: window, unit: .celsius, style: .inline)
            .frame(height: 14)
            .help("Last \(windowName(window)), \(Int(scale.floor)) to \(Int(scale.ceiling)) °C")
    }

    // MARK: Transport band

    typealias Flow = (title: String, value: Double?, series: MetricSeries)
    func transport(_ pane: ResourcePane, accessory: String, read: Flow, write: Flow, first: Bool = false) -> some View {
        BandCellButton(help: "Show \(pane.title) details", leadingEdge: first, trailingEdge: !first, action: { monitor.pane = pane }) {
            VStack(alignment: .leading, spacing: 12) {
                CellHeader(pane.title, icon: pane.icon, tint: pane.color) { Text(accessory) }
                HStack(alignment: .bottom, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Readout(text: rate(sum(read.value, write.value)))
                            .help("\(read.title) plus \(write.title.lowercased())")
                            .padding(.bottom, 2)
                        flowKey(read.title, read.value, pane.color, dashed: false)
                        flowKey(write.title, write.value, pane.color, dashed: true)
                    }.frame(width: 160, alignment: .leading)
                    TelemetryPlot(points: monitor.history,
                                  layers: [PlotLayer(series: read.series, color: pane.color, filled: true), PlotLayer(series: write.series, color: pane.color.opacity(0.8), dashed: true)],
                                  ceiling: monitor.rateCeiling([read.series, write.series]), window: window, unit: .rate, label: "\(pane.title) history")
                        .frame(height: 72)
                }
            }
        }
        .leadingKeyline(!first)
    }
    func flowKey(_ title: String, _ value: Double?, _ tint: Color, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            LineSwatch(tint: tint, dashed: dashed)
            Text(title).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Text(rate(value)).monospacedDigit().foregroundStyle(value == nil ? .tertiary : .primary)
        }.font(.caption11).lineLimit(1).accessibilityElement(children: .combine)
    }

    // MARK: Cores and processes band

    var cores: some View {
        VStack(alignment: .leading, spacing: 10) {
            CellHeader("CPU cores", icon: "cpu", tint: Palette.cpu) {
                LinkButton("Core history") { monitor.pane = .cpu }
            }
            HStack(spacing: 14) {
                ForEach(coreKindsPresent, id: \.self) { SwatchLabel(title: $0, tint: Palette.core($0)) }
                Spacer(minLength: 0)
            }
            CoreTileMap(values: s.cores, kinds: h.coreKinds)
                .frame(height: CoreTileMap.height(cores: max(s.cores.count, h.coreKinds.count)))
                .help("One tile per CPU core. Brighter tiles are busier; numbers are utilization percent.")
            CellHeader("GPU engines", icon: ResourcePane.gpu.icon, tint: Palette.gpu) {
                Text("Whole GPU, not per core")
            }.padding(.top, 8)
            MeterRow("Renderer", value: percent(h.rendererUsage), labelWidth: Self.environmentLabel) {
                LevelBar(fraction: h.rendererUsage.map { $0 / 100 }, tint: Palette.renderer)
            }
            MeterRow("Tiler", value: percent(h.tilerUsage), labelWidth: Self.environmentLabel) {
                LevelBar(fraction: h.tilerUsage.map { $0 / 100 }, tint: Palette.tiler)
            }
            .help("Renderer and tiler measure different stages and overlap; they should not be added")
        }.cellLayout()
    }
    // MARK: Derived values

    var cpuCoreCount: Int { h.tier0Count + h.tier1Count > 0 ? h.tier0Count + h.tier1Count : ProcessInfo.processInfo.activeProcessorCount }
    var hardwareSummary: String {
        var parts = ["\(cpuCoreCount)-core CPU"]
        if h.gpuCores > 0 { parts.append("\(h.gpuCores)-core GPU") }
        parts.append("\(memoryCapacity(s.total)) unified memory")
        return parts.joined(separator: ", ")
    }
    var cpuDetail: String {
        guard h.tier0Count > 0 else { return "\(cpuCoreCount) cores" }
        return h.tier1Count > 0 ? "\(h.tier0Count) \(h.tier0) + \(h.tier1Count) \(h.tier1) cores" : "\(h.tier0Count) \(h.tier0) cores"
    }
    var coreKindsPresent: [String] {
        ["Super", "Performance", "Efficiency"].filter(h.coreKinds.contains)
    }
    var chipTotal: Double? { guard let a = h.cpuWatts, let b = h.gpuWatts, let c = h.aneWatts else { return nil }; return a + b + c }
}

func sum(_ a: Double?, _ b: Double?) -> Double? { guard let a, let b else { return nil }; return a + b }

private struct OverviewFooter: View {
    let monitor: Monitor
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(monitor.paused ? Color.orange : Color.green).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(monitor.paused ? "Paused" : "Live, every \(Int(monitor.interval)) s")
            Spacer(minLength: 12)
            Text("Charts show the last \(windowName(monitor.historySeconds))")
        }
        .font(.caption11).foregroundStyle(.secondary).lineLimit(1)
        .help("Temperatures, fans and battery refresh every 10 seconds")
    }

}

private struct OverviewBattery: View, Equatable {
    let monitor: Monitor
    let charge: Double?
    let watts: Double?
    let state: String
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.monitor === b.monitor && a.charge == b.charge && a.watts == b.watts && a.state == b.state
    }
    var body: some View {
        let flow = batteryFlow(watts)
        return BandCellButton(help: "Show battery details", action: { monitor.pane = .battery }) {
            VStack(alignment: .leading, spacing: 8) {
                CellHeader("Battery", icon: ResourcePane.battery.icon, tint: Palette.battery) { Text(state) }
                    .padding(.bottom, 4)
                MeterRow("Charge", value: percent(charge), labelWidth: OverviewDashboard.environmentLabel) {
                    LevelBar(fraction: charge.map { $0 / 100 }, tint: Palette.battery)
                }
                MeterRow(flow.label, value: flow.value, labelWidth: OverviewDashboard.environmentLabel)
            }
        }
    }
}
