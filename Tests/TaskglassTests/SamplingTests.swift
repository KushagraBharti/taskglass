import Foundation
import SystemProbe

@main struct SamplingTests {
    static func main() async {
        testAcceleratorAccounting()
        precondition(cpuPercent(next: 5_000_000_000, previous: 1_000_000_000, elapsed: 2) == 200)
        precondition(cpuPercent(next: 1, previous: 2, elapsed: 1) == nil)
        precondition(cpuPercent(next: 2, previous: 1, elapsed: 0) == nil)
        precondition(counterDelta(3, 9) == 0 && counterDelta(12, 9) == 3)
        precondition(cpuTickDelta(0x20, 0xfffffff0) == 48)
        precondition(cpuTickDelta(30, 0xffff_ffec + 0xffff_fff1) == 65)
        precondition(percent(.nan) == "—" && rate(.infinity) == "—" && rate(-1) == "—")
        func row(_ id: Int32, _ name: String, cpu: Double? = 0, memory: UInt64? = 10, read: Double? = 0, write: Double? = 0) -> ProcessRow {
            ProcessRow(id: id, parent: 1, path: nil, birth: 1, name: name, cpu: cpu, resident: 10, footprint: memory, threads: 1, uid: 501, readRate: read, writeRate: write)
        }
        let tied = [row(3, "worker"), row(1, "Worker"), row(2, "worker")]
        for key in ["name", "pid", "cpu", "memory", "resident", "threads", "read", "write", "disk", "uid"] {
            for ascending in [true, false] {
                for a in tied {
                    precondition(!processPrecedes(a, a, key: key, ascending: ascending))
                    for b in tied where a.id != b.id {
                        precondition(processPrecedes(a, b, key: key, ascending: ascending) != processPrecedes(b, a, key: key, ascending: ascending))
                    }
                }
            }
        }
        let ranking = [row(1, "CPU", cpu: 190, memory: 10, read: 10, write: 0),
                       row(2, "Memory", cpu: 5, memory: 100, read: 0, write: 100),
                       row(3, "Reader", cpu: 0, memory: 50, read: 80, write: 30),
                       row(4, "Denied", cpu: nil, memory: nil, read: nil, write: nil)]
        precondition(rankedProcesses(ranking, key: "cpu", limit: 2).map(\.id) == [1, 2])
        precondition(rankedProcesses(ranking, key: "memory", limit: 2).map(\.id) == [2, 3])
        precondition(rankedProcesses(ranking, key: "disk", limit: 2).map(\.id) == [3, 2])
        precondition(rankedProcesses(ranking, key: "read", limit: 1).first?.id == 3)
        precondition(rankedProcesses(ranking, key: "write", limit: 1).first?.id == 2)
        precondition(rankedProcesses(ranking, key: "memory", limit: 8).count == 3)
        precondition(rankedProcesses(ranking, key: "cpu", limit: 0).isEmpty)
        func appRow(_ id: Int32, path: String, cpu: Double, memory: UInt64) -> ProcessRow {
            ProcessRow(id: id, parent: 1, path: path, birth: 1, name: "Worker", cpu: cpu, resident: memory, footprint: memory, threads: 1, uid: 501, readRate: 1, writeRate: 2)
        }
        let appRows = [appRow(101, path: "/Applications/Browser.app/Contents/MacOS/Browser", cpu: 10, memory: 100),
                       appRow(102, path: "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", cpu: 20, memory: 200),
                       appRow(103, path: "/usr/bin/worker", cpu: 5, memory: 50)]
        let families = processFamilies(appRows, key: "memory", grouped: true)
        precondition(families.count == 2 && families[0].name == "Browser")
        precondition(families[0].members.map(\.id) == [102, 101])
        precondition(families[0].memory == 300 && families[0].cpu == 30)
        precondition(families[0].value("memory") == 300)
        precondition(families[0].read == 2 && families[0].write == 4)
        precondition(families.flatMap(\.members).count == appRows.count)
        precondition(processFamilies(appRows, key: "cpu", grouped: false).count == 3)
        precondition(processFamilies([], key: "cpu", grouped: true).isEmpty)
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
        precondition(resumed.processes.first { $0.id == getpid() }?.cpu != nil)
        // A single busy thread must not become >100% merely because system-only
        // reads happened between process reads.
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        busy.standardOutput = FileHandle.nullDevice
        try! busy.run()
        _ = await sampler.read()
        try? await Task.sleep(for: .milliseconds(150))
        _ = await sampler.read(includeProcesses: false)
        try? await Task.sleep(for: .milliseconds(150))
        let busySample = await sampler.read()
        let busyCPU = busySample.processes.first { $0.id == busy.processIdentifier }?.cpu
        busy.terminate(); busy.waitUntilExit()
        FileHandle.standardError.write(Data("Busy fixture CPU: \(busyCPU ?? -1)%\n".utf8))
        precondition(busyCPU != nil && busyCPU! > 30 && busyCPU! < 130)
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
        let groupingStart = ProcessInfo.processInfo.systemUptime
        var groupedCount = 0
        for _ in 0..<100 { groupedCount += processFamilies(second.processes, key: "memory", grouped: true).count }
        precondition(groupedCount > 0)
        print(String(format: "Process grouping: %.3f ms average over 100 builds", (ProcessInfo.processInfo.systemUptime - groupingStart) * 10))
        var combined = 0.0
        for _ in 0..<20 {
            let start = ProcessInfo.processInfo.systemUptime
            _ = await sampler.read(includeProcesses: true, includeHardware: true)
            combined += ProcessInfo.processInfo.systemUptime - start
        }
        print(String(format: "Combined hardware + process sampler: %.2f ms average over 20 reads", combined / 20 * 1000))

    }
}
