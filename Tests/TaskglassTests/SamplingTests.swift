import Foundation
import SystemProbe

@main struct SamplingTests {
    static func main() async {
        precondition(cpuPercent(next: 5_000_000_000, previous: 1_000_000_000, elapsed: 2) == 200)
        precondition(cpuPercent(next: 1, previous: 2, elapsed: 1) == nil)
        precondition(cpuPercent(next: 2, previous: 1, elapsed: 0) == nil)
        precondition(counterDelta(3, 9) == 0 && counterDelta(12, 9) == 3)
        func row(_ id: Int32, _ name: String) -> ProcessRow {
            ProcessRow(id: id, parent: 1, path: nil, birth: 1, name: name, cpu: 0, resident: 10, footprint: 10, threads: 1, uid: 501, readRate: 0, writeRate: 0)
        }
        let tied = [row(3, "worker"), row(1, "Worker"), row(2, "worker")]
        for key in ["name", "pid", "cpu", "memory", "resident", "threads", "read", "write", "uid"] {
            for ascending in [true, false] {
                for a in tied {
                    precondition(!processPrecedes(a, a, key: key, ascending: ascending))
                    for b in tied where a.id != b.id {
                        precondition(processPrecedes(a, b, key: key, ascending: ascending) != processPrecedes(b, a, key: key, ascending: ascending))
                    }
                }
            }
        }
        let sampler = Sampler()
        let first = await sampler.read()
        precondition(first.cpu == nil && first.total > 0 && first.valid && first.used <= first.total)
        precondition(first.processes.contains { $0.id == getpid() })
        try? await Task.sleep(for: .milliseconds(250))
        let second = await sampler.read()
        precondition(second.cpu != nil && second.cpu! >= 0 && second.cpu! <= 100)
        precondition(second.cores.count == ProcessInfo.processInfo.activeProcessorCount && second.cores.allSatisfy { $0 >= 0 && $0 <= 100 })
        precondition(Set(second.processes.map(\.id)).count == second.processes.count)
        precondition(second.processes.first { $0.id == getpid() }?.cpu != nil)
        await sampler.reset()
        let reset = await sampler.read()
        precondition(reset.cpu == nil && reset.processes.allSatisfy { $0.cpu == nil })
        let systemOnly = await sampler.read(includeProcesses: false)
        precondition(systemOnly.processes.isEmpty && systemOnly.valid)
        let resumed = await sampler.read()
        precondition(resumed.processes.allSatisfy { $0.cpu == nil })
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: "/bin/sleep")
        fixture.arguments = ["30"]
        try! fixture.run()
        let fixtureSnapshot = await sampler.read()
        let fixtureRow = fixtureSnapshot.processes.first { $0.id == fixture.processIdentifier }!
        precondition(tg_terminate(fixtureRow.id, fixtureRow.birth + 1, 0) == 0)
        precondition(fixture.isRunning)
        precondition(tg_terminate(fixtureRow.id, fixtureRow.birth, 0) == 1)
        fixture.waitUntilExit()
        print("PASS: strict sorting, CPU intervals, multi-core percentages, reset guards, live memory, process enumeration, identity continuity, per-core range, resume baseline, system-only sampling, process termination identity guard")
        var total = 0.0
        for _ in 0..<50 { let start = ProcessInfo.processInfo.systemUptime; _ = await sampler.read(); total += ProcessInfo.processInfo.systemUptime - start }
        print(String(format: "Direct sampler: %.2f ms average over 50 reads (%d accessible processes)", total / 50 * 1000, second.processes.count))
    }
}
