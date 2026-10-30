# Claude UI implementation pass

Model: `claude-opus-5-5`, as reported by the CLI response. The user explicitly requested this delegation.

I've rebuilt the Taskglass UI with the same layout. `./scripts/build-app.sh` builds cleanly and `./scripts/test.sh` passes. I haven't looked at it running, though: launching the app needed approval in this session, so I couldn't take screenshots, and everything below is checked in code only.

**The main change.** The overview is no longer a set of separate rounded cards with colored outlines. Each row is now one continuous band, with thin divider lines between its columns. The top two rows have 4 columns and the bottom two have 2, and the divider lines line up from row to row. The black background, the resource colors and every feature are kept; I didn't remove any measurement or add a fake one.

**Shared building blocks (two new files)**
- **`Theme.swift`:** one place for colors, spacing, type sizes and the shared formatters. CPU and Network used to share cyan; Network now has its own blue-violet.
- **`Components.swift`:** reusable pieces that replace the copy-pasted views:
  - the band itself, plus a clickable column with a hover highlight and native keyboard focus;
  - headers, value readouts (number large, unit smaller and grey), and a label/bar/value row used for fans, GPU engines, temperatures, battery and power;
  - level bars, a stacked composition bar, chart legends (solid or dashed to match the line), stat grids, tables, footnotes, and a "not measured" placeholder.

**Overview**
- The duplicate "Overview" heading is gone because the toolbar already shows it. In its place is one line about the hardware ("Apple M5 Pro with 18-core CPU, …") with memory pressure and thermal state on the right.
- The arrow icons and the colored outline around every module are gone. Color now appears only in the data and the small icons.
- **Charts:** all share one size, with faint gridlines at 0, 50% and 100%, a scale label, and a time axis matching the selected history window.
- **Temperatures:** the 0–120 °C ring gauges are replaced by CPU and GPU rows that each show a small history line and the current value.
- **Fans:** bars are scaled to each fan's own reported maximum.
- **Battery:** shows charge and net power.
- **Chip power:** a total bar split by CPU, GPU and Neural Engine (ANE), with a legend that shortens itself when the column is narrow.
- **Storage and network:** wider charts, with read/write (or receive/send) shown as solid and dashed lines.
- **Core map:** redrawn with clearer labels and values. The GPU renderer/tiler rows use the same row component as fans.
- **Top processes:** clicking a row opens Processes with that process selected and the inspector open.

**Resource pages**
- Every page now uses one shared layout: value and hardware line, a legend with live values, one chart with labeled scales and a time axis, then stats, sections and short footnotes.
- The CPU core history shows each core type in its own color and gained a time axis. It now draws in about 8 batches per refresh instead of one rectangle per cell.
- Memory has a composition bar, storage a capacity bar, and network a per-interface table that now includes totals. Temperatures shows fan rows plus a sensor table you can filter.
- On the Neural Engine page, if no power reading has ever been available, a dashed "not available" box replaces the chart. Power is still never shown as a usage percentage.

**Sidebar:** the small history charts sit in a subtle frame, and missing values are dimmed.

**Two behavior changes to look at:**
- **Charts now span the full selected window.** Before, a chart stretched its data across whatever history existed. Now every chart shares one time axis, so right after launch they fill in from the right instead of looking full.
- **Network headline:** the overview tile and the Network page now show receiving plus sending combined. Before, they showed receiving only.

**Toolchain:** `@SwiftUI.State` still triggers the missing macro plugin. The hover highlight therefore keeps its state in an explicit `SwiftUI.State` value, and no `@State` was added.

**Files:** I edited `OverviewDashboard.swift`, `PerformanceWorkspace.swift`, `TelemetryPlot.swift`, `ContentView.swift` and `ResourcePane.swift`, and added `Theme.swift` and `Components.swift`. I didn't commit. `README.md`, `DEVELOPMENT.md`, `scripts/check-hardware.sh` and `Tests/GPULoad.swift` changed during the session, but those came from the parallel hardware work, not me.

Things to check by eye once you run it:
- that the overview columns really line up;
- that the small scale label in the top-left of the overview charts reads well over the lines;
- how dense the hardware line at the top and the footer are at the minimum window width.
