import SwiftUI
import AppKit

/// One plotted series. The first filled layer gets the translucent area under its line.
struct PlotLayer: Identifiable {
    let series: MetricSeries
    let color: Color
    var dashed = false
    var filled = false
    var id: MetricSeries { series }
}

enum PlotUnit {
    case percent, rate, bytes, power, celsius, millisecondsPerSecond
    /// Axis labels: round values without trailing ".0", binary units for byte amounts and rates.
    func axis(_ value: Double) -> String {
        switch self {
        case .millisecondsPerSecond: return trimmed(value) + " ms/s"
        case .percent: return "\(Int(value.rounded()))%"
        case .rate: return value <= 0 ? "0" : axisBytes(value) + "/s"
        case .bytes: return value <= 0 ? "0" : axisBytes(value)
        case .power:
            if value <= 0 { return "0" }
            return value < 1 ? "\(Int((value * 1000).rounded())) mW" : trimmed(value) + " W"
        case .celsius: return "\(Int(value.rounded()))°C"
        }
    }
    private func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return decimal(rounded, places: rounded == rounded.rounded() ? 0 : 1)
    }
    private func axisBytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = value, index = 0
        while amount >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
        return "\(trimmed(amount)) \(units[index])"
    }
}

/// micro: sidebar thumbnails. inline: a bare line inside a meter row.
/// compact: overview cells with a top scale label. detailed: pane charts with a scale gutter and time axis.
enum PlotStyle { case micro, inline, compact, detailed }

/// Horizontal gridlines at even divisions; the baseline is drawn separately and stronger.
struct PlotGrid: Shape {
    let divisions: Int
    var verticals = 0
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<divisions {
            let y = (rect.minY + rect.height * CGFloat(index) / CGFloat(divisions)).rounded() + 0.25
            path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        if verticals > 0 {
            for index in 1..<verticals {
                let x = (rect.minX + rect.width * CGFloat(index) / CGFloat(verticals)).rounded() + 0.25
                path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
        return path
    }
}
struct PlotBaseline: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.minX, y: rect.maxY - 0.25)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 0.25)) }
    }
}
/// Where sampling began, while history is shorter than the window. Distinguishes "not yet sampled" from zero.
struct PlotStartMarker: Shape {
    let points: [Point]
    let window: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first?.time, let end = points.last?.time, window > 0 else { return path }
        let age = end - first
        guard age < window * 0.97 else { return path }
        let x = (rect.minX + rect.width * (1 - age / window)).rounded() + 0.25
        path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
        return path
    }
}

struct TelemetryPlot: View {
    let points: [Point]
    let layers: [PlotLayer]
    var floor: Double = 0
    let ceiling: Double
    let window: Double
    var unit: PlotUnit = .percent
    var style: PlotStyle = .compact
    var label = "History"
    var paused = false

    private let gutter: CGFloat = 52

    init(points: [Point], layers: [PlotLayer], floor: Double = 0, ceiling: Double, window: Double, unit: PlotUnit = .percent,
         style: PlotStyle = .compact, label: String = "History", paused: Bool = false) {
        self.points = points; self.layers = layers; self.floor = floor; self.ceiling = ceiling; self.window = window
        self.unit = unit; self.style = style; self.label = label; self.paused = paused
    }

    var body: some View {
        switch style {
        case .micro:
            lines(lineWidth: 1)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
        case .inline:
            ZStack {
                PlotBaseline().stroke(Palette.grid, lineWidth: Metrics.hairline)
                lines(lineWidth: 1.25).padding(.vertical, 1)
            }
            .accessibilityHidden(true)
        case .compact:
            ZStack(alignment: .topLeading) {
                PlotGrid(divisions: 2).stroke(Palette.grid, lineWidth: Metrics.hairline)
                PlotBaseline().stroke(Palette.baseline, lineWidth: Metrics.hairline)
                startMarker
                lines(lineWidth: 1.25).padding(.top, 1)
                Text(unit.axis(ceiling)).font(.scale10).foregroundStyle(Palette.quiet).padding(.top, 3)
                emptyState
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        case .detailed:
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ZStack {
                        // Vertical rules every 10 s, 30 s or 1 min for the 1, 3 and 10 minute windows.
                        PlotGrid(divisions: 4, verticals: window >= 600 ? 10 : 6).stroke(Palette.grid, lineWidth: Metrics.hairline)
                        PlotBaseline().stroke(Palette.baseline, lineWidth: Metrics.hairline)
                        startMarker
                        lines(lineWidth: 1.5).padding(.top, 1)
                        emptyState
                    }
                    scaleGutter
                }
                TimeAxis(window: window, paused: paused).padding(.trailing, gutter)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    private func lines(lineWidth: CGFloat) -> some View {
        PlotLines(points: points, layers: layers, floor: floor, ceiling: ceiling, window: window,
                  lineWidth: lineWidth, fillOpacity: style == .micro ? 0.18 : 0.13)
    }

    private var startMarker: some View {
        PlotStartMarker(points: points, window: window)
            .stroke(Palette.baseline, style: StrokeStyle(lineWidth: Metrics.hairline, dash: [2, 3]))
    }

    /// Two samples are needed before any rate exists, so an empty plot says which case applies.
    private var hasData: Bool { layers.contains { layer in points.contains { layer.series.value($0) != nil } } }
    @ViewBuilder private var emptyState: some View {
        if !hasData {
            Text(points.count < 2 ? "Collecting samples" : "Not reported")
                .font(.caption11).foregroundStyle(Palette.quiet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Right-hand scale: top, middle and bottom, each centred on its gridline.
    private var scaleGutter: some View {
        GeometryReader { geometry in
            ForEach([1.0, 0.5, 0.0], id: \.self) { fraction in
                Text(unit.axis(floor + (ceiling - floor) * fraction))
                    .font(.scale10).foregroundStyle(Palette.quiet).lineLimit(1)
                    .frame(width: gutter - 8, alignment: .leading)
                    .position(x: 8 + (gutter - 8) / 2, y: geometry.size.height * (1 - fraction))
            }
        }.frame(width: gutter)
    }

    private var accessibilityText: String {
        "\(label), last \(windowName(window)), scale \(unit.axis(floor)) to \(unit.axis(ceiling))" + (hasData ? "" : ", no data")
    }
}

/// "3 min ago … Now" under a plot. Reads "Paused" at the right edge while sampling is paused.
struct TimeAxis: View {
    let window: Double
    var paused = false
    var body: some View {
        HStack {
            Text(window >= 60 ? "\(Int(window / 60)) min ago" : "\(Int(window)) s ago")
            Spacer()
            Text(paused ? "Paused" : "Now")
        }
        .font(.scale10).foregroundStyle(Palette.quiet)
        .accessibilityHidden(true)
    }
}

// MARK: Native core renderers

/// Per-core utilization history. Cells are bucketed into eight opacity levels so each draw
/// fills about eight paths per cluster, regardless of history length.
struct CoreHeatmap: NSViewRepresentable {
    static let rowHeight: CGFloat = 12, rowGap: CGFloat = 5
    static let labelWidth: CGFloat = 34, valueWidth: CGFloat = 52
    static func height(rows: Int) -> CGFloat { CGFloat(max(1, rows)) * (rowHeight + rowGap) - rowGap }
    /// Opacity of each of the eight load levels; shared with the legend ramp.
    static func alpha(level: Int) -> Double { 0.14 + 0.86 * Double(level) / 7 }

    let points: [Point]
    let indices: [Int]
    let prefix: String
    let kind: String
    let window: Double
    func makeNSView(context: Context) -> HeatmapView { HeatmapView() }
    func updateNSView(_ view: HeatmapView, context: Context) {
        // History only ever appends and trims, so its ends and length identify what is drawn.
        // Any other publish (selection, preferences, hardware refresh) leaves the heatmap alone.
        guard view.points.count != points.count || view.points.first?.time != points.first?.time
            || view.points.last?.time != points.last?.time || view.timeWindow != window
            || view.prefix != prefix || view.kind != kind || view.indices != indices else { return }
        view.points = points; view.indices = indices; view.prefix = prefix; view.kind = kind
        view.tint = Palette.coreNS(kind); view.timeWindow = window
        view.needsDisplay = true
        let last = points.last
        view.setAccessibilityLabel("\(kind) core history. " + indices.enumerated().map { offset, index in
            "\(prefix)\(offset + 1): \(percent(last?.cores.indices.contains(index) == true ? last!.cores[index] : nil))"
        }.joined(separator: ", "))
    }
    final class HeatmapView: NSView {
        var points: [Point] = [], indices: [Int] = []
        var prefix = "", kind = "", timeWindow = 180.0
        var tint: NSColor = Palette.performanceNS {
            didSet { if tint != oldValue { levelColors = Self.colors(for: tint) } }
        }
        private var levelColors = colors(for: Palette.performanceNS)
        private static let trackColor = NSColor.white.withAlphaComponent(0.05).cgColor
        private static func colors(for tint: NSColor) -> [CGColor] {
            (0..<8).map { tint.withAlphaComponent(CoreHeatmap.alpha(level: $0)).cgColor }
        }
        private let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        private let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.labelColor]
        private let missingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
        override var isFlipped: Bool { true }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(true); setAccessibilityRole(.image)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func draw(_ dirtyRect: NSRect) {
            let labelWidth = CoreHeatmap.labelWidth, valueWidth = CoreHeatmap.valueWidth
            let rowHeight = CoreHeatmap.rowHeight, step = rowHeight + CoreHeatmap.rowGap
            let plotWidth = max(1, bounds.width - labelWidth - valueWidth)
            let geometry = HeatmapGeometry(points: points, indices: indices, window: timeWindow, plotWidth: plotWidth,
                                           labelWidth: labelWidth, rowHeight: rowHeight, rowStep: step)
            for (row, index) in indices.enumerated() {
                let y = CGFloat(row) * step
                let label = "\(prefix)\(row + 1)" as NSString
                label.draw(at: NSPoint(x: 0, y: y + (rowHeight - label.size(withAttributes: labelAttributes).height) / 2), withAttributes: labelAttributes)
                let current = points.last.flatMap { $0.cores.indices.contains(index) ? $0.cores[index] : nil }
                let value = percent(current) as NSString
                let attributes = current == nil ? missingAttributes : valueAttributes
                let size = value.size(withAttributes: attributes)
                value.draw(at: NSPoint(x: bounds.width - size.width, y: y + (rowHeight - size.height) / 2), withAttributes: attributes)
            }
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            context.setFillColor(Self.trackColor)
            context.addPath(geometry.track); context.fillPath()
            for (level, path) in geometry.levels.enumerated() where !path.isEmpty {
                context.setFillColor(levelColors[level])
                context.addPath(path); context.fillPath()
            }
            context.restoreGState()
        }
    }
}

/// Current load per core as a tile grid. Tile opacity follows utilization; text states the exact value.
struct CoreTileMap: NSViewRepresentable {
    static let columns = 6, tileHeight: CGFloat = 24, gap: CGFloat = 4
    static func height(cores: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(cores) / Double(columns))))
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap
    }
    let values: [Double]
    let kinds: [String]
    func makeNSView(context: Context) -> TileView {
        let view = TileView()
        view.setAccessibilityElement(true); view.setAccessibilityRole(.image)
        return view
    }
    func updateNSView(_ view: TileView, context: Context) {
        guard view.values != values || view.kinds != kinds else { return }
        let topologyChanged = view.values.count != values.count || view.kinds != kinds
        view.values = values; view.kinds = kinds
        if topologyChanged { view.rebuildTopology() }
        view.needsDisplay = true
        view.setAccessibilityLabel(view.order.enumerated().map { "\(view.labels[$0.offset]): \(percent(values[$0.element]))" }.joined(separator: ", "))
    }
    final class TileView: NSView {
        var values: [Double] = [], kinds: [String] = []
        override var isFlipped: Bool { true }
        func kind(_ index: Int) -> String { kinds.indices.contains(index) ? kinds[index] : "Cores" }
        func rank(_ kind: String) -> Int { kind == "Super" ? 0 : kind == "Performance" ? 1 : kind == "Efficiency" ? 2 : 3 }
        private(set) var order: [Int] = []
        private(set) var labels: [String] = []
        func rebuildTopology() {
            order = values.indices.sorted { rank(kind($0)) == rank(kind($1)) ? $0 < $1 : rank(kind($0)) < rank(kind($1)) }
            var counts: [String: Int] = [:]
            labels = order.map { index in
                let k = kind(index)
                counts[k, default: 0] += 1
                return k == "Cores" ? "C\(counts[k]!)" : "\(k.prefix(1))\(counts[k]!)"
            }
        }
        override func draw(_ dirtyRect: NSRect) {
            let columns = CoreTileMap.columns, gap = CoreTileMap.gap, height = CoreTileMap.tileHeight
            let width = (bounds.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let labelAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.62)]
            let valueAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.95)]
            // Placeholder tiles before the first two samples, so the grid keeps its shape.
            if values.isEmpty {
                for position in 0..<max(0, kinds.count) {
                    let rect = NSRect(x: CGFloat(position % columns) * (width + gap), y: CGFloat(position / columns) * (height + gap), width: width, height: height)
                    NSColor.white.withAlphaComponent(0.05).setFill(); NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
                }
                return
            }
            for (position, index) in order.enumerated() {
                let k = kind(index)
                let rect = NSRect(x: CGFloat(position % columns) * (width + gap), y: CGFloat(position / columns) * (height + gap), width: width, height: height)
                let tile = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                NSColor.white.withAlphaComponent(0.05).setFill(); tile.fill()
                let usage = min(100, max(0, values[index]))
                Palette.coreNS(k).withAlphaComponent(0.12 + usage / 100 * 0.68).setFill(); tile.fill()
                let label = labels[position] as NSString
                let labelSize = label.size(withAttributes: labelAttributes)
                label.draw(at: NSPoint(x: rect.minX + 7, y: rect.midY - labelSize.height / 2), withAttributes: labelAttributes)
                let value = decimal(usage, places: 0) as NSString
                let valueSize = value.size(withAttributes: valueAttributes)
                value.draw(at: NSPoint(x: rect.maxX - 7 - valueSize.width, y: rect.midY - valueSize.height / 2), withAttributes: valueAttributes)
            }
        }
    }
}
