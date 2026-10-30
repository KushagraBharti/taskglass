import Foundation

// UI-independent declaration of the routing contract; the production monitor,
// sampler, ranking and history code below are compiled unchanged.
enum ResourcePane: String, Hashable { case overview, processes, cpu, memory, gpu, neural, storage, network, battery, temperatures }

@main struct MonitorLifecycleTests {
    @MainActor static func main() async {
        let preferences = AppPreferences()
        let settings = Monitor(preferences: preferences)
        settings.activatePane(.memory); settings.resourceSort = "cpu"
        settings.activatePane(.cpu); settings.resourceSort = "write"
        settings.activatePane(.memory)
        precondition(settings.resourceSort == "cpu")
        settings.interval = 5; settings.historySeconds = 180; settings.resourceGrouped = false
        let restored = Monitor(preferences: preferences)
        precondition(restored.interval == 5 && restored.historySeconds == 180 && !restored.resourceGrouped)
        let monitor = Monitor()
        monitor.selected = getpid()
        monitor.interval = 0.05
        monitor.setWindowExposed(false)
        let sampling = Task { await monitor.run() }
        try? await Task.sleep(for: .seconds(1))
        precondition(monitor.history.isEmpty && !monitor.snapshot.valid)
        precondition(monitor.resourceSampleDate == nil)
        monitor.setWindowExposed(true)
        precondition(monitor.snapshot.valid && monitor.history.count >= 2)
        precondition(monitor.resourceSampleDate != nil)
        precondition(monitor.processHistory.count >= 2 && monitor.processHistory.last?.processMemory != nil)
        precondition(monitor.selectedProcessRecord?.id == getpid())
        let count = monitor.history.count
        let lastTime = monitor.history.last!.time
        monitor.setWindowExposed(false)
        try? await Task.sleep(for: .milliseconds(200))
        precondition(monitor.history.count == count && monitor.history.last!.time == lastTime)
        monitor.setWindowExposed(true)
        precondition(monitor.history.count > count && monitor.history.last!.time > lastTime)
        precondition(monitor.history.count <= 601)
        let beforeWake = monitor.history.last!.time
        monitor.setWindowExposed(false)
        monitor.systemDidWake()
        try? await Task.sleep(for: .milliseconds(250))
        monitor.setWindowExposed(true)
        precondition(monitor.history.contains { $0.time > beforeWake && $0.cpu.isNaN })
        // Resource/overview ticks can omit processes; paused navigation must
        // still use the last complete process sample for browsing and counts.
        for _ in 0..<100 {
            if monitor.snapshot.processes.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(monitor.snapshot.processes.isEmpty)
        monitor.paused = true
        monitor.activatePane(.processes)
        precondition(monitor.rows.count == monitor.accessibleProcessCount && !monitor.rows.isEmpty)
        monitor.selected = nil
        precondition(monitor.processHistory.isEmpty && monitor.selectedProcessRecord == nil)
        sampling.cancel(); await sampling.value
        print("PASS: covered windows keep sampling without publishing, exposure flushes retained history and process data, wake resets rates, paused process browsing retains rows, cancellation exits")
    }
}
