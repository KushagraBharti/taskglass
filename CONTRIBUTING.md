# Contributing

Taskglass uses SwiftUI, reusable AppKit tables, and a small native C probe.
There are no third-party package dependencies.

Build with a current Apple silicon Mac and Apple's Swift/macOS SDK:

```sh
./scripts/build-app.sh
./scripts/test.sh
./scripts/check-hardware.sh
```

Build output and compiler caches stay in `.build/`; the app and release archives
stay in `dist/`. No system package or privileged helper is installed. The app
uses its normal macOS preferences domain for view settings; tests use memory.

Keep changes focused. Preserve these invariants:

- System CPU is normalized to 100%; process CPU uses 100% per core.
- Convert Mach CPU ticks using the machine's timebase.
- PID/start identity must survive sorting and be checked before termination.
- Missing measurements stay distinct from a real zero.
- Power is not utilization. GPU engine counters overlap. Process footprints
  can share memory and cannot be summed into a unique system total.
- All histories and caches remain bounded. Sampling happens off the main thread.
- Tables reuse visible cells. Avoid periodic animations or unnecessary redraws.
- Hardware sources must fail safely on other chips, OS versions and permissions.

Use the project's existing tests for changes to sampling or lifecycle behavior.
For performance changes, compare release builds and report physical footprint,
RSS, one-core CPU percentage, refresh interval, exposure and test duration.
Don't compare a covered window with an actively rendered one.

The optional `./scripts/check-hardware.sh --gpu-workload` runs a bounded six-second
Metal workload. It is a development fixture, not part of the app. Raw screenshots
and process-level diagnostics should remain in ignored paths.

By submitting a contribution you agree it may be distributed under the MIT license.
