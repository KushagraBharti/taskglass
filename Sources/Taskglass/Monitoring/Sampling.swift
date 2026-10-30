import Foundation
import SystemProbe

/// Immutable strings and bundle identity are shared by all samples of a process.
/// This keeps sorting/copying rows cheap and resolves non-app paths only once.
final class ProcessMetadata: Sendable, Equatable {
    let path: String?
    let name: String
    let application: ProcessApplication?
    init(path: String?, name: String, application: ProcessApplication? = nil) {
        self.path = path; self.name = name
        self.application = application ?? processApplication(path)
    }
    static func == (lhs: ProcessMetadata, rhs: ProcessMetadata) -> Bool {
        lhs === rhs || (lhs.path == rhs.path && lhs.name == rhs.name && lhs.application == rhs.application)
    }
}

struct ProcessRow: Identifiable, Sendable, Equatable {
    let id: Int32
    let parent: Int32
    let metadata: ProcessMetadata
    let birth: UInt64
    var path: String? { metadata.path }
    var name: String { metadata.name }
    var application: ProcessApplication? { metadata.application }
    let cpu: Double?
    let resident: UInt64
    let footprint: UInt64?
    let threads: UInt32
    let uid: UInt32
    let readRate: Double?
    let writeRate: Double?
    var gpuTime: Double?
    var neuralMemory: UInt64?
    var aneGroup: UInt64?
    var aneGroupTime: Double?

    init(id: Int32, parent: Int32, metadata: ProcessMetadata, birth: UInt64, cpu: Double?, resident: UInt64,
         footprint: UInt64?, threads: UInt32, uid: UInt32, readRate: Double?, writeRate: Double?,
         gpuTime: Double? = nil, neuralMemory: UInt64? = nil, aneGroup: UInt64? = nil, aneGroupTime: Double? = nil) {
        self.id = id; self.parent = parent; self.metadata = metadata; self.birth = birth; self.cpu = cpu
        self.resident = resident; self.footprint = footprint; self.threads = threads; self.uid = uid
        self.readRate = readRate; self.writeRate = writeRate; self.gpuTime = gpuTime; self.neuralMemory = neuralMemory
        self.aneGroup = aneGroup; self.aneGroupTime = aneGroupTime
    }

    init(id: Int32, parent: Int32, path: String?, birth: UInt64, name: String, cpu: Double?, resident: UInt64,
         footprint: UInt64?, threads: UInt32, uid: UInt32, readRate: Double?, writeRate: Double?,
         application: ProcessApplication? = nil, gpuTime: Double? = nil, neuralMemory: UInt64? = nil,
         aneGroup: UInt64? = nil, aneGroupTime: Double? = nil) {
        self.init(id: id, parent: parent, metadata: ProcessMetadata(path: path, name: name, application: application),
                  birth: birth, cpu: cpu, resident: resident, footprint: footprint, threads: threads, uid: uid,
                  readRate: readRate, writeRate: writeRate, gpuTime: gpuTime, neuralMemory: neuralMemory,
                  aneGroup: aneGroup, aneGroupTime: aneGroupTime)
    }
}

struct Point: Sendable {
    let cpu: Double
    let memory: Double
    var time: Double = ProcessInfo.processInfo.systemUptime
    var processMemory: Double? = nil
    var processGPUTime: Double? = nil
    var processNeuralMemory: Double? = nil
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
    var gpuAccountingAvailable: Bool? = nil
    var aneAccountingAvailable: Bool? = nil
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
    private var gpuAccounting = GPUAccounting()
    private var aneAccounting = ANEAccounting()
    private var previous: TGSystem?
    private var time: TimeInterval?
    private var processes: [Int32: (birth: UInt64, cpu: UInt64, read: UInt64, write: UInt64, metadata: ProcessMetadata, shortName: String, ioValid: Bool)] = [:]
    func reset() { gpuAccounting.reset(); aneAccounting.reset(); hardware.reset(); hardwareActive = false; processTime = nil; previous = nil; time = nil; processes = [:]; interfaceCounters = [:] }
    func read(includeProcesses: Bool = true, includeHardware: Bool? = nil, includeSensorDetails: Bool = true, includeGPU: Bool = false, includeANE: Bool = false) -> Snapshot {
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
        var next: [Int32: (birth: UInt64, cpu: UInt64, read: UInt64, write: UInt64, metadata: ProcessMetadata, shortName: String, ioValid: Bool)] = [:]
        next.reserveCapacity(Int(count))
        if let pointer {
            defer { tg_free(pointer) }
            result.processes.reserveCapacity(Int(count))
            let rawRows = UnsafeBufferPointer(start: pointer, count: Int(count))
            var aneRates: [UInt64: Double] = [:]
            if includeANE {
                tg_ane_process_groups(pointer, count)
                var counters: [UInt64: UInt64] = [:]
                for row in rawRows where row.ane_valid != 0 {
                    if counters[row.ane_group] == nil { counters[row.ane_group] = row.ane_nanoseconds }
                }
                result.aneAccountingAvailable = !counters.isEmpty
                aneRates = aneAccounting.update(counters, now: ProcessInfo.processInfo.systemUptime)
            } else { aneAccounting.reset() }
            // One scratch path buffer per sample, allocated only for new identities.
            var pathBuffer: [CChar] = []
            for index in 0..<Int(count) {
                var p = pointer[index]
                let old = processes[p.pid]
                let shortName = withUnsafePointer(to: &p.name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: 64) { name in
                        if let old, old.birth == p.birth, old.shortName.withCString({ strcmp($0, name) == 0 }) {
                            return old.shortName
                        }
                        // Decode only a new/changed name. The fallback also preserves
                        // replacement-character behavior for truncated UTF-8 names.
                        return String(cString: name)
                    }
                }
                let metadata: ProcessMetadata
                if let old, old.birth == p.birth && old.shortName == shortName { metadata = old.metadata }
                else {
                    if pathBuffer.isEmpty { pathBuffer = [CChar](repeating: 0, count: 4096) }
                    let path = tg_path(p.pid, &pathBuffer, Int32(pathBuffer.count)) > 0 ? pathBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) } : nil
                    let name = path.map { path in
                        path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
                    } ?? shortName
                    metadata = ProcessMetadata(path: path, name: name)
                }
                let cpu = old?.birth == p.birth ? cpuPercent(next: p.cpu, previous: old!.cpu, elapsed: processElapsed) : nil
                result.processes.append(ProcessRow(id: p.pid, parent: p.parent, metadata: metadata, birth: p.birth, cpu: cpu, resident: p.resident, footprint: p.footprint_valid != 0 ? p.footprint : nil, threads: p.threads, uid: p.uid, readRate: old?.birth == p.birth && old?.ioValid == true && processElapsed > 0 && p.footprint_valid != 0 ? Double(counterDelta(p.disk_read, old!.read)) / processElapsed : nil, writeRate: old?.birth == p.birth && old?.ioValid == true && processElapsed > 0 && p.footprint_valid != 0 ? Double(counterDelta(p.disk_write, old!.write)) / processElapsed : nil,
                    neuralMemory: p.neural_valid != 0 ? p.neural_footprint : nil,
                    aneGroup: p.ane_group != 0 ? p.ane_group : nil, aneGroupTime: aneRates[p.ane_group]))
                next[p.pid] = (p.birth, p.cpu, p.disk_read, p.disk_write, metadata, shortName, p.footprint_valid != 0)
            }
            if includeGPU {
                var clients: UnsafeMutablePointer<TGGPUClient>?, available: Int32 = 0
                let clientCount = tg_gpu_clients(&clients, &available)
                defer { if let clients { tg_free(clients) } }
                let counters = UnsafeBufferPointer(start: clients, count: Int(clientCount)).lazy.map {
                    GPUClientCounter(id: $0.entry, pid: $0.pid, nanoseconds: $0.nanoseconds, contexts: $0.contexts)
                }
                result.gpuAccountingAvailable = available != 0
                let rates = gpuAccounting.update(counters, birthForPID: { next[$0]?.birth },
                    now: ProcessInfo.processInfo.systemUptime, available: available != 0)
                for index in result.processes.indices { result.processes[index].gpuTime = rates[result.processes[index].id] }
            } else { gpuAccounting.reset() }
        }
        if pointer == nil { gpuAccounting.reset(); aneAccounting.reset() }
        previous = raw; time = now; processTime = processNow; processes = next
        return result
    }
}

func bytes(_ value: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var amount = Double(value), index = 0
    while amount >= 1024 && index < units.count - 1 { amount /= 1024; index += 1 }
    return decimal(amount, places: amount >= 100 || index == 0 ? 0 : 1) + " " + units[index]
}
func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return decimal(value, places: 1) + "%"
}
func rate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0, value < Double(UInt64.max) else { return "—" }
    return bytes(UInt64(value)) + "/s"
}
