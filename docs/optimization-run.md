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
