# Local resource measurements

Measured on the development Mac with a release build, macOS 27.0.1, 18 logical cores and 48 GB of physical memory. The process list contained approximately 690 accessible processes. The default refresh interval was two seconds. These are short development measurements, not a guarantee for other Macs or workloads.

| Run | Duration | CPU, one core | Median physical footprint | Peak physical footprint |
| --- | ---: | ---: | ---: | ---: |
| Initial full UI, Canvas graphs | 30 s | 0.109% | 168.95 MiB | 185.53 MiB |
| Visible row updates, Canvas graphs | 45 s | 0.060% | 153.12 MiB | 160.84 MiB |
| Visible row updates, vector graphs | 30 s | 0.061% | 70.75 MiB | 74.33 MiB |
| Paused, before vector change | 15 s | 0.001% | 86.61 MiB | 89.00 MiB |

The final vector graph run recorded 148.05 MiB median resident memory and 4.87 interrupt wakeups per second. Physical footprint and resident memory have different definitions. Reporting only one would hide part of the cost. The runs used fresh launches and different timings, and were not a controlled repeated experiment. The measurements suggest the graph change helped, but longer repeated runs are still needed.

The latest direct sampler test averaged 1.38 ms per read over 50 reads. It reads the process list, system and per-core CPU counters, memory, swap, pressure, and network counters. It does not time UI work.

The JSON files are raw output from `scripts/measure.py`. The final comparison covers the process view while visible and idle. Interaction, filtering, the Performance view, accessibility inspection, or changing the window size can increase costs. No claim of being the smallest possible macOS monitor has been verified.

A `leaks` diagnostic on an earlier build reported small framework/XPC cycles, but restricted process access prevented a complete analysis. It does not establish that the app is leak-free. Diagnostic files stay in the ignored build folder.

## Native utility refinement

A further pass removes the persistent dashboard sidebar, uses native toolbar navigation and Cocoa search, and updates existing visible table cells in place. Primary columns are visible by default; secondary columns are optional. The C process record is smaller, its next-counter dictionary reserves capacity, and Performance mode reads only system counters.

| Mode | Duration | CPU, one core | Median footprint | Median RSS |
| --- | ---: | ---: | ---: | ---: |
| Processes, fresh launch | 90 s | 0.052% | 50.41 MiB | 118.80 MiB |
| Performance, after UI interaction | 30 s | 0.038% | 84.69 MiB | 181.92 MiB |
| Paused, after UI interaction | 15 s | 0.001% | 82.53 MiB | 182.22 MiB |

The 90-second process run started at 50.39 MiB physical footprint and ended at 50.86 MiB, with a 53.47 MiB peak. It included approximately 700 accessible processes, two-second sampling, and the existing window size restored by macOS. The Performance and paused runs followed accessibility inspection, searching, opening the inspector and toggling columns in the same app session. Their memory numbers include those warm caches, so they do not isolate the cost of a view. No repeatability or universal minimum claim is made. JSON files are retained beside this report.

The test runner now also checks consistent ordering for tied values and case variants, and verifies that returning from system-only mode creates a fresh process CPU baseline. The full process sampler averaged 1.35–2.07 ms per read across the final test runs, with approximately 700 accessible processes.
