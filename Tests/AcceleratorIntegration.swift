import Foundation
import SystemProbe

@main struct AcceleratorIntegration {
    static func main() async throws {
        let neural = CommandLine.arguments.contains("--neural")
        let executable = neural ? ".build/checks/neural-load" : ".build/checks/gpu-load"
        let ready = neural ? ".build/checks/neural-load-ready" : ".build/checks/gpu-load-ready"
        try? FileManager.default.removeItem(atPath: ready)
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: executable)
        try fixture.run()
        defer { if fixture.isRunning { fixture.terminate(); fixture.waitUntilExit() } }
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: ready) || !fixture.isRunning { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(fixture.isRunning && FileManager.default.fileExists(atPath: ready), "Workload failed to start")
        let sampler = Sampler()
        var peak = 0.0, memory: UInt64 = 0, group: UInt64?
        var elapsed = 0.0
        let reads = 12
        for _ in 0..<reads {
            let start = ProcessInfo.processInfo.systemUptime
            let sample = await sampler.read(includeHardware: false, includeGPU: !neural, includeANE: neural)
            elapsed += ProcessInfo.processInfo.systemUptime - start
            if let row = sample.processes.first(where: { $0.id == fixture.processIdentifier }) {
                peak = max(peak, (neural ? row.aneGroupTime : row.gpuTime) ?? 0)
                memory = max(memory, row.neuralMemory ?? 0)
                group = row.aneGroup
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        fixture.waitUntilExit()
        precondition(fixture.terminationStatus == 0 && peak > 0, "Real accelerator work was not attributed to the workload PID/group")
        print("PASS: \(neural ? "ANE group" : "GPU process") PID \(fixture.processIdentifier), peak \(peak) ms/s, group \(group.map(String.init) ?? "n/a"), neural bytes \(memory), complete sampler average \(elapsed / Double(reads) * 1000) ms")
    }
}
