import SwiftUI
import AppKit

struct ProcessTable: NSViewRepresentable {
    @ObservedObject var monitor: Monitor
    func makeCoordinator() -> Coordinator { Coordinator(monitor) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        for (key, title, width) in [("name", "Process", 260.0), ("pid", "PID", 65), ("cpu", "CPU", 85), ("memory", "Memory", 100), ("resident", "Resident", 100), ("threads", "Threads", 70), ("read", "Disk read/s", 95), ("write", "Disk write/s", 95), ("uid", "User ID", 70)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); c.title = title; c.width = width; c.minWidth = key == "name" ? 120 : 55
            c.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: key == "name")
            c.headerCell.alignment = key == "name" ? .left : .right
            table.addTableColumn(c)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.style = .fullWidth; table.rowHeight = 29; table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false; table.allowsEmptySelection = true
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.sortDescriptors = [NSSortDescriptor(key: "memory", ascending: false)]
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.inspect)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let c = context.coordinator
        guard c.rows != monitor.rows else { return }
        c.updating = true
        let countChanged = c.rows.count != monitor.rows.count
        c.rows = monitor.rows
        if let table = c.table {
            if countChanged { table.noteNumberOfRowsChanged() }
            let range = table.rows(in: table.visibleRect)
            if range.location != NSNotFound && range.length > 0 {
                table.reloadData(forRowIndexes: IndexSet(integersIn: range.location..<min(c.rows.count, range.location + range.length)), columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
            }
        }
        if let selected = monitor.selected, let index = c.rows.firstIndex(where: { $0.id == selected }) {
            c.table?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else { c.table?.deselectAll(nil) }
        c.updating = false
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let monitor: Monitor
        var rows: [ProcessRow] = []
        weak var table: NSTableView?
        var updating = false
        init(_ monitor: Monitor) { self.monitor = monitor }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count, let key = column?.identifier else { return nil }
            let cell = tableView.makeView(withIdentifier: key, owner: self) as? NSTableCellView ?? makeCell(key)
            let p = rows[row]
            switch key.rawValue {
            case "name": cell.textField?.stringValue = p.name
            case "pid": cell.textField?.stringValue = String(p.id)
            case "cpu": cell.textField?.stringValue = percent(p.cpu)
            case "memory": cell.textField?.stringValue = p.footprint.map(bytes) ?? "—"
            case "resident": cell.textField?.stringValue = bytes(p.resident)
            case "threads": cell.textField?.stringValue = String(p.threads)
            case "read": cell.textField?.stringValue = rate(p.readRate)
            case "write": cell.textField?.stringValue = rate(p.writeRate)
            default: cell.textField?.stringValue = String(p.uid)
            }
            cell.toolTip = key.rawValue == "memory" ? "Physical footprint. A dash means macOS denied access." : cell.textField?.stringValue
            return cell
        }
        func makeCell(_ key: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView(); cell.identifier = key
            let text = NSTextField(labelWithString: ""); text.translatesAutoresizingMaskIntoConstraints = false
            text.font = key.rawValue == "name" ? .systemFont(ofSize: 12) : .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            text.alignment = key.rawValue == "name" ? .left : .right; text.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(text); cell.textField = text
            NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            monitor.selected = table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow].id : nil
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first else { return }
            monitor.sort = descriptor.key ?? "memory"; monitor.ascending = descriptor.ascending; monitor.arrange()
        }
        @objc func inspect() { monitor.inspect = true }
    }
}
