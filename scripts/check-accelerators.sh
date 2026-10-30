#!/bin/bash
# Optional real GPU/ANE tests. No downloaded models or installed dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun clang -O2 -I Sources/SystemProbe/include -c Sources/SystemProbe/probe.c -o .build/checks/probe.o
xcrun clang -O2 -I Sources/SystemProbe/include -c Sources/SystemProbe/hardware.c -o .build/checks/hardware.o
xcrun clang -O2 -I Sources/SystemProbe/include -c Sources/SystemProbe/accelerators.c -o .build/checks/accelerators.o
xcrun swiftc -Osize -parse-as-library -I Sources/SystemProbe/include -module-cache-path .build/checks/module-cache -framework IOKit -framework CoreFoundation Sources/Taskglass/Sampling.swift Sources/Taskglass/AcceleratorAccounting.swift Sources/Taskglass/Hardware.swift Sources/Taskglass/MetricFormatting.swift Sources/Taskglass/ProcessGrouping.swift Sources/Taskglass/ProcessMembers.swift Sources/Taskglass/ProcessOrdering.swift Tests/AcceleratorIntegration.swift .build/checks/{probe,hardware,accelerators}.o -o .build/checks/accelerator-integration
xcrun swiftc -O -module-cache-path .build/checks/module-cache -framework Metal Tests/GPULoad.swift -o .build/checks/gpu-load
.build/checks/accelerator-integration
if [ "${1:-}" = "--neural" ]; then
    python3 Tests/make-neural-fixture.py
    xcrun swiftc -O -I Sources/SystemProbe/include -module-cache-path .build/checks/module-cache -framework CoreML -framework IOKit -framework CoreFoundation Tests/NeuralLoad.swift .build/checks/accelerators.o -o .build/checks/neural-load
    .build/checks/accelerator-integration --neural
fi
