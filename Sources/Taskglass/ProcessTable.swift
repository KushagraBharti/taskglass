import SwiftUI
import AppKit

/// Main process list. Row positions are reused across samples; only on-screen cells are rewritten.
struct ProcessTable: NSViewRepresentable {
    @ObservedObject var monitor: Monitor
    func makeCoordinator() -> Coordinator { Coordinator(monitor) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = ProcessTableView()
        TableKit.install([
            .init(key: "name", title: "Process", width: 280, minWidth: 160),
            .init(key: "pid", title: "PID", width: 64, minWidth: 52),
            .init(key: "cpu", title: "CPU", width: 96, minWidth: 88, help: TableKit.cpuHelp),
            .init(key: "memory", title: "Memory", width: 104, minWidth: 94, help: TableKit.footprintHelp),
            .init(key: "gpu", title: "GPU time", width: 128, minWidth: 116, help: TableKit.gpuHelp),
            .init(key: "neural", title: "Neural memory", width: 128, minWidth: 116, help: TableKit.neuralHelp),
            .init(key: "resident", title: "Resident", width: 92, minWidth: 80, help: "Resident memory. Includes pages shared with other processes."),
            .init(key: "threads", title: "Threads", width: 72, minWidth: 60),
            .init(key: "read", title: "Read/s", width: 104, minWidth: 92, help: TableKit.diskHelp),
            .init(key: "write", title: "Write/s", width: 104, minWidth: 92, help: TableKit.diskHelp),
            .init(key: "uid", title: "User", width: 104, minWidth: 64, help: "Account that owns the process")
        ], in: table, ascendingKeys: ["name", "pid", "uid"])
        table.style = .fullWidth
        table.backgroundColor = .black
        // Initial order is set before the delegate exists, so it can't publish during view creation.
        table.sortDescriptors = [NSSortDescriptor(key: monitor.sort, ascending: monitor.ascending)]
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.inspectClicked)
        table.onReturn = { [weak monitor = monitor] in if monitor?.selected != nil { monitor?.showingInspector = true } }
        table.setAccessibilityLabel("Processes")
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = context.coordinator; table.menu = menu
        context.coordinator.table = table
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.namesResolved), name: UserNames.didResolve, object: nil)
        return TableKit.scrollView(for: table)
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let c = context.coordinator
        guard let table = c.table else { return }
        var columnsChanged = false
        for column in table.tableColumns {
            let hidden: Bool
            switch column.identifier.rawValue {
            case "gpu": hidden = !monitor.showGPU
            case "neural": hidden = !monitor.showNeuralMemory
            case "resident": hidden = !monitor.showResident
            case "read", "write": hidden = !monitor.showDisk
            case "uid": hidden = !monitor.showUser
            default: continue
            }
            if column.isHidden != hidden { column.isHidden = hidden; columnsChanged = true }
        }
        if columnsChanged { TableKit.fitVisibleColumns(table) }
        let sortChanged = c.sortKey != monitor.sort || c.ascending != monitor.ascending
        let rowsChanged = c.rows != monitor.rows
        guard rowsChanged || sortChanged || columnsChanged || c.selected != monitor.selected else { return }
        c.updating = true
        defer { c.updating = false }
        if sortChanged {
            let descriptors = [NSSortDescriptor(key: monitor.sort, ascending: monitor.ascending)]
            if table.sortDescriptors != descriptors { table.sortDescriptors = descriptors }
            c.sortKey = monitor.sort; c.ascending = monitor.ascending
        }
        if rowsChanged || sortChanged {
            let countChanged = c.rows.count != monitor.rows.count
            c.rows = monitor.rows
            c.maximum = c.rows.lazy.compactMap { c.barValue($0) }.max() ?? 0
            if countChanged { table.noteNumberOfRowsChanged() }
            TableKit.refreshVisible(table) { cell, key, row in
                if row < c.rows.count { c.configure(cell, key: key, process: c.rows[row]) }
            }
        }
        c.selected = monitor.selected
        if let selected = monitor.selected, let index = c.rows.firstIndex(where: { $0.id == selected }) {
            if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            // Bring a selection made elsewhere (Overview, resource pages) into view once.
            if c.revealed != selected { table.scrollRowToVisible(index); c.revealed = selected }
        } else if table.selectedRow >= 0 { table.deselectAll(nil) }
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        let monitor: Monitor
        var rows: [ProcessRow] = []
        var sortKey = ""
        var ascending = false
        var selected: Int32?
        var revealed: Int32?
        var maximum = 0.0
        weak var table: ProcessTableView?
        var updating = false
        init(_ monitor: Monitor) { self.monitor = monitor }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count, let key = column?.identifier else { return nil }
            let cell = tableView.makeView(withIdentifier: key, owner: self) as? ProcessCell ?? ProcessCell(key: key.rawValue)
            configure(cell, key: key.rawValue, process: rows[row])
            return cell
        }

        /// Bars appear in the CPU or Memory column while the list is ranked by it, relative to the largest row.
        func barValue(_ p: ProcessRow) -> Double? {
            switch sortKey {
            case "gpu": p.gpuTime
            case "neural": p.neuralMemory.map { Double($0) }
            case "cpu": p.cpu
            case "memory": p.footprint.map { Double($0) }
            default: nil
            }
        }
        func configure(_ cell: ProcessCell, key: String, process p: ProcessRow) {
            switch key {
            case "name":
                cell.show(p.name)
                cell.setIcon(ProcessIcons.icon(for: p))
                let tip = p.path ?? p.name
                if cell.toolTip != tip { cell.toolTip = tip }
                return
            case "pid": cell.show(String(p.id), quiet: true)
            case "cpu": cell.showMeasurement(.percentage(p.cpu), quiet: (p.cpu ?? 1) < 0.05)
            case "memory": cell.showMeasurement(.byteCount(p.footprint))
            case "gpu": cell.showMeasurement(.gpuTime(p.gpuTime), quiet: p.gpuTime == 0)
            case "neural": cell.showMeasurement(.byteCount(p.neuralMemory), quiet: p.neuralMemory == 0)
            case "resident": cell.showMeasurement(.byteCount(p.resident))
            case "threads": cell.show(String(p.threads))
            case "read": cell.showMeasurement(.byteRate(p.readRate), quiet: p.readRate == 0)
            case "write": cell.showMeasurement(.byteRate(p.writeRate), quiet: p.writeRate == 0)
            default: cell.show(UserNames.name(p.uid), quiet: true)
            }
            let ranked = key == sortKey && !ascending && maximum > 0
            cell.setBar(ranked ? barValue(p).map { $0 / maximum } : nil, tint: key == "gpu" ? Palette.gpuNS : key == "neural" ? Palette.neuralNS : key == "memory" ? Palette.memoryNS : Palette.cpuNS)
        }

        /// An account name arrived from the background lookup: replace the UID in visible User cells only.
        @objc func namesResolved() {
            guard let table, monitor.showUser else { return }
            TableKit.refreshVisible(table) { cell, key, row in
                if key == "uid", row < rows.count { configure(cell, key: key, process: rows[row]) }
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            let id = table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow].id : nil
            selected = id; revealed = id
            monitor.selected = id
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating, let descriptor = tableView.sortDescriptors.first else { return }
            monitor.sort = descriptor.key ?? "memory"; monitor.ascending = descriptor.ascending; monitor.arrange()
        }

        // MARK: Actions

        @objc func inspectClicked() {
            guard let table, table.clickedRow >= 0 else { return }
            monitor.showingInspector = true
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, table.clickedRow >= 0, table.clickedRow < rows.count else { return }
            let row = rows[table.clickedRow]
            menu.addItem("Inspect", target: self, action: #selector(inspect(_:)), represented: row.id)
            if let path = row.path { menu.addItem("Show in Finder", target: self, action: #selector(reveal(_:)), represented: path) }
            menu.addItem("Copy Name", target: self, action: #selector(copyName(_:)), represented: row.name)
            menu.addItem(.separator())
            let owned = row.uid == getuid() && row.id != getpid()
            menu.addItem("Quit…", target: self, action: #selector(quit(_:)), represented: row.id).isEnabled = owned
            menu.addItem("Force Quit…", target: self, action: #selector(forceQuit(_:)), represented: row.id).isEnabled = owned
        }
        @objc func inspect(_ item: NSMenuItem) {
            guard let id = item.representedObject as? Int32 else { return }
            monitor.selected = id; monitor.showingInspector = true
        }
        @objc func reveal(_ item: NSMenuItem) { if let path = item.representedObject as? String { revealInFinder(path) } }
        @objc func copyName(_ item: NSMenuItem) { if let name = item.representedObject as? String { copyToPasteboard(name) } }
        @objc func quit(_ item: NSMenuItem) { terminate(item, force: false) }
        @objc func forceQuit(_ item: NSMenuItem) { terminate(item, force: true) }
        func terminate(_ item: NSMenuItem, force: Bool) {
            guard let id = item.representedObject as? Int32 else { return }
            monitor.selected = id
            monitor.requestQuit(force: force)
        }
    }
}
