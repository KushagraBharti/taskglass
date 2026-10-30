# Optimization run

Requested minimum: six continuous hours of active optimization. The user rejected scheduled continuation; taskglass-optimization-passes was deleted. Continuous work runs from 2026-10-30 05:53:30 UTC until 11:53:30 UTC in this chat. The earlier first-pass work is recorded below but does not shorten this timer.

Branch: perf/six-hour-optimization. Baseline: v0.1.1 / c743e4f. No new dependencies or global installations. User prioritizes implementation; keep builds and correctness checks targeted and brief.

## Current pass

In progress: reduce process-group allocation/hashing, remove temporary sampler collections, reduce retained native outline payloads and unnecessary rendering work. Original grouping and differential microbenchmark saved under ignored .build/optimization. Preserve rate baseline resets, PID birth guards, missing readings and shared ANE accounting.

Active time will be recorded at the end of each pass, separately from scheduled elapsed time. No six-hour completion claim yet.

## Pass 1 evidence and next work

Active work so far: 2026-10-30 05:04:28–05:19:10 UTC, approximately 14 minutes. This is a checkpoint, not completion of the six-hour request.

Implemented allocation reductions in grouping, sampler dictionaries/path decoding, history summaries, core topology/labels, native cell construction/format caching and retired outline payloads. Retained hardware baseline now contains only disk counters. No dependencies added. Main/accelerator accounting semantics preserved.

Grouping comparison: 2,000 deterministic mixed processes, alternating order, 100 iterations per ranking, same frozen input and equality assertion. CPU 1.422→1.163 ms; memory 1.797→1.623 ms; GPU 1.244→0.979 ms; ANE 1.529→1.346 ms. Baseline function and benchmark under .build/optimization. This measures grouping, not whole-app speed. The source used by both functions shares ProcessFamily, so icon lookup changes are not included.

Same SDK27/compiler/Osize stripped executable: baseline 999,648 bytes; initial candidate 982,976 bytes. Recheck after later changes. Brief existing ABI/sampling/lifecycle checks passed; real busy CPU fixture 99.93%. No new test framework or dependency.

Baseline/candidate bundles and an identical-toolchain baseline checkout/build are under .build/optimization. Baseline PID 83311, events baseline-events.log. UI automation can read/click AX but window reports covered; coordinate click returned noWindowsAvailable. Do not count these measurements as exposed-window performance. Baseline covered Memory run: 20.06 seconds, 0.701% one core, 99.31 MiB median footprint; external workload uncontrolled. Published dist/Taskglass.app remains untouched.

Next candidate: replace broad Combine ObservableObject invalidation with property-scoped Observation, keeping covered-window staging unobserved and observing only presented state. Verify native representables keep updating and preserve pause/wake/selection semantics. Then assess sampler cache churn, chart geometry/cache cost and repeated formatting/layout. Do not publish before completing the requested sustained optimization and final verification.

## Pass 1 continued: presentation and sorting

Replaced Combine-wide monitor notifications with native Observation. Private sampling/staging buffers are ignored; process count, thread count and record getters depend on the published process-sample date, preserving covered-window behavior. SwiftUI views use bindings only where needed; app ownership uses explicit SwiftUI.State storage to remain compatible with the SDK27 Command Line Tools' missing State macro plugin.

Moved observable sort/filter reads out of per-row closures, skipped the redundant filter for an unfiltered process list, and sorted the selected array in place. In an alternating 100-iteration, 2,000-row comparison on the same observable model, old/new arrangement algorithms produced identical order. CPU 3.464→2.568 ms; memory 4.528→3.528 ms; GPU 2.976→2.190 ms; PID 0.240→0.129 ms. This isolates the arrangement algorithm; it does not measure old Combine versus Observation or whole-app rendering.

Final local signed candidate executable is 982,144 bytes versus 999,648 for the identical-toolchain baseline, about 1.75% smaller. Candidate bundle: .build/optimization/candidate/Taskglass.app. Current source compiles successfully. Existing monitor lifecycle checks passed after the Observation migration. Native AX checks confirmed navigation, grouping toggle and helper expansion. Real exposed-window repaint smoothness remains unmeasured because the system reports the windows covered; do not present the following as a visible-window gain.

Covered Memory candidate run: 20.08 s, 0.593% of one core, 96.11 MiB median footprint, 113.3 MiB last footprint. Baseline was 0.701%, 99.31 MiB median. Short, sequential, uncontrolled samples with differing sample counts and late UI interaction are not strong evidence of an app-wide improvement. Raw logs stay ignored.

Both temporary comparison processes were closed. The original published dist/Taskglass.app was reopened normally. Development bundles remain scoped to .build; use full app paths with computer-use tools because their bundle identifiers are identical. No release or PR has been opened for this still-running optimization effort.

Active time accumulated in this first turn: approximately 23 minutes, from 05:04:28 to 05:27 UTC. Scheduled waiting is excluded. Remaining requested active work: approximately 5 hours 37 minutes. Update this ledger at each continuation; do not claim six hours completed based on wall time.

Next implementation priorities: inspect sampler dictionary/cache churn and repeated string/identity decoding, reduce repeated chart geometry and value formatting without changing gaps/scales, bound native outline reuse over extended process churn, and improve startup/retained memory. Obtain an exposed-window profile when available. Keep the focus on code, with brief targeted measurements and checks only. Preserve macOS14+ compatibility and avoid global installs. Complete the six-hour run before final PR/checks/merge/release.

## Continuous work correction

The user rejected scheduled continuation. Deleted taskglass-optimization-passes. Continuous six-hour work starts 2026-10-30T05:53:30.044580+00:00 and runs until 2026-10-30T11:53:30.044580+00:00. Deadline is tracked in .build/optimization/continuous-timer.json and checked between work passes. Do not create another continuation automation. Continue in this chat until the deadline; scheduled waiting no longer applies.

## Pass 2: retained process data and history summaries

Work resumed at 05:38:57 UTC; continuous deadline remains 11:53:30 UTC. Removed eagerly allocated helper rows from the native outline. Children are created on expansion and hold only a weak parent plus index. Root reuse is bounded to 32 items and clears old contents. AppKit explicitly retains returned items. Selection still follows PID and birth identity after reranking, and pane changes refresh columns even when the ranking is unchanged.

Collapsed-group churn fixture: a 100-member app moves through 600 positions. Retained item identities fell from 60,600 to 600; 600 updates took 34.379 to 15.384 ms. Old item/root/child instance sizes were 432/176/24 bytes before the subsequent metadata change. An actual NSOutlineView fixture passed 80 growth/shrink/rerank cycles, expansion/collapse, helper selection, regrouping and empty data.

Immutable process path/name/application metadata now shares one object across samples. ProcessRow stride fell from 224 to 168 bytes. Existing process names compare against the C buffer before decoding; non-app paths are resolved once. With the same already-optimized arrangement algorithm and frozen 2,000-row inputs, metadata sharing reduced CPU sorting from 2.534 to 1.679 ms, memory from 3.464 to 2.479, GPU from 2.199 to 1.521, PID from 0.128 to 0.075. These are isolated microbenchmarks, not whole-app measurements.

History peak and mean requests share a per-series summary until history changes. A representative repeated axis-request fixture took 0.008 to 0.003 ms at 31 points, 0.039 to 0.011 at 181, and 0.102 to 0.030 at 601. Equality, empty history and invalidation checks passed. This remains a small absolute saving.

Existing sampler/accounting/lifecycle checks passed after metadata changes. The full release build passed after all pass-2 changes. Temporary fixtures, baseline source and raw results remain under .build/optimization/pass2. No dependency or global installation. Next: reduce chart path generation and heatmap geometry work while preserving gaps, exact scales and appearance.

## Pass 3: chart paths and heatmap batching

Line and fill paths now share one calculation. Kept SwiftUI rendering after comparing a native-view experiment: its extra view/cache machinery did not materially improve the default short-history case. Five filled-series path calculations improved by about 40–41% at 31/181/601 points. Path commands and segment boundaries match, with coordinate differences below 0.0001 pt from SwiftUI's float conversion.

Offscreen NSHostingView update/layout/bitmap comparison at 2x: two-layer 31-point thumbnail 0.084 to 0.081 ms; 601-point thumbnail 0.317 to 0.181; 601-point 600x240 chart 1.055 to 0.941. These forced bitmap fixtures are not a visible-window smoothness measurement. The unused native-view experiment remains only under .build/optimization/pass3.

Core heatmaps calculate each sample's x/width once for all cores and batch rectangles into the eight load paths. A direct per-rectangle Core Graphics rewrite was slower and rejected. Batched geometry for 18 cores improved 31-point construction 0.018 to 0.016 ms, 181 points 0.082 to 0.066, 601 points 0.143 to 0.105. The heatmap raster is pixel-identical across all three history windows, gaps, missing cores and nonfinite values. Label font/attribute dictionaries are retained per heatmap view instead of recreated every draw. Full release build passed.

Continuous work is still underway. Next candidate: stop copying full process records into every grouped list; store ordered indices into the shared sample while preserving aggregation and selection.

## Pass 4: shared group membership

Process families now hold ordered indices into the shared sample. Single-process rows use a range and allocate no member array. Groups sort integers rather than full ProcessRow records. Family structs grow from 160 to 176 bytes, but each member index uses 8 bytes instead of another 168-byte record. Family equality compares only selected members; aggregation still follows the original sorted order, and coalition fallback titles preserve their original source-order choice.

Frozen 2,000-process comparison against the previous implementation: CPU grouping 1.028 to 0.921 ms, memory 1.636 to 1.422, GPU 0.898 to 0.759, ANE 1.141 to 0.955, disk 1.467 to 1.210. Grouped and ungrouped outputs compare equal for all columns. Existing sampling/accounting/lifecycle checks and the release build passed. Live sampling timings varied with system load, so those are not used as before/after claims.

## Pass 5: resolve sort keys before comparisons

Added a typed process sort key, resolved once at arrangement/grouping entry. Preserved string entry points and their fallback behavior. All 13 process columns compare equal to the previous ordering in both directions. Frozen 2,000-row process sorting improved memory 2.432 to 1.907 ms, disk 2.089 to 1.865, write 1.567 to 1.290 and CPU 1.764 to 1.686. PID/name were essentially unchanged. Grouping improved another 7–32% depending on the ranking. Current source compiled in the release build.

## Pass 6: native cell layout

Replaced per-cell Auto Layout constraints with direct frames for the fixed-height text, 16-point icon and 28-point meter. Matched NSTextField alignment insets so text edges remain identical. The six-column raster fixture matched pixel for pixel, including a grouped app title and truncated numeric text. Constructing/layout of 120 cells fell from 9.288 to 5.312 ms; value updates plus alternating column resizes fell from 3.284 to 0.687 ms. This measures cell layout, not overall application CPU.

Grouped title caching now compares the existing title/count directly, avoiding a concatenated cache-key string. Font/color/paragraph attributes are shared. Bar maxima use the first already-sorted row instead of scanning the entire list again. Release build passed after the layout and title-cache changes; final integration checks still remain.

## Pass 7: numeric coalition grouping

Coalition buckets now use their numeric IDs; names and string IDs are formatted once per group. ANE grouping in the frozen fixture fell from 0.697 to 0.492 ms, about 29%. Other rankings were unchanged within 0.2%. Grouped/ungrouped outputs still compare equal.

## Pass 8: borrow GPU identity data

GPU accounting stores birth identity alongside each tracked client instead of retaining a separate map of every accessible process. The sampler borrows its existing fresh process cache and lazily reads the C client buffer, removing the temporary client array and second process-identity dictionary. CPU timestamps and all client/PID/context/reset guards remain intact.

The scoped identity-map/accounting fixture with 2,000 known processes took 0.0369 to 0.0037 ms for 20 clients and 0.0388 to 0.0143 for 100; 500 clients were unchanged. These are small absolute savings and exclude driver scanning. Existing accounting/sampling/lifecycle checks passed. A real six-second Metal workload was attributed to its PID, peaking at 992.57 ms/s; complete sampler averaged 3.37 ms during that workload. Updated the optional accelerator build script for the shared-members source dependency. No global installs.

## Pass 9: size icon caches for their actual use

List icons now retain 32x32 bitmaps for their 16-point display. The inspector has a separate 16-entry cache of 80x80 images for its 40-point display. The maximum cached pixel payload is about 1.39 MiB instead of 6.25 MiB, excluding the two generic icons and object overhead. This is a capacity calculation, not a measured whole-app footprint claim. A second-chance eviction policy replaces one cold entry instead of clearing all 256 icons at the limit. A targeted native check confirmed cached image identity and both exact retina sizes; release build passed.

## Pass 10: refresh visible table rows once

The shared table updater resolves the visible columns once, then retrieves each row's record once before configuring its cells. Outline refreshes no longer ask AppKit for the same tree item for every column. Account-name completion refreshes only the User column. Release build passed; no app-wide timing claim for this structural reduction.

## Pass 11 investigation

Rejected fetching GPU owner and usage as separate registry properties. Alternating 100 live scans with 86 clients took 0.462 ms for the existing combined properties read and 0.599 ms for separate reads. Replacing sscanf with strtol saved only 0.008 ms and narrowed accepted owner formatting, so retained the existing parser. Neither experiment changed production code.

Investigating whether the already-collected per-core CPU counters can also provide the aggregate CPU reading. Apple's current XNU host.c and processor.c use the same processor_cpu_load_info helper. Check the supported older release implementation and failure/source-transition handling before making this change. Sources: https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/host.c and https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/processor.c . Continuous deadline remains 11:53:30 UTC; six hours have not elapsed.

## Pass 12: isolate live readings from window navigation

Moved resource rail rows, the live subtitle and process workspace into their own view bodies. The window root now reads stable chip/battery-presence properties, updated only when those facts change. Live CPU/history updates no longer rebuild NavigationSplitView and the toolbar. In an instrumented offscreen host, 30 changing samples evaluated the old ContentView root 31 times and the new root once. This proves the observation boundary; it is not an exposed-window smoothness claim. The release build passed.

The aggregate CPU-counter investigation remains deferred; no C counter semantics changed. Both current XNU and the older source files were inspected, but a source-transition fallback would add complexity for one small RPC saving. Prioritizing UI invalidation and retained memory instead.

## Pass 13: slow hardware and sensor presentation

Hardware mapping reuses cached static/slow fields and borrows the raw temperature tuple in place. Fast GPU/power/disk values are always replaced, including unavailable values; slow capacity/battery/fan/sensor fields refresh at their existing cadence. A deterministic C fixture matched old/new readings across availability changes and sensor-mode transitions. Mapping including the synthetic probe took 4.524 versus 4.344 microseconds, a small saving rather than an app-wide claim.

The sensor filter/table now has its own observation boundary and complete reading equality, including names and sources. Twenty fast CPU updates caused no sensor-section rebuild; changing the filter or sensor reading still updated it. Fan views compare only their four speed/maximum inputs and label width. Release build passed. Fixtures remain in .build/optimization/pass13. An initial synthetic fixture incorrectly changed slow storage data on fast reads; corrected it to match the real probe's cached behavior before comparing.

## Pass 14: process identity and single-member aggregation

Outline selection now compares numeric PID/birth identities, avoiding a formatted string for every helper searched during re-ranking. Group expansion IDs remain unchanged. Single-member families copy their existing readings without running aggregate/deduplication machinery. Frozen 2,000-row ungrouped ranking improved CPU 1.777 to 1.703 ms, memory 2.015 to 1.948, GPU 1.423 to 1.361 and disk 2.040 to 1.962. Grouped/ungrouped results match the earlier implementation. The existing 80-cycle native outline fixture passed growth/shrink, ranking, helper selection, expansion/collapse, regrouping and empty data. Release build passed.

## Pass 15: fixed-precision metric text

Replaced Foundation format-argument construction for live numeric readings with a small inline snprintf_l bridge and bounded Swift string initialization. It uses the C locale explicitly and retains the same printf rounding. Compared 180,144 cases against the prior Foundation output, including random Double bit patterns, signed zero, rounding boundaries, extreme values and C/German/French process locales; all matched. Buffers cover the full finite Double range at the supported 0–2 decimal places without truncation.

Representative percentage formatting fell from 0.599 to 0.121 microseconds. FormatStyle and shared NumberFormatter alternatives measured 0.361 and 0.302 microseconds respectively. These are formatter timings, not whole-app speedups. Existing ABI/accounting/sampling/lifecycle checks passed, as did the release build. Current stripped executable is 1,014,256 bytes versus the same-SDK starting baseline's 999,648; overall binary size is still slightly above baseline despite the execution/memory improvements, so no overall size-reduction claim yet. Apple documents NULL convenience-function locale as C: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/xlocale.3.html .

## Pass 16: inactive-page retention and native drawing inputs

Switching to Overview/Processes releases the unused resource-list sample; leaving Overview releases its old top-five list. Sampler/GPU/ANE resets now release dictionaries whose reserved capacity was never reused because each next sample builds a new dictionary. Removed the global sensor-row cache: the equatable sensor section already prevents fast-sample work, so derived rows now live only with their view. Heatmaps compare typed inputs directly rather than constructing a signature string. Fixed native palette/track colors are shared, and each heatmap reuses its eight exact alpha colors until its tint changes. Release build passed. No whole-app footprint claim for these lifetime reductions.

## Pass 17: search and CPU detail work

Name searches skip impossible PID matches and numeric searches try the cheap PID match first. A frozen 2,000-row filter kept identical results for text, numeric, empty and Unicode queries. Representative times: helper 1.290 to 1.155 ms, codex 1.251 to 1.117, missing text 1.315 to 1.160, numeric 15 2.098 to 1.994. A hyphen query remained essentially unchanged. CPU detail rendering reads core kinds once per body and computes group averages directly without temporary value arrays. Nice chart ceilings no longer allocate a mapped array. Release build passed.

## Pass 18: integrated rendering profile

Built the starting and current UI against the same SDK with an identical frozen 1,000-process fixture and 31-point history. Median forced update/layout times in one sequential run: Overview 12.795 to 11.501 ms, Processes 3.113 to 0.885, CPU 6.282 to 5.580, Memory 5.863 to 4.303, GPU 6.327 to 5.250, Neural Engine 6.389 to 4.677, Storage 6.537 to 4.666, Network 6.325 to 4.903, Battery 5.969 to 4.713, Temperatures 6.421 to 4.167. Not a live scrolling or whole-app CPU measurement. Data generation is excluded, but fixture metadata is recreated each update, unlike the optimized real sampler. Sequential external-load effects remain possible.

The initial combined update/layout/bitmap result made Neural Engine look unusually slow. A five-second stack sample showed ~80% of main-thread samples in the forced bitmap capture, mostly Core Graphics pixel compositing. Separated layout from bitmap work rather than optimizing the diagnostic's raster overhead. Raw fixtures and profiles are in .build/optimization/pass18. The published app's native AX window and screenshot remain available; raising it now refreshed its visible readings, but a fresh exposure-classified live profile is still pending.

## Pass 19: stable controls and Overview sections

Process/thread totals now publish only when their values change. Resource ranking controls, Overview process rows, the battery panel and footer have independent observation boundaries. An instrumented native fixture confirmed that 20 unrelated fast updates did not rebuild those sections, while process counts, grouping, battery readings and their own settings still updated. Overview rows reuse formatted metrics for visible and accessibility text. Release build passed. Continuous timer remains 05:53:30–11:53:30 UTC; no scheduled continuation exists.

## Pass 20: selected-process inspector

Identity, process metadata, executable details and quit controls now compare their own small inputs instead of rebuilding with activity readings. Account-name completion is observed by the User row. Four temporary history arrays became one pass deriving all chart scales with the same finite-value handling and floors. The warmed native fixture kept the static sections unchanged through 100 live updates and updated quit availability when the process disappeared; the initial account-name/layout settling caused one extra process-info evaluation, not a recurring rebuild. Update/layout median was 0.944 to 0.913 ms (small, load-sensitive). Release build passed; action-time PID/birth checks remain unchanged.

## Pass 21: link-time optimization

Release packaging now uses SwiftPM full LTO alongside -Osize. Current signed executable fell from about 1,031 KB to 894 KB; the same-SDK starting baseline was 1,000 KB. Reflection, unwind data and safe Swift semantics remain enabled. Keeping the combined LTO object inside .build fixes dsymutil's missing-temporary-object warning; the resulting dSYM has matching UUID and subprogram information. SwiftPM 6.0 already supports the option (https://raw.githubusercontent.com/swiftlang/swift-package-manager/swift-6.0-RELEASE/Sources/CoreCommands/Options.swift). CI on the older supported toolchain still must pass before release.

The LTO accounting/sampling check passed counter units, PID/client resets, coalition deduplication, CPU busy fixture and termination identity guards. Alternating inspector profiles showed 0.909/0.964 ms without LTO and 0.895/0.899 with it; no meaningful runtime regression observed in that limited fixture. Scoped LTO app launched and rendered live Overview/CPU correctly. Computer-use subsequently timed out even on inventory, while a 3-second Taskglass stack sample showed normal event-loop waiting and updates, not a hang. Full UI verification remains pending.

Rejected -Oz for C: executable grew 72 bytes, with no measured probe benefit. More aggressive symbol stripping saved only 480 bytes and was also rejected. Direct -lto compiler flags did not cooperate with SwiftPM's object map; its generated bitcode was moved into .build and the supported SwiftPM LTO option used instead. No global installs or published app replacement.

## Pass 22: numeric identities for individual outline rows

Individual process families keep PID/birth as numbers instead of formatting a fresh identity string each sample. Group expansion still uses stable app/coalition strings; pruning ignores individual rows. Single-process families initialize directly from their record. Equal-value individuals now use numeric PID/birth order; named groups retain their previous tie order. Readings, membership and identity text matched the reference, and the 80-cycle native outline fixture passed.

With realistic 16-digit birth values and full LTO, 2,000 ungrouped rows improved CPU 2.234 to 2.007 ms, memory 2.609 to 2.393, GPU 1.815 to 1.540, disk 2.553 to 2.378. At 750 grouped rows savings were smaller (1–5.5%); ANE grouping was roughly unchanged (+0.004 ms). The initial short synthetic birth IDs fit in Swift small strings and regressed 9–13%, so they did not represent the actual allocation being removed.

Rejected a narrower CPU tick-conversion arithmetic fast path. It matched wide random values but saved only ~2 ns per conversion, about 1.5 microseconds per ordinary sample. Retained the existing 128-bit conversion.

## Pass 23: heatmap rectangle batches

Merged touching or overlapping cells of the same shade and core row without crossing a geometric gap. The renderer now submits those rectangle batches to the current drawing context rather than allocating eight intermediate paths. Pixel output matched at 1x/2x for dense/narrow layouts, missing/nonfinite cores, restarts and gaps. Full geometry-plus-2x-raster timing for 601 samples/18 cores improved 3.754 to 3.191 ms with rapidly changing values, and 3.419 to 1.839 ms with mostly idle values. The latter reduced cells from 10,139 to 714. These are isolated renderer measurements, not whole-app CPU claims. Short-history improvements were smaller. Release build passed.

Direct CGContext.fill(rects) changed a few antialiased edge pixels; retained addRects + fillPath, which matched exactly.

## Pass 24 investigation

Batched line points reduced isolated path-construction time, but full chart update/layout/raster measurements were essentially unchanged and the longest layout case regressed slightly. Retained the current implementation instead of adding another temporary point buffer. Pixel output matched. Experiment stays in .build/optimization/pass24.

## Pass 25: compact numeric sorting

Numeric sorts now cache keys once, sort compact key/index records, then permute large process/family records once. At 750 rows, ordinary process CPU sorting improved 0.334 to 0.089 ms, memory 0.333 to 0.067, GPU 0.329 to 0.128 and disk 0.331 to 0.067. Grouped resource ranking improved CPU 0.235 to 0.124, memory 0.277 to 0.119, GPU 0.228 to 0.125 and disk 0.292 to 0.123. These are frozen fixtures with output consumed, not whole-app CPU measurements. Name/PID and small-result sorts retain their direct path.

All column orderings matched in both directions except an existing neural-memory defect exposed by extreme counters: map(Double.init) selected the bit-pattern initializer. Neural-memory sorting now compares exact UInt64 counters, distinguishing missing from zero and preserving low bits beyond Double precision. Added that specific regression case to the existing accelerator check. Sampling, accelerator accounting and monitor lifecycle checks passed; no CPU/GPU/ANE collection semantics changed.

## Pass 26: reuse localized name order

The main process table preserves the order of unchanged names, sorts new/renamed entries and merges them using the existing localized comparison. The cache retains only PIDs and names, releases on leaving the table or choosing another column, and resets when Locale.current changes. It does not retain old samples. A 120-generation fixture matched fresh sorting through additions, exits, renames, Unicode names, direction changes and explicit resets. Warm 750-row sorting improved about 1.99 to 0.046 ms; 2,000 rows 6.82 to 0.109 ms. First-use sorting still takes the ordinary path.

The accumulated numeric/name changes passed the native outline's 80-cycle selection/expansion/churn check and release compilation. Scoped executable is 926,800 bytes, still below the same-SDK starting baseline's 999,648, though larger than the earlier LTO-only build. Native inspection recovered, and the scoped app was refreshed without replacing the published app.

## Pass 27: share numeric-sort implementations

Combined columns that use the same key representation so key selection happens once per row and the compact sort implementation is shared. Full-LTO machine code shrank 2,480 bytes; aligned executable size changed only 16 bytes, so this is not a meaningful download-size gain. Alternating 750/2,000-row comparisons preserved ordering and showed no material regression; disk/read sorting improved another 4–7% in the fixture. Release build passed. The current native app also rendered the live dashboard and correctly sorted the main table by name.

## Pass 28: reuse core tile drawing objects

Core tiles keep their rounded paths, fixed label measurements and last rendered value/color. Resizing or topology changes rebuild the affected geometry; changing utilization refreshes the value. Exact raster comparison passed at 1x/2x, different widths/core counts, empty placeholders and nonfinite inputs. An 18-core draw improved 0.938 to 0.793 ms with mostly idle cores and 0.959 to 0.892 ms when every core changed. The small caches live with the view. Release build passed.
