import Foundation
import SystemProbe

func testAcceleratorAccounting() {
    func client(_ ns: UInt64, id: UInt64 = 1, pid: Int32 = 12, contexts: UInt32 = 1) -> GPUClientCounter {
        GPUClientCounter(id: id, pid: pid, nanoseconds: ns, contexts: contexts)
    }
    var gpu = GPUAccounting()
    let birth: [Int32: UInt64] = [12: 100]
    func update(_ clients: [GPUClientCounter], _ time: Double, births: [Int32: UInt64]? = nil, available: Bool = true) -> [Int32: Double] {
        gpu.update(clients, births: births ?? birth, now: time, available: available)
    }
    precondition(update([client(10)], 1).isEmpty)
    precondition(update([client(200_000_010)], 3)[12] == 100)
    precondition(update([client(200_000_010)], 4)[12] == 0)
    precondition(update([client(200_000_010), client(20, id: 2)], 5).isEmpty)
    precondition(update([client(300_000_010), client(100_000_020, id: 2)], 6)[12] == 200)
    precondition(update([client(300_000_010)], 7).isEmpty)
    precondition(update([client(310_000_010, contexts: 2)], 8).isEmpty)
    precondition(update([client(1, contexts: 2)], 9).isEmpty)
    precondition(update([client(2, contexts: 2)], 10, births: [12: 101]).isEmpty)
    precondition(update([client(3, contexts: 2)], 11, available: false).isEmpty)
    precondition(update([client(4, contexts: 2)], 12).isEmpty)
    precondition(update([client(5, contexts: 2)], 11).isEmpty)
    precondition(update([], .nan).isEmpty)
    precondition(update([client(6)], 13).isEmpty)
    var ane = ANEAccounting()
    precondition(ane.update([9: 100], now: 1).isEmpty)
    precondition(ane.update([9: 200_000_100, 10: 500], now: 3)[9] == 100)
    precondition(ane.update([9: 200_000_100], now: 4)[9] == 0)
    precondition(ane.update([9: 1], now: 5).isEmpty)
    ane.reset()
    precondition(ane.update([9: 100], now: 6).isEmpty)
    func row(_ pid: Int32, group: UInt64, app: String) -> ProcessRow {
        ProcessRow(id: pid, parent: 1, path: "/Applications/\(app).app/Contents/MacOS/worker", birth: 1, name: app,
                   cpu: 0, resident: 1, footprint: 1, threads: 1, uid: 501, readRate: 0, writeRate: 0,
                   gpuTime: 20, neuralMemory: 50, aneGroup: group, aneGroupTime: 12)
    }
    let rows = [row(1, group: 9, app: "One"), row(2, group: 9, app: "One"), row(3, group: 9, app: "Two"), row(4, group: 10, app: "One")]
    let groups = processFamilies(rows, key: "ane", grouped: false)
    precondition(groups.count == 2 && groups.reduce(0) { $0 + ($1.ane ?? 0) } == 24)
    precondition(groups.first { $0.id == "coalition:9" }?.name == "Shared: One, Two")
    precondition(groups.flatMap(\.members).count == 4)
    let apps = processFamilies(rows, key: "gpu", grouped: true)
    precondition(apps.first?.gpu == 60 && apps.first?.neuralMemory == 150)
    precondition(rankedProcesses(rows, key: "gpu", limit: 2).count == 2)
    precondition(acceleratorTime(nil) == "—" && acceleratorTime(.nan) == "—" && acceleratorTime(0) == "0.0 ms/s")
    print("PASS: accelerator units, stable clients, new/removed clients, context resets, PID reuse, failed scans, group deduplication and memory ownership")
}
