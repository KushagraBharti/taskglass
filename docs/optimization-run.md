# Optimization run

Requested minimum: six hours of active optimization. Started 2026-10-30 05:04:28 UTC. Scheduled continuation every 30 minutes in this thread; waiting between runs is not active work. Automation: taskglass-optimization-passes.

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
