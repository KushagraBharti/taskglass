import Foundation
import SystemProbe

func cText<T>(_ value: T) -> String {
    var copy = value
    return withUnsafePointer(to: &copy) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
    }
}
func measured(_ value: Double) -> Double? { value.isFinite ? value : nil }
func watts(_ value: Double?) -> String { value.map { String(format: "%.2f W", $0) } ?? "—" }
func temperature(_ value: Double?) -> String { value.map { String(format: "%.0f°C", $0) } ?? "—" }

struct TemperatureReading: Identifiable, Sendable {
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
    private var previous: TGHardware?
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
        let r = tg_hardware_read(probe, mode)
        detailsActive = includeSensorDetails
        let sampleTime = ProcessInfo.processInfo.systemUptime
        if slow { slowTime = now }
        var h = HardwareMetrics()
        h.chip = cText(r.chip); h.model = cText(r.model)
        h.gpuCores = Int(r.gpu_cores)
        if r.gpu_valid != 0 { h.gpuUsage = measured(r.gpu_usage) }
        h.rendererUsage = measured(r.renderer_usage); h.tilerUsage = measured(r.tiler_usage)
        if r.gpu_memory_valid != 0 { h.gpuAllocated = r.gpu_allocated; h.gpuInUse = r.gpu_in_use }
        h.cpuWatts = measured(r.cpu_watts); h.gpuWatts = measured(r.gpu_watts); h.aneWatts = measured(r.ane_watts)
        h.anePresent = r.ane_present != 0; h.powerSource = cText(r.power_source)
        if let previous, let previousTime, sampleTime > previousTime, r.disk_valid != 0, previous.disk_valid != 0, previous.disk_identity == r.disk_identity {
            h.diskRead = Double(counterDelta(r.disk_read, previous.disk_read)) / (sampleTime - previousTime)
            h.diskWrite = Double(counterDelta(r.disk_write, previous.disk_write)) / (sampleTime - previousTime)
            if r.disk_ops_valid != 0 && previous.disk_ops_valid != 0 {
                h.diskReadIOPS = Double(counterDelta(r.disk_read_ops, previous.disk_read_ops)) / (sampleTime - previousTime)
                h.diskWriteIOPS = Double(counterDelta(r.disk_write_ops, previous.disk_write_ops)) / (sampleTime - previousTime)
            }
        }
        if r.storage_valid != 0 { h.diskTotal = r.disk_total; h.diskAvailable = r.disk_available }
        h.batteryVoltage = measured(r.battery_voltage); h.batteryMinutes = measured(r.battery_minutes)
        h.batteryPresent = r.battery_present != 0; h.batteryCharging = r.battery_charging != 0; h.batteryExternal = r.battery_external != 0
        h.batteryPercent = measured(r.battery_percent); h.batteryTemperature = measured(r.battery_temperature)
        h.batteryWatts = measured(r.battery_watts); h.batteryCapacityRatio = measured(r.battery_health); h.batteryCycles = Int(r.battery_cycles)
        h.fan0 = measured(r.fan0_rpm); h.fan1 = measured(r.fan1_rpm); h.fan0Max = measured(r.fan0_max); h.fan1Max = measured(r.fan1_max)
        if slow || cached.temperatures.isEmpty {
            var sensors = r.temperatures
            h.temperatures = withUnsafePointer(to: &sensors) { ptr in
                ptr.withMemoryRebound(to: TGTemperature.self, capacity: 192) { list in
                    (0..<Int(r.temperature_count)).map { index in
                        let sensor = list[index], source = cText(sensor.source)
                        let group = sensor.kind == 1 ? "CPU" : sensor.kind == 2 ? "GPU" : sensor.kind == 4 ? "Storage" : sensor.kind == 5 ? "Battery" : "PMU / other"
                        return TemperatureReading(id: "\(source):\(sensor.identifier)", name: cText(sensor.name), source: source, group: group, celsius: sensor.value)
                    }
                }
            }
        } else { h.temperatures = cached.temperatures }
        h.cpuTemperature = measured(r.cpu_temperature); h.gpuTemperature = measured(r.gpu_temperature)
        h.tier0 = cText(r.tier0_name); h.tier1 = cText(r.tier1_name)
        h.tier0Count = Int(r.tier0_cores); h.tier1Count = Int(r.tier1_cores)
        var kindBytes = r.core_kind
        h.coreKinds = withUnsafePointer(to: &kindBytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 128) { bytes in
                (0..<ProcessInfo.processInfo.activeProcessorCount).map { i in
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
        previous = r; previousTime = sampleTime; cached = h
        return h
    }
    deinit { if let probe { tg_hardware_destroy(probe) } }
}
