#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/check-build.sh
build_check_probe

xcrun clang -O2 -I Sources/SystemProbe/include Tests/AcceleratorABI.c \
    -framework IOKit -framework CoreFoundation -o .build/checks/accelerator-abi
.build/checks/accelerator-abi

xcrun swiftc "${check_swift_flags[@]}" "${check_sampling_sources[@]}" \
    Tests/TaskglassTests/AcceleratorTests.swift Tests/TaskglassTests/SamplingTests.swift \
    "${check_probe_objects[@]}" -o .build/checks/sampling-tests
.build/checks/sampling-tests

xcrun swiftc "${check_swift_flags[@]}" "${check_sampling_sources[@]}" \
    Sources/Taskglass/Charts/MetricSeries.swift Sources/Taskglass/Charts/HistoryStatistics.swift \
    Sources/Taskglass/Processes/ProcessNameOrder.swift Sources/Taskglass/Monitoring/Monitor.swift \
    Sources/Taskglass/Monitoring/ProfileEvents.swift Sources/Taskglass/App/AppPreferences.swift \
    Tests/TaskglassTests/MonitorLifecycleTests.swift "${check_probe_objects[@]}" -o .build/checks/lifecycle-tests
.build/checks/lifecycle-tests
