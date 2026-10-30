# Resource measurements

Development machine: Apple M5 Pro, macOS27.0.1, 18 CPU cores, 20 GPU cores, 48 GiB unified memory, roughly700 accessible processes. Release build, default2-second refresh. These are short local measurements, not guarantees or a claim of being the lightest monitor.

## CPU clock correction

Earlier profiler results treated Mach CPU ticks as nanoseconds. That understated CPU usage on this machine by125/3. Those JSON files now explicitly mark CPU as invalid and retain it only as `cpu_percent_one_core_unconverted`; historical memory and wakeup fields are unaffected. Earlier UI comparisons cannot establish the final app's CPU cost.

The app's process CPU boundary and scripts/measure.py now apply mach_timebase_info. A real busy single-thread fixture measured about99.9% after the fix. The test requires30–130%, so the previous2.4% result cannot pass unnoticed.

## Graphical monitor, before the latest refinement

| Run | Duration | CPU, one core | Median physical footprint | Peak footprint | Median RSS | Interrupt wakeups/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Rich UI with navigation/interaction during run | 60s | 9.712% | 79.24MiB | 182.22MiB | 139.92MiB | 71.74 |
| Full native grouped process table, quiet after launch | 45s | 4.244% | 98.83MiB | 100.13MiB | 190.42MiB | 2.53 |

The second run began with Memory selected and included no agent UI actions during collection. User interaction and external workload were not controlled. Footprint rose from82.14 to99.08MiB during warm-up; this short run does not establish a long-term plateau. The mixed run is not an idle baseline. Physical footprint and RSS are different memory-accounting measures; both are reported.

These numbers precede the latest backend optimizations and Claude's thorough UI refinement. The release candidates below are recorded separately rather than reusing older results as claims about newer code.

## Backend work

A grouping benchmark over100 builds with roughly700 live records fell from2.533ms to1.347ms after caching app identities, storing group totals once and avoiding single-member sorts. The warm combined process/hardware sampler is about2.7–3.0ms per read; this excludes UI work and is not a whole-app CPU measurement.

The IOReport startup comparison runs three separate native-probe processes per variant. One variant first enumerates every system channel; the other builds only the three recognized CLPC descriptors. Raw runs and method are in probe-init-comparison.json. This excludes the app UI, and OS caches/workloads are not controlled.

No history or individual process names are saved in committed profiling data. Raw UI sampling diagnostics and screenshot files stay under ignored paths. Build output and compiler caches remain inside the project.

The current native probe benchmark (`./scripts/measure-probe.sh`) records summary startup, fast reads, summary metadata reads and full raw sensor reads separately in native-probe-summary-timing.json. It excludes UI and process enumeration. Comparing its paths does not prove an equivalent whole-app speedup.

## Release candidates

All CPU values below use the corrected Mach timebase and represent one core. Exposure is captured by opt-in local event diagnostics. User activity, other workloads and OS caches are uncontrolled. Short runs do not establish long-term memory behavior.

| Run | Exposure | CPU, one core | Median physical footprint | Peak footprint |
| --- | --- | ---: | ---: | ---: |
| Final UI interaction, 90 s | 54.71 s exposed, 35.60 s covered; CPU/GPU/Overview navigation | 4.121% | 214.28 MiB | 331.70 MiB |
| CPU page, 60 s | 60.24 s exposed | 7.831% | 219.69 MiB | 244.41 MiB |
| Fresh Overview, 90 s | 6.36 s exposed, 83.97 s covered | 0.582% | 65.16 MiB | 172.45 MiB |

The mixed run precedes bounded process-icon thumbnails. The CPU and fresh Overview runs include that change. These three runs precede the Swift 6.4 build-engine SDK-metadata correction, and are not the final release binary. The initial 60 s mixed run has unknown exposure because Python's monotonic epoch differed from Foundation systemUptime; its JSON states that limitation. The profiler now uses CLOCK_UPTIME_RAW for matching event timestamps.

A covered window continues sampling but defers SwiftUI publication. Its low CPU cannot be presented as visible-window performance. UI automation, especially accessibility traversal and screenshots, can inflate transient memory. Visible CPU-page usage remains a cost to improve, not evidence of a universally lightest app.

## Distribution size

The local native-engine release executable is 949,136 bytes after stripping, compared with 2,657,432 bytes for the same unstripped executable. The app bundle occupies about 1.26 MiB including its 355 KB ICNS and licenses. Local ZIP is about 721 KiB and DMG about 1.1 MB. CI toolchain/container differences can change exact release sizes; published assets are the authority.

Stripping changes download/disk size, not a proven runtime speedup. Swift uses safe -Osize optimization; sampler and lifecycle suites also compile with -Osize. No unchecked optimization is enabled. Each cached process icon is limited to 80×80 pixels; 256 entries bound retained icon pixel data to about 6.3 MiB, excluding AppKit's own caches.

## Native-engine candidate

`release-native-overview-60s.json` records the native-engine candidate before the paused-navigation fix. It was covered for the entire 60.23 s: 0.558% of one CPU core, 86.08 MiB median physical footprint and 86.42 MiB peak. It recorded 30 samples. This is covered-window behavior, not a visible dashboard benchmark. The subsequent fix changes retained process browsing/counts, not the Overview collection cadence.

The final `-Osize` regression run passed with a 99.87% busy-thread fixture, 2.47 ms direct sampler average over 50 reads with 718 accessible processes, 1.403 ms grouping average over 100 builds, and 3.04 ms combined warm hardware/process reads. These timings exclude UI work. Lifecycle checks include paused process browsing as well as covered publication, exposure, wake-baseline reset and cancellation.

## Final visible dashboard

`release-overview-final-60s.json` records the final local source at commit 973790c, after the paused-navigation fix and tools-version compatibility change, before the final sidebar-only contrast correction. The JSON includes the source digest, binary digest and compiler configuration. The window was exposed for all 60.22 s, with Overview selected and 29 sample events. There were no agent UI actions during collection; other workloads and user activity were uncontrolled.

CPU averaged 2.36% of one core. Median physical footprint was 161.45 MiB, peak 179.47 MiB, and the run ended at 91.53 MiB. Median RSS was 164.47 MiB; interrupt wakeups averaged 2.74/s. The decline during this short run illustrates why a single launch screenshot is not a steady-state memory claim. These are local SDK 27 measurements, not measurements of the CI-built SDK 26 download, and do not establish being the lightest monitor.

## Accelerator attribution

A 30.13-second local run of the v0.1.1 GPU page, fully exposed with 15 samples at the default two-second cadence, measured 2.023% of one core, 114.20 MiB median physical footprint and 131.45 MiB peak. See v0.1.1-gpu-30s.json for the exact source revision, SDK, exposure and RSS. Footprint ended at 126.17 MiB, so this short run does not establish a long-term plateau or a controlled speedup over earlier versions.

Real six-second Metal and Core ML fixtures verified accelerator attribution on the development M5 Pro. Full sampler reads with the accelerator path enabled averaged roughly 4–6 ms while those workloads ran. These times include process enumeration but exclude UI drawing. The fixtures and compatibility limits are documented in [accelerator attribution](../docs/accelerator-attribution.md).
