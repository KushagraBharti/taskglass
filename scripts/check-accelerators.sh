#!/bin/bash
# Optional real GPU/ANE tests. No downloaded models or installed dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/check-build.sh
build_check_probe
xcrun swiftc "${check_swift_flags[@]}" "${check_sampling_sources[@]}" \
    Tests/TaskglassTests/AcceleratorIntegration.swift "${check_probe_objects[@]}" -o .build/checks/accelerator-integration
xcrun swiftc -O -module-cache-path .build/checks/module-cache -framework Metal Tests/Fixtures/GPULoad.swift -o .build/checks/gpu-load
.build/checks/accelerator-integration
if [ "${1:-}" = "--neural" ]; then
    python3 Tests/Fixtures/make-neural-fixture.py
    xcrun swiftc -O -I Sources/SystemProbe/include -module-cache-path .build/checks/module-cache -framework CoreML -framework IOKit -framework CoreFoundation Tests/Fixtures/NeuralLoad.swift .build/checks/accelerators.o -o .build/checks/neural-load
    .build/checks/accelerator-integration --neural
fi
