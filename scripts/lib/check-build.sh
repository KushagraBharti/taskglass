# Shared source lists and compiler options for the standalone native checks.
# Source from the repository root; this file does not run checks itself.
check_swift_flags=(
    -Osize -parse-as-library -I Sources/SystemProbe/include
    -module-cache-path .build/checks/module-cache
    -framework IOKit -framework CoreFoundation
)
check_probe_objects=(.build/checks/probe.o .build/checks/hardware.o .build/checks/accelerators.o)
check_sampling_sources=(
    Sources/Taskglass/Monitoring/Sampling.swift
    Sources/Taskglass/Monitoring/AcceleratorAccounting.swift
    Sources/Taskglass/Monitoring/Hardware.swift
    Sources/Taskglass/UI/MetricFormatting.swift
    Sources/Taskglass/Processes/IndexedSorting.swift
    Sources/Taskglass/Processes/ProcessOrdering.swift
    Sources/Taskglass/Processes/ProcessGrouping.swift
    Sources/Taskglass/Processes/ProcessMembers.swift
)

build_check_probe() {
    mkdir -p .build/checks
    local source
    for source in probe hardware accelerators; do
        xcrun clang -O2 -I Sources/SystemProbe/include -c "Sources/SystemProbe/$source.c" -o ".build/checks/$source.o"
    done
}
