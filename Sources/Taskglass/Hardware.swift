import Foundation
import SystemProbe

func cText<T>(_ value: T) -> String {
    var copy = value
    return withUnsafePointer(to: &copy) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
    }
}
func measured(_ value: Double) -> Double? { value.isFinite ? value : nil }
func watts(_ value: Double?) -> String { value.map { decimal($0, places: 2) + " W" } ?? "—" }
func temperature(_ value: Double?) -> String { value.map { decimal($0, places: 0) + "°C" } ?? "—" }

struct TemperatureReading: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let source: String
    let group: String
    let celsius: Double
}
struct HardwareMetrics: Sendable {
    var chip = "Apple silicon", model = ""
    var gpuUsage: Double?, rendererUsage: Double?, tilerUsage: Double?
    var gpuCores = 0
    var gpuAllocated: UInt64?, gpuInUse: UInt64?
    var cpuWatts: Double?, gpuWatts: Double?, aneWatts: Double?
    var powerSource = ""
    var anePresent = false
    var diskRead: Double?, diskWrite: Double?
    var diskReadIOPS: Double?, diskWriteIOPS: Double?
    var batteryVoltage: Double?, batteryMinutes: Double?
    var diskTotal: UInt64?, diskAvailable: UInt64?
    var batteryPercent: Double?, batteryTemperature: Double?, batteryWatts: Double?, batteryCapacityRatio: Double?
    var batteryPresent = false, batteryCharging = false, batteryExternal = false
    var batteryCycles = 0
    var coreKinds: [String] = []
    var temperatures: [TemperatureReading] = []
    var fan0: Double?, fan1: Double?, fan0Max: Double?, fan1Max: Double?
    var cpuTemperature: Double?, gpuTemperature: Double?
    var tier0 = "", tier1 = "", tier0Count = 0, tier1Count = 0
    var batteryState: String { batteryPercent == nil ? "Unavailable" : batteryCharging ? "Charging" : batteryExternal ? "Power adapter" : "On battery" }
}
final class HardwareReader {
    private var probe: OpaquePointer?
    private var initialized = false
    private struct DiskCounters {
        let valid: Int32, opsValid: Int32
        let identity: UInt64, read: UInt64, write: UInt64, readOps: UInt64, writeOps: UInt64
        init(_ r: TGHardware) {
            valid = r.disk_valid; opsValid = r.disk_ops_valid; identity = r.disk_identity
            read = r.disk_read; write = r.disk_write; readOps = r.disk_read_ops; writeOps = r.disk_write_ops
        }
    }
    private var previous: DiskCounters?
    private var metadataLoaded = false
    private var previousTime: Double?
    private var slowTime: Double = -.infinity
    private var detailsActive = false
    private(set) var cached = HardwareMetrics()
    func reset() {
        if let probe { tg_hardware_reset(probe) }
        previous = nil; previousTime = nil
    }
    func read(now: Double, includeSensorDetails: Bool = true) -> HardwareMetrics {
        if !initialized { probe = tg_hardware_create(); initialized = true }
        guard let probe else { return cached }
        let slow = now - slowTime >= 10 || (includeSensorDetails && !detailsActive)
        // Modes: fast=0, full sensor table=1, summary with SMC/IOHID fallback=2.
        let mode: Int32 = slow ? (includeSensorDetails ? 1 : 2) : 0
        var r = tg_hardware_read(probe, mode)
        detailsActive = includeSensorDetails
        let sampleTime = ProcessInfo.processInfo.systemUptime
        if slow { slowTime = now }
        var h = cached
        if !metadataLoaded {
            h.chip = cText(r.chip); h.model = cText(r.model)
            h.gpuCores = Int(r.gpu_cores); h.anePresent = r.ane_present != 0
            h.powerSource = cText(r.power_source)
            h.tier0 = cText(r.tier0_name); h.tier1 = cText(r.tier1_name)
            h.tier0Count = Int(r.tier0_cores); h.tier1Count = Int(r.tier1_cores)
        }
        // Fast readings must replace cached values even when a source becomes unavailable.
        h.gpuUsage = r.gpu_valid != 0 ? measured(r.gpu_usage) : nil
        h.rendererUsage = measured(r.renderer_usage); h.tilerUsage = measured(r.tiler_usage)
        h.gpuAllocated = r.gpu_memory_valid != 0 ? r.gpu_allocated : nil
        h.gpuInUse = r.gpu_memory_valid != 0 ? r.gpu_in_use : nil
        h.cpuWatts = measured(r.cpu_watts); h.gpuWatts = measured(r.gpu_watts); h.aneWatts = measured(r.ane_watts)
        h.diskRead = nil; h.diskWrite = nil; h.diskReadIOPS = nil; h.diskWriteIOPS = nil
        if let previous, let previousTime, sampleTime > previousTime, r.disk_valid != 0, previous.valid != 0, previous.identity == r.disk_identity {
            h.diskRead = Double(counterDelta(r.disk_read, previous.read)) / (sampleTime - previousTime)
            h.diskWrite = Double(counterDelta(r.disk_write, previous.write)) / (sampleTime - previousTime)
            if r.disk_ops_valid != 0 && previous.opsValid != 0 {
                h.diskReadIOPS = Double(counterDelta(r.disk_read_ops, previous.readOps)) / (sampleTime - previousTime)
                h.diskWriteIOPS = Double(counterDelta(r.disk_write_ops, previous.writeOps)) / (sampleTime - previousTime)
            }
        }
        if slow {
            h.diskTotal = r.storage_valid != 0 ? r.disk_total : nil
            h.diskAvailable = r.storage_valid != 0 ? r.disk_available : nil
            h.batteryVoltage = measured(r.battery_voltage); h.batteryMinutes = measured(r.battery_minutes)
            h.batteryPresent = r.battery_present != 0; h.batteryCharging = r.battery_charging != 0; h.batteryExternal = r.battery_external != 0
            h.batteryPercent = measured(r.battery_percent); h.batteryTemperature = measured(r.battery_temperature)
            h.batteryWatts = measured(r.battery_watts); h.batteryCapacityRatio = measured(r.battery_health); h.batteryCycles = Int(r.battery_cycles)
            h.fan0 = measured(r.fan0_rpm); h.fan1 = measured(r.fan1_rpm); h.fan0Max = measured(r.fan0_max); h.fan1Max = measured(r.fan1_max)
            h.cpuTemperature = measured(r.cpu_temperature); h.gpuTemperature = measured(r.gpu_temperature)
            let count = min(192, max(0, Int(r.temperature_count)))
            h.temperatures = withUnsafePointer(to: &r.temperatures) { ptr in
                ptr.withMemoryRebound(to: TGTemperature.self, capacity: 192) { list in
                    (0..<count).map { index in
                        let sensor = list[index], source = cText(sensor.source)
                        let group = sensor.kind == 1 ? "CPU" : sensor.kind == 2 ? "GPU" : sensor.kind == 4 ? "Storage" : sensor.kind == 5 ? "Battery" : "PMU / other"
                        return TemperatureReading(id: "\(source):\(sensor.identifier)", name: cText(sensor.name), source: source, group: group, celsius: sensor.value)
                    }
                }
            }
        }
        let coreCount = min(128, ProcessInfo.processInfo.activeProcessorCount)
        if metadataLoaded && cached.coreKinds.count == coreCount {
            h.coreKinds = cached.coreKinds
        } else {
            h.coreKinds = withUnsafePointer(to: &r.core_kind) { ptr in
                ptr.withMemoryRebound(to: UInt8.self, capacity: 128) { bytes in
                    (0..<coreCount).map { i in
                        switch bytes[i] {
                        case 69: return "Efficiency"
                        case 77: return "Performance"
                        case 83: return "Super"
                        case 80: return h.tier0 == "Super" || h.tier1 == "Super" ? "Super" : "Performance"
                        default: return "Cores"
                        }
                    }
                }
            }
        }
        metadataLoaded = true
        previous = DiskCounters(r); previousTime = sampleTime; cached = h
        return h
    }
    deinit { if let probe { tg_hardware_destroy(probe) } }
}
