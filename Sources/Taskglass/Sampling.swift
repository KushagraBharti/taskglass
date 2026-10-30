import Foundation
import SystemProbe

struct ProcessRow: Identifiable, Sendable, Equatable {
    let id: Int32
    let parent: Int32
    let path: String?
    let birth: UInt64
    let name: String
    let cpu: Double?
    let resident: UInt64
    let footprint: UInt64?
    let threads: UInt32
    let uid: UInt32
    let readRate: Double?
    let writeRate: Double?
}
struct Point: Sendable { let cpu: Double; let memory: Double }
struct Snapshot: Sendable {
    var processes: [ProcessRow] = []
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var used: UInt64 = 0, wired: UInt64 = 0, compressed: UInt64 = 0, cached: UInt64 = 0, swap: UInt64 = 0
    var cpu: Double? = nil, systemCPU: Double = 0, download: Double? = nil, upload: Double? = nil
    var cores: [Double] = []
    var pressure = 0
    var valid = false
    var date = Date()
}
func counterDelta(_ next: UInt64, _ previous: UInt64) -> UInt64 { next >= previous ? next - previous : 0 }
func cpuPercent(next: UInt64, previous: UInt64, elapsed: Double) -> Double? {
    guard elapsed > 0, next >= previous else { return nil }
    return Double(next - previous) / (elapsed * 1_000_000_000) * 100
}
actor Sampler {
    private var previous: TGSystem?
    private var time: TimeInterval?
    private var processes: [Int32: (birth: UInt64, cpu: UInt64, read: UInt64, write: UInt64, name: String, path: String?, shortName: String, ioValid: Bool)] = [:]
    func reset() { previous = nil; time = nil; processes.removeAll(keepingCapacity: true) }
    func read() -> Snapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let raw = tg_system()
        let elapsed = time.map { now - $0 } ?? 0
        var result = Snapshot()
        result.total = raw.total; result.used = raw.used; result.wired = raw.wired
        result.compressed = raw.compressed; result.cached = raw.cached; result.swap = raw.swap
        result.pressure = Int(raw.pressure); result.valid = raw.valid != 0
        if let old = previous, elapsed > 0 {
            let user = counterDelta(raw.cpu_user, old.cpu_user), system = counterDelta(raw.cpu_system, old.cpu_system), idle = counterDelta(raw.cpu_idle, old.cpu_idle)
            let total = Double(user + system + idle)
            if total > 0 && raw.cpu_valid != 0 && old.cpu_valid != 0 { result.cpu = Double(user + system) / total * 100; result.systemCPU = Double(system) / total * 100 }
            if raw.net_valid != 0 && old.net_valid != 0 && raw.net_identity == old.net_identity {
                result.download = Double(counterDelta(raw.received, old.received)) / elapsed
                result.upload = Double(counterDelta(raw.sent, old.sent)) / elapsed
            }
            var nextRaw = raw, oldRaw = old
            withUnsafePointer(to: &nextRaw.core_busy) { nb in
                withUnsafePointer(to: &nextRaw.core_total) { nt in
                    withUnsafePointer(to: &oldRaw.core_busy) { ob in
                        withUnsafePointer(to: &oldRaw.core_total) { ot in
                            nb.withMemoryRebound(to: UInt64.self, capacity: 128) { busy in
                                nt.withMemoryRebound(to: UInt64.self, capacity: 128) { total in
                                    ob.withMemoryRebound(to: UInt64.self, capacity: 128) { oldBusy in
                                        ot.withMemoryRebound(to: UInt64.self, capacity: 128) { oldTotal in
                                            result.cores = (0..<Int(min(raw.cores, old.cores))).map { i in
                                                let delta = counterDelta(total[i], oldTotal[i])
                                                return delta > 0 ? min(100, Double(counterDelta(busy[i], oldBusy[i])) / Double(delta) * 100) : 0
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        var pointer: UnsafeMutablePointer<TGProcess>?
        let count = tg_processes(&pointer)
        var next: [Int32: (birth: UInt64, cpu: UInt64, read: UInt64, write: UInt64, name: String, path: String?, shortName: String, ioValid: Bool)] = [:]
        if let pointer {
            defer { tg_free(pointer) }
            result.processes.reserveCapacity(Int(count))
            for index in 0..<Int(count) {
                var p = pointer[index]
                let shortName = withUnsafePointer(to: &p.name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
                let old = processes[p.pid]
                let path: String?
                let name: String
                if let old, old.birth == p.birth && old.shortName == shortName { path = old.path; name = old.name }
                else {
                    var buffer = [CChar](repeating: 0, count: 4096)
                    path = tg_path(p.pid, &buffer, 4096) > 0 ? String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
                    name = path?.split(separator: "/").last.map(String.init) ?? shortName
                }
                let cpu = old?.birth == p.birth ? cpuPercent(next: p.cpu, previous: old!.cpu, elapsed: elapsed) : nil
                result.processes.append(ProcessRow(id: p.pid, parent: p.parent, path: path, birth: p.birth, name: name, cpu: cpu, resident: p.resident, footprint: p.footprint_valid != 0 ? p.footprint : nil, threads: p.threads, uid: p.uid, readRate: old?.birth == p.birth && old?.ioValid == true && elapsed > 0 && p.footprint_valid != 0 ? Double(counterDelta(p.disk_read, old!.read)) / elapsed : nil, writeRate: old?.birth == p.birth && old?.ioValid == true && elapsed > 0 && p.footprint_valid != 0 ? Double(counterDelta(p.disk_write, old!.write)) / elapsed : nil))
                next[p.pid] = (p.birth, p.cpu, p.disk_read, p.disk_write, name, path, shortName, p.footprint_valid != 0)
            }
        }
        previous = raw; time = now; processes = next
        return result
    }
}

func bytes(_ value: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var amount = Double(value), index = 0
    while amount >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
    return String(format: amount >= 100 || index == 0 ? "%.0f %@" : "%.1f %@", amount, units[index])
}
func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "—" }
func rate(_ value: Double?) -> String { value.map { bytes(UInt64(max(0, $0))) + "/s" } ?? "—" }
