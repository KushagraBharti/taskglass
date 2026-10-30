# Claude thorough UI implementation pass

Model: `claude-opus-5-5`, confirmed by the CLI response.

# Thorough UI pass: implemented changes and open issues

Scope: UI files only. These were edited: Theme, Components, ContentView, OverviewDashboard, PerformanceWorkspace, ResourcePane, ResourceProcesses, ResourceProcessTable, ProcessTable and TelemetryPlot. New UI-only files: TableKit.swift and ProcessInspector.swift. No parent-owned files were edited.
Verification: `./scripts/build-app.sh` builds with no Swift warnings. `./scripts/test.sh` passes. The app was **not launched or visually inspected** by me; everything below needs the parent's live screenshots.

## Round 1: system and hierarchy
- [x] **Axis scales.** Byte-rate charts use power-of-two ceilings from a 1 MB/s floor, so labels read 1 MB/s, 512 KB/s, 2 MB/s… instead of "1.9 MB/s". Axis labels drop trailing ".0" (100 mW, 2 W, 1.5 W). The Overview, the panes and the sidebar share `Monitor.rateCeiling`.
- [x] **Temperature plots** start at a 20 °C floor (top 100 °C, or 120 °C if a reading exceeds 96 °C). Lines now show variation instead of sitting flat at 0–120. The floor is stated in the tooltip and gutter.
- [x] **Plot states.** A dashed start-of-sampling marker appears while history is shorter than the window. Empty plots read "Collecting samples" (fewer than 2 points) or "Not reported". Detailed time axes read "Paused" instead of "Now" while paused. Lines break at sample gaps over 11 s instead of joining across unmeasured time.
- [x] **Overview header** is now "18-core CPU, 20-core GPU, 48 GB unified memory". The chip is already the toolbar subtitle. Installed memory is shown as a round "48 GB".
- [x] **Overview footer** is "Live, every 2 s" / "Charts show the last 3 minutes". The 10 s refresh note moved to a tooltip.
- [x] **Overview resource captions** step down instead of truncating: `FittingText` shortens "6 Super + 12 Performance cores" to "18 cores", and "Power draw, not utilization" to "Power, not usage".
- [x] **Environment band.** Every row uses the same 64 pt label column. Temperature rows use a bare inline trend (no empty-looking box). The battery's second row reads "Discharging 30.05 W" or "Charging…" instead of a signed value next to an empty track. Fans are a button into Temperatures. Chip power states its scope in the header ("CPU + GPU + ANE"), and the tooltip says it is not system/wall power.
- [x] **Fans.** One shared `FanList` (Overview and Temperatures) shows only fans the SMC reports ("Fan" when there is one). The bar spans each fan's own reported maximum.
- [x] **Cores band.** Removed the "Fill shows current load" prose (now a tooltip). GPU engines say "Whole GPU, not per core". Renderer/tiler labels align with the environment band.
- [x] **Top processes** show app icons, from the sampler's cached `ProcessRow.application`.
- [x] **Pane scaffold.** Secondary figures sit inside the chart band under a full-bleed keyline (`StatStrip`). It is one even row, or a 2/3-column grid when narrow, so stats no longer float as a disjoint card. Long footnotes moved to an ⓘ popover beside the subtitle.
- [x] **Visible definitions kept:** ANE "Power draw, not utilization"; GPU "aggregate counters"; memory "GPU allocated: Not separate VRAM"; Temperatures "CPU sensor group average"; group overlap caption under every resource table; chip power scope; stat notes "Experimental", "CPU sensor group", "Interface counters".
- [x] **Stats deduplicated against chart keys.**
  - CPU: User, Idle, Power, Temperature, Thermal.
  - Storage: IOPS, plus window peaks for read and write.
  - Network: window peaks, plus interface counter totals.
  - Neural Engine: average and peak instead of "Now".
  - Temperatures: hottest sensor, named.
- [x] **CPU core history** uses a 0–100% opacity ramp legend that shares `CoreHeatmap.alpha(level:)` with the drawing, plus a shared `TimeAxis`. A missing per-core value draws in tertiary.
- [x] **Sensors.** Segmented filter offering only groups that have readings ("Other" for PMU / other). `SensorTable` is `Equatable` with a lazy row stack, so it re-renders only when a reading changes.
- [x] **Resource process section.**
  - Compact controls: a "Group by app" checkbox, a "Rank by" menu and an ⓘ.
  - Unattributed resources share one line: "GPU use isn't attributed to individual processes. This list is ranked by CPU." The same applies to Neural Engine use, network traffic, battery draw and temperature.
  - "Reading processes" empty state.
  - The table height fits whole rows.

## Round 2: craft and interaction
- [x] **Shared native table kit** (`TableKit.swift`), used by both tables.
  - One `ProcessCell` with icon, label and relative bar; shared fonts, row height, grid, header tooltips and help strings.
  - App icon cache; user-name cache; Return-key table subclasses.
  - In-place visible refresh. Each label/colour/bar is set only when it changes, and bars redraw only at a 0.5% step change.
- [x] **Resource outline.**
  - **Positional slots:** re-ranking rewrites on-screen cells in place. Process start/exit is applied as tail insert/remove. A reload happens only when the outline's known structure would mismatch (an expanded group changed rank or member count, or the key/grouping changed).
  - **Identity preserved:** expansion and selection follow application/process identity. An expansion verifies its child rows against the slot (`reconcileChildren`) to defeat stale outline caches.
  - **Rows and header:**
    - Group rows show a blank PID, not "—", because nothing is missing.
    - Group titles are medium weight, followed by a smaller secondary "44 processes" (omitted for single-process apps).
    - Helper rows are icon-less under their app.
    - The ranked column header is semibold with no sort chevron, so it no longer sits offset from its values.
  - Double-click/Return inspects. Context menu: Show in Processes, Show in Finder, Expand/Collapse, Copy Name.
  - Name column absorbs width; numeric columns keep minimums; the table scrolls sideways below that.
- [x] **Main Processes table.**
  - Same cell system and icons. The CPU/Memory relative bar shows while sorted descending by that column.
  - User column shows the account name, left-aligned.
  - Header tooltips define CPU % per core, footprint vs denied, and disk vs file cache.
  - Context menu: Inspect, Show in Finder, Copy Name, Quit…, Force Quit… (disabled when not owned).
  - Selection made elsewhere scrolls into view once. Return opens the inspector.
  - Initial sort descriptors are set before the delegate, so no publish happens during view creation.
- [x] **Processes page.** Empty states: "Reading processes", "No processes match “x”" with Clear Search, "No applications" with Show All Processes. The subtitle reads "12 of 694 processes" while filtered, and threads only for the full list (previously it mixed filtered rows with all threads). The filter icon fills while a scope filter is active.
- [x] **Inspector** (`ProcessInspector.swift`).
  - Icon + name + PID header; Activity / Process / Executable sections; values selectable.
  - The parent is a link that selects it; the user is shown as name (uid); the app comes from cached identity.
  - Quit / Force Quit… (destructive) are pinned at the bottom, with the reason when disabled.
  - "Process has ended" vs "No process selected".
- [x] **About these measurements** is now a sectioned, scrollable sheet (CPU, Memory, Disk and network, GPU/ANE/power, Sensors, Sampling and privacy).
- [x] **Sidebar.** The network value and micro plot now both show receive + send (new `MetricSeries.networkTotal`); before, the value was download-only next to a download plot while every other surface showed the total. Temperature micro plot uses the shared temperature scale.
- [x] **Accessibility.** `CellHeader` contains rather than combines, so header links stay reachable. Toolbar buttons have labels. Tables are labelled "Processes". Plot labels include the scale and "no data". Data rows read "column value" pairs.
- [x] **Parent feedback applied:** no reliance on `resourceLeaders` order; no `reloadData` for pure re-sorts; sensor rows not rebuilt per sample; no animations, Canvas or drawingGroup; double `rankResources` removed from header-click sorting.

## Round 3: self-review fixes found while rereading
- `CellHeader` accessibility combine swallowed links: fixed.
- The ANE info popover repeated the attribution notice: removed.
- "Heat isn't attributed…" reworded to "Temperature".
- `iops` is now a shared formatter (whole numbers per second).

## Open issues to check against live screenshots
1. `Metrics.processTableHeight` assumes a 28 pt header and 30 pt rows (28 + intercell 2). The inset style's padding may leave a partial row; adjust the constant once seen.
2. The ranked-header emphasis uses the header cell's own font size via an attributed title. Verify it matches system header metrics and stays in place after a header click.
3. Numeric cells use −4 pt trailing padding to approximate header text inset. Confirm alignment in both table styles (inset vs full-width).
4. The overview chip-power legend still drops names at default width (values with coloured swatches only). The header scope text is the mitigation; a better layout may be needed.
5. `StatStrip` / `LegendFlow` rely on `ViewThatFits`. Confirm the fallback grid at the 1000 pt minimum window and with the inspector open.
6. The slot outline's stale-cache handling (`reconcileChildren`) relies on `NSOutlineView.numberOfChildren(ofItem:)` / `child(_:ofItem:)` reflecting the outline's own cache. Verify live: expand, collapse, re-rank, re-expand.
7. Column reordering is now disabled in both tables, to keep the name column first for autoresizing. This is a small behaviour change from before.
8. `Graphs.swift` (HistoryGraph/Sparkline) is unused dead code; left in place.
9. Pane-level ⓘ popovers and the sensor segmented control are untested for keyboard focus order.
10. UI cost was not measured here; the parent's profiling decides whether the in-place outline path and equatable sensor table are measurable wins.
