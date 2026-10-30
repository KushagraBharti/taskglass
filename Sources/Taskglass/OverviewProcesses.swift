import SwiftUI
import AppKit

/// Only process samples rebuild this list; unrelated hardware updates leave it alone.
struct OverviewProcesses: View {
    let monitor: Monitor
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CellHeader("Top processes", icon: ResourcePane.processes.icon, tint: .secondary) {
                LinkButton("Show all") { openProcesses(selecting: nil) }
            }.padding(.bottom, 4)
            processLine(icon: nil, name: Text("Name"), cpu: Text("CPU"), memory: Text("Memory"))
                .font(.caption11).foregroundStyle(.secondary)
                .overlay(alignment: .bottom) { Palette.keyline.frame(height: Metrics.hairline).padding(.horizontal, 6) }
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                if monitor.overviewProcesses.isEmpty {
                    Text("Reading processes").font(.caption11).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading).padding(.horizontal, 6)
                }
                ForEach(monitor.overviewProcesses) { process in
                    let cpu = percent(process.cpu), memory = process.footprint.map(bytes)
                    Button { openProcesses(selecting: process.id) } label: {
                        processLine(icon: ProcessIcons.icon(for: process),
                                    name: Text(process.name).foregroundStyle(.primary),
                                    cpu: Text(cpu).foregroundStyle(.primary),
                                    memory: Text(memory ?? "—").foregroundStyle(process.footprint == nil ? .tertiary : .secondary))
                            .font(.body12).frame(height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(HoverFillStyle(radius: 5))
                    .help("Inspect \(process.name) in Processes")
                    .accessibilityLabel("\(process.name), CPU \(cpu), memory \(memory ?? "unavailable")")
                }
            }.frame(minHeight: 5 * 26, alignment: .top)
        }.cellLayout()
    }
    func processLine(icon: NSImage?, name: Text, cpu: Text, memory: Text) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon { Image(nsImage: icon).resizable().interpolation(.high) } else { Color.clear }
            }.frame(width: 16, height: 16).accessibilityHidden(true)
            name.lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            cpu.frame(width: 56, alignment: .trailing)
            memory.frame(width: 68, alignment: .trailing).padding(.leading, 4)
        }
        .monospacedDigit().frame(minHeight: 22).padding(.horizontal, 6)
    }
    func openProcesses(selecting id: Int32?) {
        monitor.sort = "cpu"; monitor.ascending = false
        if let id { monitor.selected = id; monitor.showingInspector = true }
        monitor.pane = .processes
    }

}
