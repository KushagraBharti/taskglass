import Foundation

enum MetricSeries: Hashable {
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
