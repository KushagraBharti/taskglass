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
