# Claude design consultation

Model reported by the CLI: claude-opus-5-5. Requested by the user. This is a design proposal, not a claim that every proposed feature is implemented. Taskglass uses lightweight vector paths and an AppKit core heatmap instead of the suggested Canvas renderer. Hardware names and counters are validated against this Mac.

# Taskglass redesign: an instrument, not a dashboard

I read `ContentView.swift`, `Graphs.swift`, `Monitor.swift`, `Sampling.swift` and the screenshot, and didn't edit anything. This is a spec only. None of it is built or tested.

## 1. What's wrong now

- **The two hero charts waste space.** Memory is plotted on a fixed 0–100% scale, so it's a flat line across about 900 px. CPU sits at the bottom 10% of a 130 pt box. Most of the chart area carries no information.
- **Cores have numbers but no identity.** In the screenshot, cores 7–12 all read 0.0%. That's very likely a parked cluster, but without P/E labels it looks like a bug. Eighteen `ProgressView`s are also the most expensive way to show the least information.
- **Nothing has a fixed position.** Everything is the same weight, with `.textBackgroundColor` across the whole window, a 22 pt "This Mac" header, and a status bar that repeats the core count. Your eye has nowhere to settle.
- **There are two navigation models.** A segmented control switches pages, then a scroll view has to hold everything.

**Point of view:** Taskglass should look like an instrument panel. That means:
- Every resource is always visible in a rail on the left.
- Every chart shares one time axis.
- Every chart has a fixed, labelled scale.
- Hardware is named: "P3", not "3"; "Apple M4 Pro GPU · 20 cores", not "GPU".
- Missing data is shown as missing, never drawn as zero.

## 2. Navigation structure

Replace the segmented picker with a `NavigationSplitView`. On macOS 26 the sidebar and toolbar become real Liquid Glass automatically. That's the only glass in the app. Content stays on a plain window background, with no glass cards.

```
Sidebar (Liquid Glass)        Detail (opaque, semantic background)
───────────────────────       ─────────────────────────────────────
  ≣  Processes                ← the existing Table, unchanged + inspector
  ◔  Overview                 ← time-aligned strips + top processes
 RESOURCES
 [╱╲_]  CPU        12%        ← micrograph 44×24 + name + live value
 [▁▁▁]  Memory  29.2 GB
 [▁▅▇]  GPU        38%
 [┄┄┄]  Neural Engine  Not reported   ← dimmed, still listed
 [▁▁▃]  Macintosh HD  1.2 MB/s        ← one row per physical disk
 [▂▁▃]  Network  368 KB/s ↓
 [▇▇▇]  Battery    82% ⚡              ← row omitted entirely on desktops
```

**Rules:**
- **Hardware that doesn't exist is hidden.** A desktop Mac has no Battery row.
- **Hardware that exists but can't be measured is shown, dimmed,** with a reason in its pane. The Neural Engine on a machine without a readable power channel is the main case.
- **The toolbar follows the selected pane.**
  - Processes: native `.searchable`, filter menu and inspector toggle.
  - Every pane: Pause, a time-window menu (1 / 3 / 10 min), and `⋯`.
- **The status bar goes away.** Counts move to `.navigationSubtitle` ("412 processes · 3,912 threads", or "Paused").
- **The 78 pt summary under the process table also goes.** The rail already shows the same numbers, and the table gets the height back.

## 3. Type, spacing and colour

All system font. Numbers always use `.monospacedDigit()`.

| Role | Size / weight | Style |
|---|---|---|
| Pane title | 20 semibold | `.primary` |
| Hardware line under title | 12 regular | `.secondary` |
| Hero value (top right) | 28 regular, mono digits | `.primary` |
| Hero caption | 11 regular | `.secondary` |
| Section header | 13 semibold (`.headline`) | `.primary` |
| Stat value | 15 medium, mono digits | `.primary`; nil → "—" in `.tertiary` |
| Stat label | 11 regular | `.secondary` |
| Overview strip value | 17 medium, mono digits | |
| Rail name / rail value | 13 medium / 11 regular mono | `.primary` / `.secondary` |
| Axis and scale labels | 10 regular, mono digits | `.tertiary` |

**Spacing** is on a 4 pt grid:

| Element | Value |
|---|---|
| Pane padding | 28 horizontal, 20 top, 28 bottom |
| Content width | max 1080, centred |
| Header → chart | 16 |
| Chart → time axis | 4 |
| Between sections | 28 |
| Stat grid gaps | 24 between columns, 14 between rows |
| Primary chart height | **fixed 168**, never flexible |
| Secondary chart height | 96 |
| Overview strip height | 56 |
| Rail micrograph | 44×24 |
| Core heatmap row | 12, with a 3 pt gap |
| Gap between clusters | 14 |
| Sidebar width | min 210, ideal 232, max 280 |

**Colour:** colour appears only in the data, never in the chrome.

| Resource | Colour |
|---|---|
| CPU | `systemBlue` (system time is the same blue at 55% opacity) |
| Memory | `systemPurple` |
| GPU | `systemOrange` |
| Neural Engine | `systemPink` |
| Disk | `systemTeal` |
| Network | `systemCyan` |
| Battery | `systemGreen` |

- Memory pressure is the only place traffic-light colours appear (green / yellow / red).
- Gridlines are `Color.primary.opacity(0.06)` and the baseline is `0.14`.
- Plot wells are `Color.primary.opacity(0.035)` with a 4 pt radius and a 0.5 pt `separatorColor` stroke.
- All of these adapt to light and dark automatically.

## 4. Pane layouts

### Overview

The overview is one table of strips on a shared time axis. Hovering anywhere draws a vertical line through every strip, and each value column switches to the value at that moment (with a "−42 s" label). That lets you correlate spikes across resources, which a grid of cards can't do.

```
Overview                                   MacBook Pro · M4 Pro · up 4d 3h
Memory pressure normal · Thermal nominal · Battery 82%, charging
──────────────────────────────────────────────────────────────────────────
CPU          12.4%  │▁▂▁▃▅▂▁▁▂▁▁▃▇▅▂▁▁▁▂▁▁▁▁▂▃▁▁▂│  P 21% · E 9%
GPU            38%  │▁▁▁▁▂▅▇▇▆▅▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁│  Renderer 35% · 6.4 GB
Memory     29.2 GB  │▆▆▆▆▆▆▆▆▆▆▆▆▆▆▇▆▆▆▆▆▆▆▆▆▆▆▆│  of 48 GB · ● Normal
Neural Eng.  0.4 W  │▁▁▁▁▁▁▁▃▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁│  power, not utilization
Disk       1.2 MB/s │▁▁▃▁▁▁▁▁▁▁▁▁▆▁▁▁▁▁▁▁▁▁▁▁▁▁▁│  ↑R 1.1 · ↓W 0.1
Network    368 KB/s │▂▁▃▂▂▁▁▁▂▁▁▁▂▁▁▁▃▁▁▁▂▁▁▁▁▁▁│  ↓368 KB/s · ↑55 KB/s
              3 min ago ┊          ┊          ┊          now
──────────────────────────────────────────────────────────────────────────
Top processes           CPU     Memory              (5 rows, click → Processes)
```

- **Strip columns:** label and value 128 pt | plot (flexible, at least 320) | context 200 pt.
- **Top processes:** sampled every third tick so the overview stays light.

### CPU

The P/E heatmap replaces the 18 progress bars. Each core gets one row 12 pt tall, showing its history as cells whose opacity follows utilization.

```
CPU                                                            12.4%
Apple M4 Pro · 14 cores (10 Performance, 4 Efficiency)    User 8.1 · Sys 4.3
┌100 ─────────────────────────────────────────────────────────────────┐
│          stacked area: system (dark) under user (light)       168pt │
└  0 ────────────────────────────────────────────────── 3 min ··· now ┘
Performance cores                                              avg 21%
 P1 ░░▒▒▓▓█▓▒░░░░▒▒▓▒░░░░░░░▒▒▓▓▒░░░░░░░░▒▒░░░░░░░░░░░░░▒▒▓      23%
 P2 ░░▒▓▓▒░░░░░░░▒▓▓▒░░░░░░░░▒▒▒░░░░░░░░░░▒░░░░░░░░░░░░░▒▒      22%
 …
Efficiency cores                                                avg 9%
 E1 ▒▒▒▒▒▒▒▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒       8%
──────────────────────────────────────────────────────────────────────
Utilization  User   System  Idle   Load (1/5/15)   Processes  Threads  Uptime
```

**Getting P/E labels right:**
- Read cluster counts with `sysctl hw.nperflevels` and `hw.perflevel{0,1}.logicalcpu`.
- Read which CPU index belongs to which cluster from each IODeviceTree `cpus/*` node's `cluster-type` property.
- **Don't assume E cores come first.** If the mapping can't be read, label the rows "Core 1…n" and group them as "Cores".

### Memory

```
Memory                                              29.2 GB of 48 GB
┌ App ████████████ Wired ███ Compressed ██ Cached ██████ Free ░░░░░░ ┐ 14pt bar
  legend row: ■ App 14.6 GB  ■ Wired 3.8  ■ Compressed 5.3  ■ Cached 16.6 …
┌ stacked used (0 … 48 GB) — 96pt                                     ┐
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ pressure band 3pt (green/yellow/red)
Pressure  Swap used  Compressed  Wired  Cached files  GPU allocated (unified)
```

### GPU

```
GPU                                                               38%
Apple M4 Pro GPU · 20 cores                              Device utilization
┌100 ── Device (filled) · Renderer (line) · Tiler (dashed) ── 168pt ─┐
└  0 ────────────────────────────────────────────────── 3 min ··· now ┘
Device 38%   Renderer 35%   Tiler 12%   In use 3.1 GB   Allocated 6.4 GB
Unified memory  [GPU allocated ████][other used ██████████][free ░░░░] 48 GB
```

- **Data source:** the IOAccelerator `PerformanceStatistics` keys, plus `model` and `gpu-core-count` from the AGX accelerator's registry entry. Don't create an `MTLDevice` just to get the GPU's name, because that loads Metal into a monitor that's meant to stay light.
- **Memory:** show allocated memory as a slice of unified memory, never as "VRAM".
- **If a key is missing:** remove that series and its stat. Don't show 0%.

### Neural Engine

Watts are not a utilization figure, and the pane should never present them as one.

```
Neural Engine                                                  0.42 W
Apple M4 Pro                                                Power draw
Power is not utilization. macOS doesn't report Neural Engine usage.
┌ 2 W ── auto-scaled power, labelled in W ───────────── 168pt ────────┐
└ 0 W ───────────────────────────────────────────────── 3 min ··· now ┘
Now 0.42 W   Average 0.12 W   Peak 1.8 W   Energy since opened 0.03 Wh
```

When no power channel can be read, show a 56 pt dashed well instead of a chart:

```
┌┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┐
┊ ◌  Neural Engine power isn't available on this Mac.                 ┊
┊    macOS doesn't expose Neural Engine utilization to apps.          ┊
└┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┘
```

Don't show a Neural Engine core count unless it comes from a source you've checked.

### Disk, Network and Battery

- **Disk (one pane per physical disk):**
  - Mirrored chart: read above the axis, write below.
  - Stats: read, write, totals since opened, and a capacity bar (used / purgeable / available, using `volumeAvailableCapacityForImportantUsage`).
  - If there's more than one physical disk, add a segmented picker in the header.
- **Network:**
  - Mirrored chart: download above, upload below.
  - A per-interface list (Wi-Fi, Ethernet, Thunderbolt) with its own rates.
  - Totals since opened.
- **Battery:**
  - Charge chart, 0–100, 96 pt.
  - Signed power chart, ±W, 96 pt, with discharging below the axis.
  - Stats: state ("Charging · 61 W adapter"), time remaining, cycles, max capacity %, temperature °C, voltage.

### Process inspector

Use the real app icon (`NSRunningApplication.icon`, falling back to `NSWorkspace.icon(forFile:)`) in place of the generic `"app"` symbol.

## 5. Scales and honesty rules

1. **Percent charts** are always 0–100, with gridlines at 50 and 100 and labels on the right inside the plot (10 pt, `.tertiary`).
2. **Rate and power charts** use a "nice" ceiling (1/2/5 × 10ⁿ) of the visible window's peak, with a floor (1 MB/s, 100 mW) so the scale doesn't jump at idle. The scale is always written on the chart.
3. **Gaps are drawn as gaps.** Missing samples are stored as `.nan`, and the line breaks there.
4. **Unknown values show "—" in `.tertiary`.** Never 0.
5. **Every series names its exact source:** "Device utilization", "Power draw", "Physical disk I/O".

## 6. Key SwiftUI code

**Navigation root:**
```swift
enum Pane: Hashable { case processes, overview, cpu, memory, gpu, neuralEngine, disk(String), network, battery }

NavigationSplitView {
    List(selection: $model.pane) {
        Label("Processes", systemImage: "list.bullet.rectangle").tag(Pane.processes)
        Label("Overview", systemImage: "gauge.with.dots.needle.33percent").tag(Pane.overview)
        Section("Resources") {
            ForEach(model.resources) { r in RailRow(resource: r).tag(r.pane) }
        }
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 280)
} detail: {
    switch model.pane {
    case .processes: ProcessTable(monitor: monitor)
    case .overview:  OverviewPane(model: model)
    case .cpu:       CPUPane(model: model.cpu)
    default:         ResourcePaneRouter(model: model)
    }
}
.navigationTitle(model.pane.title)
.navigationSubtitle(model.subtitle)
.inspector(isPresented: $monitor.showingInspector) { inspector }
```

**History storage:** `Float` values, `.nan` for gaps, a fixed capacity, and history kept per series.
```swift
struct Series {
    let capacity: Int
    private(set) var values: [Float] = []
    mutating func append(_ v: Double?) {
        values.append(v.map(Float.init) ?? .nan)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
    var peak: Float { values.lazy.filter { !$0.isNaN }.max() ?? 0 }
}

func niceCeiling(_ x: Double, floor f: Double) -> Double {
    let x = max(x, f), e = pow(10, (log10(x)).rounded(.down))
    return [1, 2, 5, 10].map { $0 * e }.first { $0 >= x }!
}

func plotPath(_ v: [Float], ceiling: Float, capacity: Int, in r: CGRect) -> Path {
    var p = Path(); var pen = false
    let dx = r.width / CGFloat(max(1, capacity - 1)), x0 = r.maxX - CGFloat(v.count - 1) * dx
    for (i, y) in v.enumerated() {
        guard !y.isNaN else { pen = false; continue }            // truthful gap
        let pt = CGPoint(x: x0 + CGFloat(i) * dx, y: r.maxY - r.height * CGFloat(min(1, y / ceiling)))
        pen ? p.addLine(to: pt) : p.move(to: pt); pen = true
    }
    return p
}
```

**Rail row and micrograph:** one `Canvas`, no subviews.
```swift
struct Micrograph: View {
    let series: Series; let ceiling: Float; let tint: Color
    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(.primary.opacity(0.035)))
            let line = plotPath(series.values, ceiling: ceiling, capacity: series.capacity, in: r.insetBy(dx: 1.5, dy: 2.5))
            ctx.stroke(line, with: .color(tint), lineWidth: 1)
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

struct RailRow: View {
    let resource: ResourceSummary   // title, value: String?, series, ceiling, tint, measurable
    var body: some View {
        HStack(spacing: 10) {
            Micrograph(series: resource.series, ceiling: resource.ceiling, tint: resource.tint)
                .frame(width: 44, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(resource.title).font(.system(size: 13, weight: .medium))
                Text(resource.value ?? "Not reported").font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(resource.value == nil ? .tertiary : .secondary)
            }
        }
        .padding(.vertical, 3)
        .opacity(resource.measurable ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}
```

**Pane scaffold:** every focused pane uses the same structure.
```swift
struct ResourcePane<Chart: View, Content: View>: View {
    let title: String, hardware: String, value: String?, caption: String
    @ViewBuilder var chart: Chart
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 20, weight: .semibold))
                        Text(hardware).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(value ?? "—").font(.system(size: 28)).monospacedDigit()
                        Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                chart.frame(height: 168).padding(.top, 16)
                content.padding(.top, 28)
            }
            .padding(EdgeInsets(top: 20, leading: 28, bottom: 28, trailing: 28))
            .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }
    }
}

struct Stat: Identifiable { let label: String; let value: String?; var id: String { label } }
struct StatGrid: View {
    let stats: [Stat]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 190), spacing: 24, alignment: .leading)],
                  alignment: .leading, spacing: 14) {
            ForEach(stats) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.label).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(s.value ?? "—").font(.system(size: 15, weight: .medium)).monospacedDigit()
                        .foregroundStyle(s.value == nil ? .tertiary : .primary)
                }
            }
        }
    }
}
```

**Core heatmap:** opacity is rounded to 8 levels, so each tick is about 8 fills plus labels, not 1,600 rectangles.
```swift
struct CoreHeatmap: View {
    struct Core { let label: String; let history: Series; let now: Double? }
    let cores: [Core]; let tint: Color
    var body: some View {
        Canvas { ctx, size in
            let labelW: CGFloat = 28, valueW: CGFloat = 44, rowH: CGFloat = 12, gap: CGFloat = 3
            let plotW = size.width - labelW - valueW
            var buckets = Array(repeating: Path(), count: 8)
            for (row, core) in cores.enumerated() {
                let y = CGFloat(row) * (rowH + gap)
                let w = plotW / CGFloat(core.history.capacity)
                let x0 = labelW + plotW - CGFloat(core.history.values.count) * w
                for (i, v) in core.history.values.enumerated() where !v.isNaN {
                    buckets[min(7, Int(v / 12.5))].addRect(CGRect(x: x0 + CGFloat(i) * w, y: y, width: max(0.5, w - 0.5), height: rowH))
                }
                ctx.draw(Text(core.label).font(.system(size: 10)).foregroundStyle(.secondary), at: CGPoint(x: 0, y: y + rowH / 2), anchor: .leading)
                ctx.draw(Text(percent(core.now)).font(.system(size: 10)).monospacedDigit(), at: CGPoint(x: size.width, y: y + rowH / 2), anchor: .trailing)
            }
            for (level, path) in buckets.enumerated() {
                ctx.fill(path, with: .color(tint.opacity(0.08 + 0.92 * Double(level) / 7)))
            }
        }
        .frame(height: CGFloat(cores.count) * 15)
    }
}
```
Render one `CoreHeatmap` per cluster under its section header, 14 pt apart.

**Missing-data state:** used inline wherever a chart would go.
```swift
struct Unmeasured: View {
    let headline: String, reason: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 13, weight: .medium))
                Text(reason).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14).frame(minHeight: 56)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(.separator))
    }
}
```

**Overview hover scrubber:** one shared index across all strips.
```swift
@State private var scrub: Int?   // owned by OverviewPane, passed as Binding to every strip
plot
    .onContinuousHover { phase in
        switch phase {
        case .active(let p): scrub = Int((p.x / plotWidth * CGFloat(capacity - 1)).rounded())
        case .ended: scrub = nil
        }
    }
    .overlay(alignment: .leading) {
        if let scrub { Rectangle().fill(.secondary).frame(width: 0.5).offset(x: plotWidth * CGFloat(scrub) / CGFloat(capacity - 1)) }
    }
// value column: Text(scrub.map { format(series.values[safe: $0]) } ?? liveValue)
```

## 7. Keeping it light

- **Move `Monitor` to `@Observable`, with one model per resource.** Today every tick updates the single `@Published var snapshot`, which re-renders the whole window. With per-resource models, a rail row only redraws when its own data changes, and the detail view only redraws for the visible pane.
- **Sample each source at its own rate:**

  | Data | How often |
  |---|---|
  | CPU, memory, network, disk rates, GPU, Neural Engine power | every tick |
  | Battery | every 10 s |
  | Disk capacity | every 60 s |
  | Hardware names and topology | once |
  | Processes | only on the Processes pane, and every third tick for Overview's top 5 |

- **Pause when the window is hidden.** Add `NSWindow.didChangeOcclusionStateNotification` to the existing minimize/hide checks, so sampling also stops when the window is fully covered.
- **History size:** 120 samples × about 30 series × `Float` is under 15 KB.
- **Drawing:** all charts are `Canvas` with no per-point views and no animation.
- **Accessibility:** give each focused chart `.accessibilityChartDescriptor` so it can be read out.
