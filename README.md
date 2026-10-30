# Taskglass

A native macOS task manager built with SwiftUI and AppKit. One window for processes and system performance, with direct kernel measurements and no third-party runtime.

## Build and run

Requires macOS 26+, Apple Silicon, and Swift 6.2 or newer with the macOS SDK. The local build uses the installed Apple command line tools. Full Xcode is not required.

```sh
./scripts/build-app.sh
open dist/Taskglass.app
```

The release app is unsigned. Signing, notarization, a public license choice, and distribution packaging are still needed before public release.

## Current features

- Native, reusable process table with sorting, search, app and user filters, selection, and keyboard navigation.
- Sampled CPU, physical memory footprint, resident memory, thread count, physical disk read/write rates, PID, and user ID. Extra columns are available by scrolling horizontally.
- Process inspector with parent PID, executable path, reveal in Finder, quit and force quit. Process signals are restricted to your user, exclude Taskglass itself, and verify the process start identity. Applications receive native quit requests. Actions require confirmation in the app.
- System CPU, per-core utilization, memory pressure, wired and compressed memory, cached files, swap use, physical interface network rates, thermal state, and uptime.
- Performance view with larger graphs. Up to 90 samples stay in memory.
- Refresh every 1, 2, or 5 seconds. Pause manually or automatically while hidden or minimized. Closing the window cancels sampling.
- Native system appearance, Liquid Glass search and toolbar controls, and native accessibility support for the process table.

## Measurement definitions

System CPU uses the difference between host CPU tick counters. It is normalized to 100% across all logical cores. Per-process CPU uses the difference between `proc_taskinfo` CPU time counters divided by the elapsed monotonic time. A process can exceed 100% by using multiple cores. A new process or resumed sampler needs two samples before displaying a CPU rate.

Memory uses `rusage_info_v2.ri_phys_footprint` where macOS grants access. Resident memory is displayed separately because it can count shared pages and excludes some compressed allocations. Neither column should be summed to estimate system usage. Used memory is internal pages minus purgeable pages, plus wired pages and the physical compressor. Cached files are external plus purgeable pages. Memory pressure comes from the kernel's pressure level, rather than an invented threshold based on free RAM.

Disk rates are differences between per-process physical disk I/O counters. Cached reads and writes need not touch disk, and these are not filesystem throughput measurements. Network rates use 64-bit route interface counters for active `en` interfaces; virtual interfaces are excluded to reduce double counting. Local traffic is included. Interface resets can produce a zero-rate sample.

Processes inaccessible through `libproc` are omitted and the UI explicitly says “accessible processes.” Individual unavailable counters show a dash. Short-lived processes can disappear between samples. CPU and I/O timing includes a small sampling skew across the process enumeration. Graphs use a fixed 0–100% scale.

GPU utilization, fan RPM, component temperatures, energy impact, and per-process network rates are not implemented. macOS does not offer all Windows Task Manager measurements through equivalent public APIs. The app does not install helpers or request administrator privileges.

## Verify and measure

```sh
./scripts/test.sh
pgrep -fl '/Taskglass.app/Contents/MacOS/Taskglass'
python3 scripts/measure.py <PID> --seconds 30
```

The test runner uses the installed compiler, without XCTest or package downloads. It checks CPU interval math, multi-core values, counter resets, live memory, process enumeration, identity continuity, and baseline resets. It also times 50 direct sampler reads. `measure.py` reads the app's CPU, footprint, RSS, and interrupt wakeups through libproc. Run it with the release app visible and idle, then again while paused. Results vary by process count, display scale, system version, and UI interaction.

## Project footprint

No third-party dependencies, daemons, login items, package manager installs, or app telemetry. No persisted monitoring history. Swift, AppKit, SwiftUI, Mach, libproc, and system networking headers come from Apple's installed SDK.

All generated build output, shared SwiftPM caches, and compiler module caches are directed under `.build/`. The app bundle stays in `dist/`. Both directories are ignored by Git. Screenshots are ignored because they can show local process names. macOS itself can create launch records and crash reports in its normal system locations.

```sh
rm -rf .build dist
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for implementation decisions and follow-up work.
