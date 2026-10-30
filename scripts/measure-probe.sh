#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
xcrun clang -O2 -I Sources/SystemProbe/include Tests/ProbeTiming.c Sources/SystemProbe/hardware.c -framework IOKit -framework CoreFoundation -o .build/checks/probe-timing
.build/checks/probe-timing
