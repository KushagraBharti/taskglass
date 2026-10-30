import SwiftUI
import AppKit

/// Resource hues and chrome tones. Colour is reserved for measured data; chrome stays neutral.
enum Palette {
    static let background = Color.black
    static let surface = Color.white.opacity(0.04)
    static let surfaceHover = Color.white.opacity(0.035)
    static let keyline = Color.white.opacity(0.085)
    static let grid = Color.white.opacity(0.07)
    static let baseline = Color.white.opacity(0.16)
    static let track = Color.white.opacity(0.08)
    /// Axis labels and secondary notes. A fixed tone below `.secondary`: the hierarchical
    /// `.tertiary` style fades to near-invisible on black once the window is inactive.
    static let quiet = Color.white.opacity(0.42)

    static let cpu = Color(nsColor: cpuNS)
    static let performanceCores = Color(nsColor: performanceNS)
    static let efficiencyCores = Color(nsColor: efficiencyNS)
    static let memory = Color(nsColor: memoryNS)
    static let gpu = Color(red: 1.00, green: 0.62, blue: 0.26)
    static let renderer = Color(red: 1.00, green: 0.83, blue: 0.36)
    static let tiler = Color(red: 1.00, green: 0.42, blue: 0.40)
    static let neural = Color(red: 1.00, green: 0.43, blue: 0.64)
    static let storage = Color(nsColor: storageNS)
    static let network = Color(red: 0.49, green: 0.58, blue: 1.00)
    static let battery = Color(red: 0.50, green: 0.86, blue: 0.40)
    static let temperature = Color(red: 1.00, green: 0.49, blue: 0.38)
    static let power = Color(red: 1.00, green: 0.82, blue: 0.32)
    static let fan = Color(white: 0.78)

    static let gpuNS = NSColor(srgbRed: 1, green: 0.62, blue: 0.26, alpha: 1)
    static let neuralNS = NSColor(srgbRed: 1, green: 0.43, blue: 0.64, alpha: 1)
    static let cpuNS = NSColor(srgbRed: 0.35, green: 0.78, blue: 0.98, alpha: 1)
    static let performanceNS = NSColor(srgbRed: 0.27, green: 0.53, blue: 1.00, alpha: 1)
    static let efficiencyNS = NSColor(srgbRed: 0.36, green: 0.86, blue: 0.80, alpha: 1)
    static let memoryNS = NSColor(srgbRed: 0.71, green: 0.52, blue: 1.00, alpha: 1)
    static let storageNS = NSColor(srgbRed: 0.33, green: 0.85, blue: 0.68, alpha: 1)

    static func coreNS(_ kind: String) -> NSColor {
        kind == "Super" ? cpuNS : kind == "Efficiency" ? efficiencyNS : performanceNS
    }
    static func core(_ kind: String) -> Color { Color(nsColor: coreNS(kind)) }
}

/// 4 pt spacing grid and shared geometry.
enum Metrics {
    static let pagePadding: CGFloat = 24
    static let bandGap: CGFloat = 12
    static let sectionGap: CGFloat = 28
    static let cellHorizontal: CGFloat = 16
    static let cellVertical: CGFloat = 14
    static let bandRadius: CGFloat = 10
    static let rowHeight: CGFloat = 18
    static let tableRow: CGFloat = 26
    static let contentWidth: CGFloat = 1200
    static let paneWidth: CGFloat = 1080
    static let hairline: CGFloat = 0.5
}

extension Font {
    static let cellTitle = Font.system(size: 12, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let body12 = Font.system(size: 12)
    static let caption11 = Font.system(size: 11)
    static let scale10 = Font.system(size: 10).monospacedDigit()
    static let stat = Font.system(size: 15, weight: .medium).monospacedDigit()
}

/// Power formatting shared by every pane: milliwatts below 1 W.
func power(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return abs(value) < 1 ? decimal(value * 1000, places: 0) + " mW" : decimal(value, places: 2) + " W"
}
func rpm(_ value: Double?) -> String { value.map { decimal($0, places: 0) + " rpm" } ?? "—" }

/// Installed memory as marketed, e.g. "48 GB", rather than "48.0 GB".
func memoryCapacity(_ total: UInt64) -> String { "\(Int((Double(total) / 1_073_741_824).rounded())) GB" }

/// Battery flow named by direction, so the value never needs a sign convention to read.
func batteryFlow(_ watts: Double?) -> (label: String, value: String) {
    guard let watts, watts.isFinite else { return ("Net power", "—") }
    if watts <= -0.0005 { return ("Discharging", power(-watts)) }
    if watts >= 0.0005 { return ("Charging", power(watts)) }
    return ("Net power", power(0))
}

func iops(_ value: Double?) -> String { value.map { decimal($0, places: 0) + "/s" } ?? "—" }

/// "3 minutes", "1 minute", "30 seconds" for the shared history window.
func windowName(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(seconds)) seconds" }
    let minutes = Int(seconds / 60)
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
}

var thermalStateName: String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: "Nominal"; case .fair: "Fair"; case .serious: "Serious"; case .critical: "Critical"
    @unknown default: "Unknown"
    }
}
var thermalStateColor: Color {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: .green; case .fair: .yellow; case .serious: .orange; case .critical: .red
    @unknown default: .secondary
    }
}
func pressureName(_ level: Int) -> String { level == 1 ? "Normal" : level == 2 ? "Elevated" : level == 4 ? "Critical" : "Unknown" }
func pressureColor(_ level: Int) -> Color { level == 1 ? .green : level == 2 ? .yellow : level == 4 ? .red : .secondary }

extension Monitor {
    /// Nice 1/2/5 ceiling of the visible window's peak across several series, with an idle floor.
    func ceiling(_ series: [MetricSeries], minimum: Double) -> Double {
        niceCeiling(series.lazy.compactMap(peak).max() ?? 0, minimum: minimum)
    }
    /// Byte rates scale in powers of two from a 1 MB/s idle floor, so every axis label is a round binary value.
    func rateCeiling(_ series: [MetricSeries]) -> Double {
        binaryCeiling(series.lazy.compactMap(peak).max() ?? 0, minimum: 1_048_576)
    }
    /// Temperature plots start at 20 °C and top out at 100 °C unless a reading in the window needs more room.
    var temperatureScale: (floor: Double, ceiling: Double) {
        let hottest = [MetricSeries.temperature, .gpuTemperature, .batteryTemperature].lazy.compactMap(peak).max() ?? 0
        return (20, hottest > 96 ? 120 : 100)
    }
}
