import SwiftUI
import AppKit

struct ProcessTable: NSViewRepresentable {
    @ObservedObject var monitor: Monitor
    func makeCoordinator() -> Coordinator { Coordinator(monitor) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        for (key, title, width) in [("name", "Process name", 330.0), ("pid", "PID", 65), ("cpu", "CPU", 85), ("memory", "Memory", 100), ("resident", "Resident", 100), ("threads", "Threads", 70), ("read", "Disk read/s", 95), ("write", "Disk write/s", 95), ("uid", "User ID", 70)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); c.title = title; c.width = width; c.minWidth = key == "name" ? 120 : 55
            c.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: key == "name")
            c.headerCell.alignment = key == "name" ? .left : .right
            table.addTableColumn(c)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.style = .fullWidth; table.rowHeight = 28; table.usesAlternatingRowBackgroundColors = true
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
        if let table = c.table {
            for column in table.tableColumns {
                switch column.identifier.rawValue {
                case "resident": column.isHidden = !monitor.showResident
                case "read", "write": column.isHidden = !monitor.showDisk
                case "uid": column.isHidden = !monitor.showUser
                default: break
                }
            }
        }
        guard c.rows != monitor.rows else { return }
        c.updating = true
        let countChanged = c.rows.count != monitor.rows.count
        c.rows = monitor.rows
        if let table = c.table {
            if countChanged { table.noteNumberOfRowsChanged() }
            // Update existing visible cells in place. Avoid row/view and accessibility churn.
            let range = table.rows(in: table.visibleRect)
            if range.location != NSNotFound && range.length > 0 {
                let end = min(c.rows.count, range.location + range.length)
                if range.location < end {
                    for row in range.location..<end {
                        for (index, column) in table.tableColumns.enumerated() where !column.isHidden {
                            if let cell = table.view(atColumn: index, row: row, makeIfNecessary: false) as? NSTableCellView {
                                c.configure(cell, key: column.identifier.rawValue, process: c.rows[row])
                            }
                        }
                    }
                }
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
            configure(cell, key: key.rawValue, process: rows[row])
            return cell
        }
        func configure(_ cell: NSTableCellView, key: String, process p: ProcessRow) {
            let value: String
            switch key {
            case "name": value = p.name
            case "pid": value = String(p.id)
            case "cpu": value = percent(p.cpu)
            case "memory": value = p.footprint.map(bytes) ?? "—"
            case "resident": value = bytes(p.resident)
            case "threads": value = String(p.threads)
            case "read": value = rate(p.readRate)
            case "write": value = rate(p.writeRate)
            default: value = String(p.uid)
            }
            if cell.textField?.stringValue != value { cell.textField?.stringValue = value }
            let quiet = key == "pid" || key == "uid" || (key == "cpu" && (p.cpu ?? 0) < 0.05)
            cell.textField?.textColor = quiet ? .secondaryLabelColor : .labelColor
            cell.toolTip = key == "memory" ? "Physical footprint. A dash means macOS denied access." : value
        }
        func makeCell(_ key: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView(); cell.identifier = key
            let text = NSTextField(labelWithString: ""); text.translatesAutoresizingMaskIntoConstraints = false
            text.font = key.rawValue == "name" ? .systemFont(ofSize: 13) : .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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
        @objc func inspect() { monitor.showingInspector = true }
    }
}
