import SwiftUI

// MARK: Bands

/// One continuous instrument band. Columns are separated by keylines, not separate cards,
/// so column edges line up across bands that share a column count.
struct Band<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        HStack(alignment: .top, spacing: 0) { content }
            .fixedSize(horizontal: false, vertical: true)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.bandRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.bandRadius, style: .continuous).strokeBorder(Palette.keyline, lineWidth: Metrics.hairline))
    }
}

extension View {
    /// Standard cell padding and fill behaviour inside a `Band`.
    func cellLayout() -> some View {
        padding(.horizontal, Metrics.cellHorizontal).padding(.vertical, Metrics.cellVertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    /// Keyline on the leading edge of every band column after the first.
    func leadingKeyline(_ visible: Bool = true) -> some View {
        overlay(alignment: .leading) { if visible { Palette.keyline.frame(width: Metrics.hairline) } }
    }
    /// Full-bleed horizontal keyline inside a `cellLayout()` cell, matching the band's column keylines.
    func bandDivider() -> some View {
        overlay(alignment: .top) { Palette.keyline.frame(height: Metrics.hairline).padding(.horizontal, -Metrics.cellHorizontal) }
    }
    /// Tooltip only when there is something to say.
    @ViewBuilder func help(ifPresent text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}

/// A band column that opens a pane. Hover lifts the fill slightly; the system focus ring handles keyboard focus.
struct BandCellButton<Label: View>: View {
    let help: String
    let action: () -> Void
    let label: Label
    let leadingEdge: Bool
    let trailingEdge: Bool
    init(help: String, leadingEdge: Bool = false, trailingEdge: Bool = false,
         action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.help = help; self.action = action; self.label = label()
        self.leadingEdge = leadingEdge; self.trailingEdge = trailingEdge
    }
    var body: some View {
        Button(action: action) { label.cellLayout().contentShape(Rectangle()) }
            .buttonStyle(HoverFillStyle(radius: Metrics.bandRadius, roundLeading: leadingEdge, roundTrailing: trailingEdge))
            .help(help)
            .accessibilityHint(help)
    }
}

struct HoverFillStyle: ButtonStyle {
    var radius: CGFloat = 0
    var roundLeading = true
    var roundTrailing = true
    func makeBody(configuration: Configuration) -> some View {
        HoverFill(configuration: configuration, radius: radius, roundLeading: roundLeading, roundTrailing: roundTrailing)
    }
    private struct HoverFill: View {
        let configuration: ButtonStyleConfiguration
        let radius: CGFloat
        let roundLeading: Bool
        let roundTrailing: Bool
        // Explicit State value: the toolchain lacks the SwiftUI macro plugin behind `@State`.
        private let hovering = SwiftUI.State(initialValue: false)
        var body: some View {
            configuration.label
                .background(Color.white.opacity(configuration.isPressed ? 0.07 : hovering.wrappedValue ? 0.035 : 0), in: UnevenRoundedRectangle(topLeadingRadius: roundLeading ? radius : 0,
                    bottomLeadingRadius: roundLeading ? radius : 0, bottomTrailingRadius: roundTrailing ? radius : 0,
                    topTrailingRadius: roundTrailing ? radius : 0, style: .continuous))
                .onHover { hovering.wrappedValue = $0 }
        }
    }
}

// MARK: Headings

/// Title row used by every band cell: tinted glyph, neutral title, optional trailing accessory.
struct CellHeader<Accessory: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let accessory: Accessory
    init(_ title: String, icon: String, tint: Color, @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.icon = icon; self.tint = tint; self.accessory = accessory()
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(tint).frame(width: 14)
                .accessibilityHidden(true)
            Text(title).font(.cellTitle).foregroundStyle(.primary).lineLimit(1).layoutPriority(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            accessory.font(.caption11).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(height: 16)
        // Contain, not combine: accessory links such as "Show all" must stay individually reachable.
        .accessibilityElement(children: .contain)
    }
}
extension CellHeader where Accessory == EmptyView {
    init(_ title: String, icon: String, tint: Color) { self.init(title, icon: icon, tint: tint) { EmptyView() } }
}

/// Inline navigation link for header accessories. Keeps the link tint inside secondary-styled slots.
struct LinkButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(title, action: action).buttonStyle(.link).foregroundStyle(Color.accentColor).font(.caption11)
    }
}

struct SectionHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory
    init(_ title: String, @ViewBuilder accessory: () -> Accessory) { self.title = title; self.accessory = accessory() }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(.sectionTitle).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            accessory.font(.caption11).foregroundStyle(.secondary)
        }.frame(minHeight: 22)
    }
}
extension SectionHeader where Accessory == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

/// Definitions that matter but need not be read every time: a quiet ⓘ that opens a popover.
struct InfoButton: View {
    let title: String
    let notes: [String]
    private let presented = SwiftUI.State(initialValue: false)
    init(_ title: String, notes: [String]) { self.title = title; self.notes = notes }
    var body: some View {
        Button { presented.wrappedValue.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: presented.projectedValue, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 12, weight: .semibold))
                ForEach(notes, id: \.self) { note in
                    Text(note).font(.caption11).foregroundStyle(.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).frame(width: 320, alignment: .leading)
        }
    }
}

// MARK: Values

/// A measured value with its unit set smaller and quieter, e.g. "31.0" + " GB".
struct Readout: View {
    let text: String
    var size: CGFloat = 22
    var weight: Font.Weight = .medium
    var body: some View {
        let (number, unit) = Readout.split(text)
        Text("\(Text(number).font(.system(size: size, weight: weight)).foregroundStyle(number == "—" ? .tertiary : .primary))\(Text(unit).font(.system(size: (size * 0.6).rounded(), weight: .regular)).foregroundStyle(.secondary))")
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            .accessibilityLabel(text)
    }
    static func split(_ text: String) -> (String, String) {
        let numeric = text.prefix { $0.isNumber || $0 == "." || $0 == "-" || $0 == "−" || $0 == "," }
        guard !numeric.isEmpty else { return (text, "") }
        return (String(numeric), String(text.dropFirst(numeric.count)))
    }
}

/// One line that steps down to a shorter wording rather than truncating mid-phrase.
struct FittingText: View {
    let full: String
    let short: String
    init(_ full: String, short: String) { self.full = full; self.short = short }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(full).fixedSize()
            Text(short).lineLimit(1)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(full)
    }
}

/// Label, visual, value: the shared row for fans, GPU engines, temperatures, battery and power.
struct MeterRow<Visual: View>: View {
    let label: String
    let value: String
    var labelWidth: CGFloat = 48
    let visual: Visual
    init(_ label: String, value: String, labelWidth: CGFloat = 48, @ViewBuilder visual: () -> Visual) {
        self.label = label; self.value = value; self.labelWidth = labelWidth; self.visual = visual()
    }
    var body: some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
            visual.frame(maxWidth: .infinity)
            Text(value).monospacedDigit().foregroundStyle(value == "—" ? .tertiary : .primary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .font(.caption11).lineLimit(1).frame(height: Metrics.rowHeight)
        .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value)
    }
}
extension MeterRow where Visual == Color {
    /// Value-only row that keeps the label and value columns aligned with its neighbours.
    init(_ label: String, value: String, labelWidth: CGFloat = 48) {
        self.init(label, value: value, labelWidth: labelWidth) { Color.clear }
    }
}

/// Horizontal level against a known maximum. Unknown values draw only the track.
struct LevelBar: View {
    let fraction: Double?
    let tint: Color
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                if let fraction, fraction.isFinite {
                    Capsule().fill(tint).frame(width: max(fraction > 0 ? height : 0, geometry.size.width * min(1, max(0, fraction))))
                }
            }
        }.frame(height: height)
    }
}

/// Proportional composition bar. Segment widths always sum to the measured total.
struct SegmentedBar: View {
    let segments: [(value: Double, tint: Color)]
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { geometry in
            let total = segments.reduce(0) { $0 + max(0, $1.value) }
            let visible = segments.filter { $0.value > 0 }
            let gaps = CGFloat(max(0, visible.count - 1))
            HStack(spacing: 1) {
                if total > 0 {
                    ForEach(visible.indices, id: \.self) { index in
                        Rectangle().fill(visible[index].tint)
                            .frame(width: max(0, geometry.size.width - gaps) * visible[index].value / total)
                    }
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .background(Palette.track)
            .clipShape(Capsule())
        }.frame(height: height)
    }
}

/// Line sample + series name + current value. Solid / dashed matches the plotted stroke.
struct SeriesKey: View {
    let title: String
    let value: String?
    let tint: Color
    var dashed = false
    var body: some View {
        HStack(spacing: 6) {
            LineSwatch(tint: tint, dashed: dashed)
            Text(title).foregroundStyle(.secondary)
            if let value { Text(value).monospacedDigit().foregroundStyle(value == "—" ? .tertiary : .primary) }
        }.font(.caption11).lineLimit(1).fixedSize()
            .accessibilityElement(children: .combine)
    }
}
struct LineSwatch: View {
    let tint: Color
    var dashed = false
    var body: some View {
        Path { path in path.move(to: CGPoint(x: 0, y: 1)); path.addLine(to: CGPoint(x: 12, y: 1)) }
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .butt, dash: dashed ? [3, 2] : []))
            .frame(width: 12, height: 2)
            .accessibilityHidden(true)
    }
}
struct ChipSwatch: View {
    let tint: Color
    var body: some View { RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 8, height: 8).accessibilityHidden(true) }
}
struct SwatchLabel: View {
    let title: String
    let tint: Color
    var body: some View {
        HStack(spacing: 5) { ChipSwatch(tint: tint); Text(title).foregroundStyle(.secondary) }.font(.caption11).fixedSize()
    }
}

/// Swatch + name + value: legend entry for composition bars.
struct SwatchValue: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        HStack(spacing: 5) {
            ChipSwatch(tint: tint)
            if !title.isEmpty { Text(title).foregroundStyle(.secondary) }
            Text(value).monospacedDigit().foregroundStyle(value == "—" ? .tertiary : .primary)
        }.font(.caption11).lineLimit(1).fixedSize().accessibilityElement(children: .combine)
    }
}

/// Legend entries on one line when they fit, otherwise in an aligned grid. Never clipped.
struct LegendFlow<Content: View>: View {
    var spacing: CGFloat = 18
    let content: Content
    init(spacing: CGFloat = 18, @ViewBuilder content: () -> Content) { self.spacing = spacing; self.content = content() }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: spacing, alignment: .leading)], alignment: .leading, spacing: 8) { content }
        }
    }
}

/// Eight-step opacity ramp matching the core heatmap's load buckets.
struct LoadRamp: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("0%")
            HStack(spacing: 1) {
                ForEach(0..<8, id: \.self) { level in
                    Rectangle().fill(Color.white.opacity(CoreHeatmap.alpha(level: level))).frame(width: 7, height: 7)
                }
            }
            Text("100%")
        }
        .font(.scale10).foregroundStyle(Palette.quiet).fixedSize()
        .accessibilityElement(children: .ignore).accessibilityLabel("Brighter means higher load, from 0 to 100 percent")
    }
}

/// Every fan the SMC reports, against its own reported maximum. Read-only.
struct FanList: View, Equatable {
    private let fan0: Double?, fan1: Double?, fan0Max: Double?, fan1Max: Double?
    let labelWidth: CGFloat
    init(hardware: HardwareMetrics, labelWidth: CGFloat = 48) {
        fan0 = hardware.fan0; fan1 = hardware.fan1
        fan0Max = hardware.fan0Max; fan1Max = hardware.fan1Max
        self.labelWidth = labelWidth
    }
    var body: some View {
        let fans = [(fan0, fan0Max), (fan1, fan1Max)].filter { $0.0 != nil || $0.1 != nil }
        if fans.isEmpty {
            Text("No fans reported").font(.caption11).foregroundStyle(.secondary).frame(height: Metrics.rowHeight)
        } else {
            ForEach(fans.indices, id: \.self) { index in
                FanRow(name: fans.count == 1 ? "Fan" : "Fan \(index + 1)", speed: fans[index].0, maximum: fans[index].1, labelWidth: labelWidth)
            }
        }
    }
}
struct FanRow: View {
    let name: String
    let speed: Double?
    let maximum: Double?
    var labelWidth: CGFloat = 48
    var body: some View {
        MeterRow(name, value: rpm(speed), labelWidth: labelWidth) {
            LevelBar(fraction: speed.flatMap { s in maximum.flatMap { $0 > 0 ? s / $0 : nil } }, tint: Palette.fan)
        }.help(maximum.map { "Bar spans 0 to \(Int($0)) rpm, this fan's reported maximum" } ?? "Maximum speed not reported")
    }
}

/// Dot + text for system states. Traffic colours appear only here.
struct StatusIndicator: View {
    let label: String
    let state: String
    let tint: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(label).foregroundStyle(.secondary)
            Text(state).foregroundStyle(.primary)
        }.font(.caption11).fixedSize()
            .accessibilityElement(children: .combine)
    }
}

// MARK: Stats and tables

struct Stat: Identifiable {
    let label: String
    let value: String
    var note: String?
    var help: String?
    var id: String { label }
    init(_ label: String, _ value: String, note: String? = nil, help: String? = nil) {
        self.label = label; self.value = value; self.note = note; self.help = help
    }
}

/// Secondary figures under a chart. One evenly spaced row when it fits, otherwise a grid.
struct StatStrip: View {
    let stats: [Stat]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(stats) { StatCell(stat: $0).frame(maxWidth: .infinity, alignment: .leading) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .topLeading), count: stats.count > 4 ? 3 : 2),
                      alignment: .leading, spacing: 14) {
                ForEach(stats) { StatCell(stat: $0) }
            }
        }
    }
}
struct StatCell: View {
    let stat: Stat
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stat.label).font(.caption11).foregroundStyle(.secondary).lineLimit(1)
            Text(stat.value).font(.stat).foregroundStyle(stat.value == "—" ? .tertiary : .primary).lineLimit(1).minimumScaleFactor(0.8)
            if let note = stat.note { Text(note).font(.caption11).foregroundStyle(Palette.quiet).lineLimit(1) }
        }
        .accessibilityElement(children: .combine)
        .help(ifPresent: stat.help)
    }
}

struct ColumnSpec: Identifiable {
    let title: String
    let width: CGFloat?
    var trailing = false
    var id: String { title }
}

/// Column headings for in-band tables; widths match `DataRow` exactly.
struct DataHeader: View {
    let columns: [ColumnSpec]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(columns) { column in
                Text(column.title).frame(maxWidth: column.width ?? .infinity, alignment: column.trailing ? .trailing : .leading)
                    .frame(width: column.width)
            }
        }
        .font(.caption11).foregroundStyle(.secondary).frame(height: 24)
        .overlay(alignment: .bottom) { Palette.keyline.frame(height: Metrics.hairline) }
        .accessibilityHidden(true)
    }
}
struct DataRow: View {
    let columns: [ColumnSpec]
    let values: [String]
    var body: some View {
        HStack(spacing: 12) {
            ForEach(columns.indices, id: \.self) { index in
                let column = columns[index]
                // Names and measured (trailing) values read as primary; descriptive columns recede.
                Text(values[index])
                    .foregroundStyle(values[index] == "—" ? .tertiary : index == 0 || column.trailing ? .primary : .secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: column.width ?? .infinity, alignment: column.trailing ? .trailing : .leading)
                    .frame(width: column.width)
            }
        }
        .font(.body12).monospacedDigit().frame(height: Metrics.tableRow)
        .overlay(alignment: .bottom) { Palette.keyline.opacity(0.6).frame(height: Metrics.hairline) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zip(columns, values).map { "\($0.title) \($1)" }.joined(separator: ", "))
    }
}
/// Placeholder row inside an in-band table.
struct EmptyRow: View {
    let text: String
    var body: some View {
        Text(text).font(.body12).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: Metrics.tableRow + 8, alignment: .leading)
    }
}

/// Short caption below a pane element, kept to a readable measure.
struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption11).foregroundStyle(.secondary).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640, alignment: .leading)
    }
}

/// One-line statement of what a view does not measure, set where the misreading would happen.
struct Notice: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle").foregroundStyle(.tertiary).accessibilityHidden(true)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption11).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Inline placeholder where a measurement cannot be read. Says what is missing and why.
struct Unmeasured: View {
    let headline: String
    let reason: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(.system(size: 12, weight: .medium))
                Text(reason).font(.caption11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.keyline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .accessibilityElement(children: .combine)
    }
}
