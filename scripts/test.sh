#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun clang -O2 -I Sources/SystemProbe/include Tests/AcceleratorABI.c -framework IOKit -framework CoreFoundation -o .build/checks/accelerator-abi
.build/checks/accelerator-abi
xcrun clang -O2 -I Sources/SystemProbe/include -c Sources/SystemProbe/probe.c -o .build/checks/probe.o
xcrun clang -O2 -I Sources/SystemProbe/include -c Sources/SystemProbe/hardware.c -o .build/checks/hardware.o
xcrun clang -O2 -I Sources/SystemProbe/include -c Sources/SystemProbe/accelerators.c -o .build/checks/accelerators.o
xcrun swiftc -framework IOKit -framework CoreFoundation -module-cache-path .build/checks/module-cache -Osize -parse-as-library -I Sources/SystemProbe/include Sources/Taskglass/Sampling.swift Sources/Taskglass/AcceleratorAccounting.swift Sources/Taskglass/Hardware.swift Sources/Taskglass/ProcessOrdering.swift Sources/Taskglass/ProcessGrouping.swift Tests/TaskglassTests/AcceleratorTests.swift Tests/TaskglassTests/SamplingTests.swift .build/checks/probe.o .build/checks/hardware.o .build/checks/accelerators.o -o .build/checks/sampling-tests
.build/checks/sampling-tests
xcrun swiftc -framework IOKit -framework CoreFoundation -module-cache-path .build/checks/module-cache -Osize -parse-as-library -I Sources/SystemProbe/include Sources/Taskglass/Sampling.swift Sources/Taskglass/AcceleratorAccounting.swift Sources/Taskglass/Hardware.swift Sources/Taskglass/ProcessOrdering.swift Sources/Taskglass/ProcessGrouping.swift Sources/Taskglass/MetricSeries.swift Sources/Taskglass/HistoryStatistics.swift Sources/Taskglass/Monitor.swift Sources/Taskglass/ProfileEvents.swift Sources/Taskglass/AppPreferences.swift Tests/TaskglassTests/MonitorLifecycleTests.swift .build/checks/probe.o .build/checks/hardware.o .build/checks/accelerators.o -o .build/checks/lifecycle-tests
.build/checks/lifecycle-tests
