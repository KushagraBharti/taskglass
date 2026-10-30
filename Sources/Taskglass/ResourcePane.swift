import SwiftUI

enum ResourcePane: String, CaseIterable, Identifiable {
    case processes, overview, cpu, memory, gpu, neural, storage, network, battery, temperatures
    var id: String { rawValue }
    var title: String {
        switch self {
        case .processes: "Processes"; case .overview: "Overview"; case .cpu: "CPU"; case .memory: "Memory"
        case .gpu: "GPU"; case .neural: "Neural Engine"; case .storage: "Storage"; case .network: "Network"; case .battery: "Battery"; case .temperatures: "Temperatures"
        }
    }
    var icon: String {
        switch self {
        case .processes: "list.bullet.rectangle"; case .overview: "gauge.with.dots.needle.50percent"; case .cpu: "cpu"
        case .memory: "memorychip"; case .gpu: "square.3.layers.3d"; case .neural: "brain"
        case .storage: "internaldrive"; case .network: "network"; case .battery: "battery.75percent"; case .temperatures: "thermometer.medium"
        }
    }
    var color: Color {
        switch self {
        case .cpu: Palette.cpu; case .memory: Palette.memory; case .gpu: Palette.gpu; case .neural: Palette.neural
        case .storage: Palette.storage; case .network: Palette.network; case .battery: Palette.battery; case .temperatures: Palette.temperature
        default: .accentColor
        }
    }
    var unit: PlotUnit {
        switch self {
        case .neural: .power; case .storage, .network: .rate; case .temperatures: .celsius; default: .percent
        }
    }
    var series: MetricSeries {
        switch self {
        case .memory: .memory; case .gpu: .gpu; case .neural: .ane
        case .storage: .diskTotal; case .network: .networkTotal; case .battery: .battery; case .temperatures: .temperature; default: .cpu
        }
    }
}

enum MetricSeries {
    case cpu, system, memory, gpu, renderer, tiler, ane, diskRead, diskWrite, diskTotal, download, upload, networkTotal, battery, cpuPower, gpuPower, temperature, gpuTemperature, batteryTemperature
    /// Selected-process history only (`Monitor.processHistory`): CPU percent per core, and physical footprint in bytes.
    case processCPU, processMemory, processGPUTime, processNeuralMemory
    func value(_ point: Point) -> Double? {
        let value: Double?
        switch self {
        case .cpu, .processCPU: value = point.cpu; case .system: value = point.systemCPU
        case .processGPUTime: value = point.processGPUTime
        case .processNeuralMemory: value = point.processNeuralMemory
        case .processMemory: value = point.processMemory
        case .memory: value = point.memory; case .gpu: value = point.gpu; case .renderer: value = point.renderer
        case .tiler: value = point.tiler; case .ane: value = point.aneWatts
        case .diskTotal: value = point.diskRead.flatMap { read in point.diskWrite.map { read + $0 } };
        case .diskRead: value = point.diskRead; case .diskWrite: value = point.diskWrite
        case .download: value = point.download; case .upload: value = point.upload
        case .networkTotal: value = point.download.flatMap { down in point.upload.map { down + $0 } }
        case .battery: value = point.batteryPercent; case .cpuPower: value = point.cpuWatts; case .gpuPower: value = point.gpuWatts
        case .temperature: value = point.temperature
        case .gpuTemperature: value = point.gpuTemperature
        case .batteryTemperature: value = point.batteryTemperature
        }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }
}
func niceCeiling(_ value: Double, minimum: Double) -> Double {
    let x = max(value, minimum)
    let exponent = pow(10, floor(log10(x)))
    return [1.0, 2, 5, 10].map { $0 * exponent }.first { $0 >= x } ?? x
}
/// Next power of two at or above the value. Binary byte units then label as 512 KB, 1 MB, 2 MB, 4 MB…
func binaryCeiling(_ value: Double, minimum: Double) -> Double {
    let x = max(value, minimum, 1)
    return pow(2, ceil(log2(x)))
}
