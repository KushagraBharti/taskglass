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
    var application: ProcessApplication? = nil
}
struct Point: Sendable {
    let cpu: Double
    let memory: Double
    var time: Double = ProcessInfo.processInfo.systemUptime
    var processMemory: Double? = nil
    var beginsSegment = false
    var renderer: Double? = nil
    var tiler: Double? = nil
    var systemCPU: Double? = nil
    var cores: [Double] = []
    var temperature: Double? = nil
    var gpuTemperature: Double? = nil
    var batteryTemperature: Double? = nil
    var batteryPercent: Double? = nil
    var gpu: Double? = nil
    var aneWatts: Double? = nil
    var diskRead: Double? = nil
    var diskWrite: Double? = nil
    var download: Double? = nil
    var upload: Double? = nil
    var cpuWatts: Double? = nil
    var gpuWatts: Double? = nil
}
struct NetworkInterface: Identifiable, Sendable {
    let id: String
    let received: UInt64
    let sent: UInt64
    let download: Double?
    let upload: Double?
}
struct Snapshot: Sendable {
    var beginsInterval = false
    var sampleDuration: Double?
    var interfaces: [NetworkInterface] = []
    var received: UInt64 = 0, sent: UInt64 = 0
    var hardware = HardwareMetrics()
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
// Mach CPU tick fields are 32-bit. Wrapping subtraction also works for sums
// of their states, provided an interval contains fewer than 2^32 ticks.
func cpuTickDelta(_ next: UInt64, _ previous: UInt64) -> UInt64 {
    UInt64(UInt32(truncatingIfNeeded: next) &- UInt32(truncatingIfNeeded: previous))
}
func cpuPercent(next: UInt64, previous: UInt64, elapsed: Double) -> Double? {
    guard elapsed > 0, next >= previous else { return nil }
    return Double(next - previous) / (elapsed * 1_000_000_000) * 100
}
actor Sampler {
    private let hardware = HardwareReader()
    private var hardwareActive = false
    private var interfaceCounters: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var processTime: Double?
    private var previous: TGSystem?
    private var time: TimeInterval?
    private var processes: [Int32: (birth: UInt64, cpu: UInt64, read: UInt64, write: UInt64, name: String, path: String?, shortName: String, ioValid: Bool, application: ProcessApplication?)] = [:]
    func reset() { hardware.reset(); hardwareActive = false; processTime = nil; previous = nil; time = nil; processes.removeAll(keepingCapacity: true) }
    func read(includeProcesses: Bool = true, includeHardware: Bool? = nil, includeSensorDetails: Bool = true) -> Snapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let raw = tg_system()
        let elapsed = time.map { now - $0 } ?? 0
        var result = Snapshot()
        result.beginsInterval = previous == nil
        result.sampleDuration = elapsed > 0 ? elapsed : nil
        if includeHardware ?? !includeProcesses {
            result.hardware = hardware.read(now: now, includeSensorDetails: includeSensorDetails); hardwareActive = true
        } else {
            if hardwareActive { hardware.reset(); hardwareActive = false }
            result.hardware = hardware.cached
        }
        result.total = raw.total; result.used = raw.used; result.wired = raw.wired
        result.compressed = raw.compressed; result.cached = raw.cached; result.swap = raw.swap
        result.received = raw.received; result.sent = raw.sent
        var network = raw.interfaces
        var nextCounters: [String: (rx: UInt64, tx: UInt64)] = [:]
        withUnsafePointer(to: &network) { ptr in
            ptr.withMemoryRebound(to: TGInterface.self, capacity: 16) { list in
                for index in 0..<Int(raw.interface_count) {
                    let row = list[index], name = cText(row.name), old = interfaceCounters[name]
                    let down = elapsed > 0 && old != nil ? Double(counterDelta(row.received, old!.rx)) / elapsed : nil
                    let up = elapsed > 0 && old != nil ? Double(counterDelta(row.sent, old!.tx)) / elapsed : nil
                    result.interfaces.append(NetworkInterface(id: name, received: row.received, sent: row.sent, download: down, upload: up))
                    nextCounters[name] = (row.received, row.sent)
                }
            }
        }
        interfaceCounters = nextCounters
        result.pressure = Int(raw.pressure); result.valid = raw.valid != 0
        if let old = previous, elapsed > 0 {
            let user = cpuTickDelta(raw.cpu_user, old.cpu_user), system = cpuTickDelta(raw.cpu_system, old.cpu_system), idle = cpuTickDelta(raw.cpu_idle, old.cpu_idle)
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
                                                let delta = cpuTickDelta(total[i], oldTotal[i])
                                                return delta > 0 ? min(100, Double(cpuTickDelta(busy[i], oldBusy[i])) / Double(delta) * 100) : 0
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
        if !includeProcesses {
            previous = raw; time = now
            return result
        }
        let processNow = ProcessInfo.processInfo.systemUptime
        let processElapsed = processTime.map { processNow - $0 } ?? 0
        var pointer: UnsafeMutablePointer<TGProcess>?
        let count = tg_processes(&pointer)
        var next: [Int32: (birth: UInt64, cpu: UInt64, read: UInt64, write: UInt64, name: String, path: String?, shortName: String, ioValid: Bool, application: ProcessApplication?)] = [:]
        next.reserveCapacity(Int(count))
        if let pointer {
            defer { tg_free(pointer) }
            result.processes.reserveCapacity(Int(count))
            for index in 0..<Int(count) {
                var p = pointer[index]
                let shortName = withUnsafePointer(to: &p.name) { $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) } }
                let old = processes[p.pid]
                let path: String?
                let name: String
                let application: ProcessApplication?
                if let old, old.birth == p.birth && old.shortName == shortName { path = old.path; name = old.name; application = old.application }
                else {
                    var buffer = [CChar](repeating: 0, count: 4096)
                    path = tg_path(p.pid, &buffer, 4096) > 0 ? String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
                    name = path?.split(separator: "/").last.map(String.init) ?? shortName
                    application = processApplication(path)
                }
                let cpu = old?.birth == p.birth ? cpuPercent(next: p.cpu, previous: old!.cpu, elapsed: processElapsed) : nil
                result.processes.append(ProcessRow(id: p.pid, parent: p.parent, path: path, birth: p.birth, name: name, cpu: cpu, resident: p.resident, footprint: p.footprint_valid != 0 ? p.footprint : nil, threads: p.threads, uid: p.uid, readRate: old?.birth == p.birth && old?.ioValid == true && processElapsed > 0 && p.footprint_valid != 0 ? Double(counterDelta(p.disk_read, old!.read)) / processElapsed : nil, writeRate: old?.birth == p.birth && old?.ioValid == true && processElapsed > 0 && p.footprint_valid != 0 ? Double(counterDelta(p.disk_write, old!.write)) / processElapsed : nil, application: application))
                next[p.pid] = (p.birth, p.cpu, p.disk_read, p.disk_write, name, path, shortName, p.footprint_valid != 0, application)
            }
        }
        previous = raw; time = now; processTime = processNow; processes = next
        return result
    }
}

func bytes(_ value: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var amount = Double(value), index = 0
    while amount >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
    return String(format: amount >= 100 || index == 0 ? "%.0f %@" : "%.1f %@", amount, units[index])
}
func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return String(format: "%.1f%%", value)
}
func rate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0, value < Double(UInt64.max) else { return "—" }
    return bytes(UInt64(value)) + "/s"
}
