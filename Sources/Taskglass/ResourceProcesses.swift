import SwiftUI

/// The same process outline in every resource pane. Pages whose resource cannot be attributed
/// say so in one line; the chosen ranking always names the measurement actually shown.
struct ResourceProcesses: View {
    @ObservedObject var monitor: Monitor
    let pane: ResourcePane
    var leaders: [ProcessRow] { monitor.resourceLeaders }

    static let rankings: [(key: String, title: String, phrase: String)] = [
        ("cpu", "CPU", "CPU"), ("memory", "Memory", "memory"), ("disk", "Disk total", "total disk I/O"),
        ("read", "Disk reads", "disk reads"), ("write", "Disk writes", "disk writes")
    ]

    var body: some View {
        PaneSection("Processes", accessory: {
            HStack(spacing: 16) {
                // Stable across system-only samples, which carry no process list.
                if monitor.accessibleProcessCount > 0 {
                    Text("\(monitor.accessibleProcessCount) processes").monospacedDigit().help("Processes macOS allows Taskglass to read")
                }
                Toggle("Group by app", isOn: $monitor.resourceGrouped)
                    .toggleStyle(.checkbox)
                    .help("Combine each application with its helper processes")
                Picker("Rank by", selection: $monitor.resourceSort) {
                    ForEach(Self.rankings, id: \.key) { Text($0.title).tag($0.key) }
                }
                .pickerStyle(.menu).fixedSize()
                InfoButton("About this list", notes: [
                    "Every process macOS lets Taskglass read, ranked by the selected measurement. Click a measurement heading to rank by it; each page remembers its ranking. Expand an application to see its helpers. Double-click or press Return on a process to inspect it in Processes.",
                    "CPU: \(TableKit.cpuHelp)",
                    "Memory: \(TableKit.memoryHelp)",
                    "Disk: \(TableKit.diskHelp)"
                ])
            }
            .controlSize(.small)
        }) {
            if let subject = unattributedSubject {
                Notice("\(subject) isn't attributed to individual processes. This list is ranked by \(rankingPhrase).")
            }
            // Sizes itself to the header plus whole rows; every other row scrolls inside the table.
            ResourceProcessTable(monitor: monitor)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.bandRadius, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Metrics.bandRadius, style: .continuous).strokeBorder(Palette.keyline, lineWidth: Metrics.hairline) }
                .overlay {
                    if leaders.isEmpty {
                        Text("Reading processes").font(.body12).foregroundStyle(.secondary)
                    }
                }
            if monitor.resourceGrouped {
                Footnote("Application rows add up their processes. Shared memory can be counted more than once.")
            }
        }
    }

    var rankingPhrase: String { Self.rankings.first { $0.key == monitor.resourceSort }?.phrase ?? "CPU" }

    /// The resource on this page that has no per-process source.
    var unattributedSubject: String? {
        switch pane {
        case .gpu: "GPU use"
        case .neural: "Neural Engine use"
        case .network: "Network traffic"
        case .battery: "Battery draw"
        case .temperatures: "Temperature"
        default: nil
        }
    }
}
