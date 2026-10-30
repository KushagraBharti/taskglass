#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun clang -O2 -I Sources/SystemProbe/include -c Sources/SystemProbe/probe.c -o .build/checks/probe.o
xcrun swiftc -module-cache-path .build/checks/module-cache -O -parse-as-library -I Sources/SystemProbe/include Sources/Taskglass/Sampling.swift Sources/Taskglass/ProcessOrdering.swift Tests/TaskglassTests/SamplingTests.swift .build/checks/probe.o -o .build/checks/sampling-tests
.build/checks/sampling-tests
