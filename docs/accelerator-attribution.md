# Accelerator attribution

Taskglass reads local kernel/driver counters without root, a helper, Metal/Core ML in the app, or a third-party runtime. It does not estimate accelerator usage from CPU load or allocated memory.

## GPU time

One bounded IOKit traversal reads `AGXAccelerator` user clients, their registry IDs, `IOUserClientCreator` PIDs and `AppUsage.accumulatedGPUTime`. Driver time is already nanoseconds. Taskglass differences live client counters and reports **milliseconds of observed GPU execution per second**, not percent of GPU capacity. Overlapping contexts can exceed 1,000 ms/s. Short-lived clients that exit between samples may be missed. Driver attribution may charge compositing to WindowServer rather than the originating app.

Rates require the same registry client identities, context counts and process birth at both ends. New/removed clients, counter regressions, process replacement and failed scans leave a gap. An app row sums its observed processes. A dash is not zero or proof an app never uses the GPU.

## Neural Engine time and memory

On recognized **macOS 27.x** layouts, `PROC_PIDCOALITIONINFO` maps processes to OS resource coalitions. `coalition_info_resource_usage` exposes `ane_mach_time`. Taskglass accepts only 360/400-byte responses with the expected seven QoS classes and converts Mach ticks to nanoseconds using `mach_timebase_info` with a 128-bit intermediate. Other layouts/versions/symbol failures remain unavailable.

The time counter belongs to the **whole OS resource group**, which may contain several processes or apps. The ANE-time ranking always groups by this ID and counts the shared counter once. Expanding shows current members; children say `group` rather than repeating the total as individual-PID usage. Shared groups are labeled explicitly when multiple app bundles are identified. Membership does not prove which member submitted a particular inference, and work executed on a process's behalf may be charged to another group. ANE time is not a percentage of physical NPU occupancy.

Per-process Neural Engine memory uses `proc_pid_rusage` v6's `ri_neural_footprint` at the verified macOS 27 byte offset 368. An oversized aligned buffer makes the same decoder buildable with older SDKs. Only the recognized runtime version enables the field; ordinary physical footprint and disk counters fall back to v2 if v6 is rejected. Memory can remain allocated while the NPU is idle, so it is a separate ranking. On macOS 14–26 both ANE time and Neural Engine memory remain unavailable rather than decoding reserved fields. The Neural Engine page retains experimental power where supported independently.

## Cost and lifecycle

GPU clients are read only while the GPU pane, GPU ranking, or a visible main-table GPU column/inspector needs them. Coalition membership/time is read only while the Neural Engine pane or ANE ranking needs it. Each distinct coalition is queried once per sample using a temporary bounded hash table. All work runs on the existing sampling actor and cadence. Hiding/minimizing/pausing resets baselines; covered windows retain history without redrawing. There are no additional timers or subprocesses in the app.

## Validation and limits

`./scripts/test.sh` exercises unit conversion, PID reuse, client churn, counter resets, missing data, unsupported response layouts, group deduplication, process sorting and lifecycle behavior. CI builds and runs those tests on macOS 15 and 26 ARM runners, targeting macOS 14. Hosted runners cannot substitute for physical M1–M5 testing.

`./scripts/check-accelerators.sh --neural` builds two optional six-second fixtures under `.build/checks`: a Metal kernel and a deterministic Core ML convolution model generated with Python's standard library. Core ML is configured for CPU and Neural Engine; the test requires the actual kernel ANE counter to rise, so silent CPU fallback cannot pass on a supported system. Fixtures are not app dependencies. The ANE integration command requires macOS 27's counter ABI; use the default GPU-only command on earlier systems.

Locally verified on an M5 Pro, macOS 27.0.1: Metal fixture attributed to its PID at a peak 960.5 ms/s; Core ML fixture attributed to its OS group at a peak 66.9 ms/s and 245,760 bytes of Neural Engine memory. Twelve full process-sampler reads averaged 4.09 ms for GPU and 4.84 ms for ANE during those workloads. These are local observations, not guarantees for other machines. Private APIs can change; additional physical Macs are welcome.

## Sources

- [Apple XNU coalition counters](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/mach/coalition.h)
- [Apple XNU process coalition interface](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/sys/proc_info_private.h)
- Apple macOS 27 SDK `sys/resource.h`, `rusage_info_v6`; field offset checked at compile time when building with that SDK.
- [Apple Core ML model schemas](https://github.com/apple/coremltools/tree/main/mlmodel/format) for the authored test fixture.
- [Mac Performance Monitor GPU reader](https://github.com/Zesty0wl/mac-performance-monitor/blob/28aab067f0d75806875371d116b9885c7059e062/Sources/MacPerfMonitorCore/System/GPUProcessReader.swift) and [ANE reader](https://github.com/Zesty0wl/mac-performance-monitor/blob/28aab067f0d75806875371d116b9885c7059e062/Sources/MacPerfMonitorCore/Sampling/ANEActivityReader.swift), MIT. The defensive ANE response-layout check is adapted from that project. See THIRD_PARTY_NOTICES.md.
