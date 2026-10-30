#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun clang -O2 -I Sources/SystemProbe/include Sources/SystemProbe/hardware.c Tests/Fixtures/HardwareCheck.c -framework IOKit -framework CoreFoundation -o .build/checks/hardware-check
.build/checks/hardware-check
if [ "${1:-}" = "--gpu-workload" ]; then
    xcrun swiftc -O -module-cache-path .build/module-cache -framework Metal Tests/Fixtures/GPULoad.swift -o .build/checks/gpu-load
    rm -f .build/checks/gpu-load-ready
    .build/checks/gpu-load &
    workload_pid=$!
    trap 'kill "$workload_pid" 2>/dev/null || true' EXIT
    for attempt in {1..100}; do
        if [ -f .build/checks/gpu-load-ready ]; then break; fi
        sleep 0.1
    done
    .build/checks/hardware-check
    wait "$workload_pid"
    trap - EXIT
fi
