# Taskglass final UI verification (Claude Opus 5.5, 2026-10-29)

The previous pass's design work stayed as it was. This pass checked the current files against the requested correctness items. It made two small edits, both in `ResourceProcessTable.swift`.

## Checklist (verified in current source)

- [x] **Current and last-observed process state.** The inspector shows `selectedProcessRecord`. "Current" means `monitor.selection != nil`. On an old record the section reads "Last observed" and a notice says the values are the last ones seen. It doesn't claim the process exited. The parent-process link is hidden. Missing values show "—" rather than "Measuring". "Process unavailable" appears only when a PID is selected but was never observed.
- [x] **Destructive actions are disabled.** Quit and Force Quit are disabled for old records, other users' processes and Taskglass itself, and each case shows a reason. `Monitor.requestQuit` also checks `selection` and birth identity. The main table's context-menu Quit items are enabled only for the user's own processes, and they go through the same guarded `requestQuit`.
- [x] **Graph gap markers.** `TelemetryPath` breaks the line at `beginsSegment`, at missing readings and at gaps over 11 s. `CoreHeatmap` stops a cell at a following `beginsSegment` sample. Selected-process gaps (the NaN sample the monitor appends) also break the line.
- [x] **Byte units.** `PlotUnit.bytes` and `.rate` use the same 1024-based B/KB/MB/GB units as `bytes()`/`rate()`. The process-memory ceiling is a power of two (`binaryCeiling`, 16 MB floor), so axis labels read 64 MB, 512 MB and so on. `MetricSeries.processMemory` reads `Point.processMemory` (footprint bytes). `Point.memory` (system %) is not reinterpreted.
- [x] **Selected-process trends.** Compact CPU and memory plots in the inspector, with window = `min(historySeconds, 180)`. They use the shared plot (no Canvas, drawingGroup or animation). The CPU ceiling is 100% or whole cores above that.
- [x] **No double rank reset.** `ContentView.onChange(pane)` calls only `monitor.activatePane(pane)`. Nothing in the UI watches `resourceSort`. The Rank by picker and header clicks set `resourceSort` once, and the outline re-sorts in `update()`. `resourceLeaders` is treated as unsorted, and `processFamilies(...)` sorts it.
- [x] **Native outline expand → collapse → re-rank → expand.** Expansion and selection follow content identity (bundle path, or PID + birth), not slot position. Re-ranking collapses slots whose new content isn't expanded and expands slots whose new content is. `reconcileChildren` reloads a slot's children only when the outline's cached children differ from its current members. `reloadData` runs only on first display and when grouping changes. Visible cells are rewritten in place. Selection is restored after every update.
- [x] **Bounded caches.** Icons: 256 entries. User names: 256 entries, 32 pending lookups. Spare slots are capped at the largest count shown. **Fixed:** `expandedIDs` had no cap; it is now trimmed to current roots once it passes 64.
- [x] **No blocking work on the main thread.** Account names resolve with `getpwuid_r` on a utility queue. The UID shows until the name arrives. Only the visible User cells and the inspector refresh.
- [x] **Chip-power legend labels.** CPU, GPU and ANE names appear in both the one-line and the three-column fallback, with full spoken names for accessibility.
- [x] **Fans.** No "Read-only" header. Tooltips give each bar's scale.
- [x] **Minimum-width readability.** The window minimum is 1000×660 (parent-owned). Table columns have minimum widths, the name column absorbs resizing, and the table scrolls sideways if needed.
- [x] **Scope kept.** Every process stays in the scrollable native outline. All resource pages are present. Per-process GPU, ANE and network use is described as not measured. Battery time is labeled as time-to-empty only. The raw sensor table is lazy and equatable.
- [x] **Fixed:** a stale comment in `ResourceProcessTable` still said ContentView re-ranks when the ranking changes.

## Validation

- `./scripts/build-app.sh`: build complete (target macOS 14). Only the existing CLT linker search-path warnings.
- `./scripts/test.sh`: all suites PASS (busy CPU 98.9%, sampler 1.55 ms per read with 699 processes, grouping 1.19 ms, combined 1.76 ms, lifecycle covered/exposure/wake/cancellation).
- No app launch, screenshots or UI automation in this pass (not allowed). Live visual QA belongs to the parent.

## Remaining issues (concrete, not fixed)

1. Collapsing a group by hand while one of its members is selected lets NSOutlineView move or clear the selection, and `selectedID` follows it. The member's selection does not come back on re-expand. That only happens when re-ranking collapses a group. Minor; it was left as is to avoid fighting AppKit's selection behavior.
2. When a user expands a slot whose old children are still cached, at most one run-loop turn can show stale child rows before the deferred `reconcileChildren` corrects them. This is not seen live, only possible in theory.
3. Live checks still needed from the parent: numeric header alignment, the inactive-window contrast of axis labels and notes, and the chip-power legend at the narrowest overview width.
4. `Graphs.swift` is unused and left for the parent to remove.

## Parent release follow-up

- Removed unused Graphs.swift and corrected the selection comment to distinguish manual AppKit collapse from re-ranking.
- Limited cached process icons to 80×80 px bitmaps. Verified the generated icon in the running About panel and refreshed the Dock icon at launch.
- Built through the native SwiftPM engine to preserve the actual SDK version in the executable while targeting macOS 14.
- Inspected Overview, CPU, Memory, GPU, Neural Engine, Storage, Network, Battery and Temperatures on the native-engine build. Temperatures reported 130 named sensors, live CPU/GPU groups and both fans. Missing GPU/ANE/network attribution remained clearly labeled.
- Checked the native process table's numeric heading/value alignment, grouped app/helper expansion, collapse, a change to Disk writes ranking and re-expansion with the correct members. The resource list scrolls independently and includes all accessible processes.
- A live paused-navigation check caught a real empty-process-page bug after a system-only sample. The parent changed browsing, counts and parent lookup to use the retained complete process sample. A regression test and the rebuilt app confirm that paused browsing/search now retain the rows.
- Verified filtered search for Taskglass, its inspector, the generated icon, CPU/memory trends after resume, and disabled self-quit actions. Closing the last window ended the app on macOS 27; reopening resumed normal collection.
- Saved reviewed Overview and CPU screenshots from the running native-engine build. Raw inspector screenshots and logs remain ignored.

The automation connection intermittently timed out, including on app inventory with Taskglass closed. Thread traces showed continuing collection and an idle main run loop; later attempts recovered. These failures were not counted as successful UI checks. Full VoiceOver, every accessibility preference combination, long process-churn sessions and physical validation of other M-series/OS combinations remain outside the verified coverage.

A final inactive-window screenshot exposed dim native sidebar labels on the fixed black background. The parent assigned explicit light foreground colors to navigation labels and secondary readings; this is a contrast correction with no collection/layout change.
