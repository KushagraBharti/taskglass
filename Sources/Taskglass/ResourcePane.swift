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
