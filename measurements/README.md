# Resource measurements

Fresh release builds on an Apple M5 Pro with 18 CPU cores, 20 GPU cores, 48 GiB RAM and macOS 27.0.1. Both versions used Swift 6.4, SDK 27, a 1180 × 780 point window and the default two-second refresh. Each run had 60 seconds of warmup followed by 60 seconds of measurement, with no agent UI actions during collection. The current build adds full link-time optimization.

| View | Version | CPU, one core | Median physical footprint | Peak footprint |
| --- | --- | ---: | ---: | ---: |
| Overview | v0.1.1 baseline | 2.434% | 65.77 MiB | 67.41 MiB |
| Overview | v0.1.2 candidate | 1.696% | 58.97 MiB | 63.69 MiB |
| CPU details | v0.1.1 baseline | 2.562% | 162.22 MiB | 183.75 MiB |
| CPU details | v0.1.2 candidate | 1.373% | 163.97 MiB | 188.45 MiB |

In these local comparisons, Overview used about 30% less CPU and 10% less physical memory. CPU details used about 46% less CPU, with **no memory improvement**. Its graphics memory still fluctuates and needs further work.

CPU is a percentage of one core, so 100% means one busy core. Physical footprint and RSS are different measures. The JSON files preserve warmup, steady interval, RSS, first/last footprint, wakeups, source revisions and window exposure. All steady intervals were fully exposed except 0.02 seconds in the candidate Overview run.

These are single short runs, not repeated controlled trials or long-term memory plateaus. Other workloads and user activity were uncontrolled. UI accessibility traversal can increase transient allocations. Do not compare covered-window figures with a visible dashboard, or infer performance on every Mac from this machine. CI builds use a different toolchain and are not the binaries measured here.

## Size and retained data

The local v0.1.2 stripped executable is 928,832 bytes, about 7% smaller than the same-SDK baseline's 999,648 bytes. The app bundle is 1,292,325 bytes, ZIP 779,458 bytes, and DMG 1,194,011 bytes. Published artifact sizes can differ with the CI toolchain. Smaller files do not by themselves prove lower running memory.

List icons are capped at 256 × 32 × 32 pixels and inspector icons at 16 × 80 × 80 pixels. Their combined pixel budget is about 1.4 MiB, down from the previous 6.3 MiB bound, excluding AppKit's own caches. System history retains at most 601 samples; selected-process history retains at most 181. There is no monitoring daemon or third-party runtime.

## Reproduce

Build with `./scripts/build-app.sh`. Launch with `--profile-events`, redirect stderr to an ignored file under `.build`, then use `python3 scripts/measure.py PID --seconds 60 --events PATH`. Keep window size, page, history length, refresh cadence and exposure consistent. Warm up before measuring and report peak as well as median footprint. The profiling variants used a separate memory-only preferences domain and selected their own startup page.

Earlier exploratory measurements and detailed pass notes remain in Git history. The old profiler treated Mach CPU ticks as nanoseconds and understated CPU by 125/3 on this machine. Those historical CPU values are invalid. The current profiler converts with `mach_timebase_info`; the real busy-thread correctness fixture measures about 100%.

Only reviewed aggregates are committed. Raw process names, executable paths, UI captures and profiling logs are not published.
