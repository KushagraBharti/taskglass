import SwiftUI
import AppKit

/// A virtualized native outline: all processes remain available without building
/// hundreds of SwiftUI row trees.
///
/// Items are positional slots whose contents change each sample, like the main table's rows.
/// A re-ranking therefore rewrites on-screen cells in place instead of reloading the outline.
/// Expansion and selection follow application/process identity, not slot position: when a slot's
/// contents move, only that slot is expanded, collapsed or has its children reloaded. A full reload
/// happens only on first display and when grouping is switched.
///
/// The ranking is always descending and has no ascending form, so columns carry no sort descriptors
/// (and no sort arrow); a header click ranks by that column.
struct ResourceProcessTable: NSViewRepresentable {
    let monitor: Monitor
    /// Rows visible without scrolling. The rest of the list scrolls inside the table.
    static let visibleRows = 12
    func makeCoordinator() -> Coordinator { Coordinator(monitor) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = ProcessOutlineView()
        TableKit.install([
            .init(key: "name", title: "Name", width: 300, minWidth: 180, sortable: false),
            .init(key: "pid", title: "PID", width: 64, minWidth: 52, sortable: false),
            .init(key: "cpu", title: "CPU", width: 96, minWidth: 88, sortable: false, help: TableKit.cpuHelp + " Click to rank by CPU."),
            .init(key: "memory", title: "Memory", width: 104, minWidth: 94, sortable: false, help: TableKit.memoryHelp + " Click to rank by memory."),
            .init(key: "gpu", title: "GPU time", width: 128, minWidth: 116, sortable: false, help: TableKit.gpuHelp),
            .init(key: "ane", title: "ANE group time", width: 144, minWidth: 132, sortable: false, help: TableKit.aneHelp),
            .init(key: "neural", title: "Neural memory", width: 128, minWidth: 116, sortable: false, help: TableKit.neuralHelp),
            .init(key: "read", title: "Read/s", width: 108, minWidth: 96, sortable: false, help: TableKit.diskHelp + " Click to rank by disk reads."),
            .init(key: "write", title: "Write/s", width: 108, minWidth: 96, sortable: false, help: TableKit.diskHelp + " Click to rank by disk writes."),
            .init(key: "disk", title: "Total I/O", width: 108, minWidth: 96, sortable: false, help: TableKit.diskHelp)
        ], in: table)
        table.tableColumns.last?.isHidden = true
        table.outlineTableColumn = table.tableColumns.first
        table.style = .inset; table.indentationPerLevel = 14
        table.indentationMarkerFollowsCell = false
        table.backgroundColor = NSColor(white: 0.035, alpha: 1)
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.inspectClicked)
        table.onReturn = { [weak coordinator = context.coordinator] in coordinator?.inspectSelected() }
        table.setAccessibilityLabel("Processes")
        let menu = NSMenu(); menu.delegate = context.coordinator; table.menu = menu
        let scroll = TableKit.scrollView(for: table)
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.update() }
    /// Header plus a whole number of rows, from the table's own geometry, so no row is cut in half.
    /// Before the first row exists, the inset style's measured 32 pt header and 28 pt pitch stand in.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: context.coordinator.viewportHeight)
    }

    /// One outline row position. Its contents are replaced every sample.
    @MainActor final class Slot: NSObject {
        let isChild: Bool
        var title = ""
        var process: ProcessRow?
        var family: ProcessFamily?
        var children: [Slot] = []
        /// Child slots no longer shown. An NSOutlineView doesn't retain its items and can keep a collapsed
        /// item's old children cached, so slots are kept for reuse rather than released. Bounded by the
        /// largest member count this slot has shown.
        private var spare: [Slot] = []
        init(child: Bool) { isChild = child }
        /// Identity of what the slot currently shows: the app bundle path, or the process's PID and start time.
        var contentID: String { family?.id ?? process.map { "pid:\($0.id):\($0.birth)" } ?? "" }
        var expandable: Bool { family != nil }
        var gpu: Double? { process?.gpuTime ?? family?.gpu }
        var neural: UInt64? { process?.neuralMemory ?? family?.neuralMemory }
        var ane: Double? { isChild ? nil : family?.ane }
        var cpu: Double? { process?.cpu ?? family?.cpu }
        var memory: UInt64? { process?.footprint ?? family?.memory }
        var read: Double? { process?.readRate ?? family?.read }
        var write: Double? { process?.writeRate ?? family?.write }
        func value(_ key: String) -> Double? {
            switch key {
            case "gpu": gpu
            case "ane": ane
            case "neural": neural.map { Double($0) }
            case "cpu": cpu
            case "memory": memory.map { Double($0) }
            case "read": read
            case "write": write
            case "disk": read.flatMap { r in write.map { r + $0 } }
            default: nil
            }
        }
        func show(_ family: ProcessFamily) {
            title = family.name
            if family.application {
                self.family = family; process = nil
                resize(to: family.members.count)
                for (child, row) in zip(children, family.members) { child.title = row.name; child.process = row }
            } else {
                self.family = nil; process = family.members.first
                resize(to: 0)
            }
        }
        // AppKit may retain an item's identity in its outline cache, so keep the
        // lightweight slot but release process snapshots and paths when recycled.
        func releaseContents() {
            title = ""; process = nil; family = nil
            for child in children { child.releaseContents() }
        }
        private func resize(to count: Int) {
            while children.count > count {
                let child = children.removeLast()
                child.releaseContents()
                spare.append(child)
            }
            while children.count < count { children.append(spare.popLast() ?? Slot(child: true)) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        let monitor: Monitor
        weak var table: ProcessOutlineView?
        var roots: [Slot] = []
        /// Root slots past the current count, kept alive for the same reason as `Slot.spare`.
        private var spareRoots: [Slot] = []
        /// What the outline was last told about each root: whether it has a disclosure triangle, and its member count.
        var delivered: [(expandable: Bool, children: Int)] = []
        var expandedIDs = Set<String>()
        var selectedID: String?
        var needsReload = true
        var previous: [ProcessRow] = []
        var previousKey = ""
        var previousGrouped: Bool?
        var maximum = 1.0
        var updating = false
        /// Measured once rows exist; see `sizeThatFits`.
        var viewportHeight: CGFloat = 32 + CGFloat(ResourceProcessTable.visibleRows) * TableKit.rowHeight
        private var measured = false
        private let placeholder = Slot(child: true)
        init(_ monitor: Monitor) { self.monitor = monitor }

        func update() {
            guard let table else { return }
            let rows = monitor.resourceLeaders, key = monitor.resourceSort, grouped = monitor.resourceSort == "ane" || monitor.resourceGrouped
            guard rows != previous || key != previousKey || grouped != previousGrouped else { return }
            updating = true
            defer { updating = false }

            let families = processFamilies(rows, key: key, grouped: grouped)
            let oldCount = roots.count
            while roots.count > families.count {
                let slot = roots.removeLast()
                slot.releaseContents()
                spareRoots.append(slot)
            }
            while roots.count < families.count { roots.append(spareRoots.popLast() ?? Slot(child: false)) }
            for (slot, family) in zip(roots, families) { slot.show(family) }
            maximum = max(1e-9, roots.lazy.compactMap { $0.value(key) }.max() ?? 1)
            // Expansion is remembered across re-ranks and brief absences, but not for every app ever opened.
            if expandedIDs.count > 64 { expandedIDs.formIntersection(roots.map(\.contentID)) }

            if needsReload || grouped != previousGrouped || (key == "ane") != (previousKey == "ane") {
                // Grouping changes every row's shape; one reload, then expansion follows identity.
                table.reloadData()
                for slot in roots {
                    let want = wantsExpansion(slot)
                    if table.isItemExpanded(slot) != want { if want { table.expandItem(slot) } else { table.collapseItem(slot) } }
                    if want { reconcileChildren(slot) }
                }
                needsReload = false
            } else {
                // Processes that start or exit change the row count at the tail; existing rows are reused.
                if roots.count > oldCount { table.insertItems(at: IndexSet(oldCount..<roots.count), inParent: nil, withAnimation: []) }
                else if roots.count < oldCount { table.removeItems(at: IndexSet(roots.count..<oldCount), inParent: nil, withAnimation: []) }
                // Only slots whose shape changed are touched: an expanded application that moved rank,
                // a group that gained or lost members, or a row that became or stopped being a group.
                for (index, slot) in roots.enumerated() {
                    let want = wantsExpansion(slot), expanded = table.isItemExpanded(slot)
                    let known = index < oldCount ? delivered[index] : nil
                    if expanded && !want { table.collapseItem(slot) }
                    // Refresh the disclosure triangle before any expansion, which depends on it.
                    if let known, known.expandable != slot.expandable { table.reloadItem(slot, reloadChildren: false) }
                    if want && !expanded { table.expandItem(slot); reconcileChildren(slot) }
                    else if want && known?.children != slot.children.count { table.reloadItem(slot, reloadChildren: true) }
                }
                TableKit.refreshVisible(table) { cell, column, row in
                    if let slot = table.item(atRow: row) as? Slot { configure(cell, key: column, slot: slot) }
                }
            }
            delivered = roots.map { ($0.expandable, $0.children.count) }
            var columnsChanged = false
            for column in table.tableColumns {
                let columnKey = column.identifier.rawValue
                let acceleratorPane = monitor.pane == .gpu || monitor.pane == .neural
                let hidden: Bool
                switch columnKey {
                case "gpu": hidden = monitor.pane != .gpu && key != "gpu"
                case "ane": hidden = key != "ane"
                case "neural": hidden = monitor.pane != .neural && key != "neural"
                case "disk": hidden = key != "disk"
                case "read", "write": hidden = acceleratorPane && key != columnKey && key != "disk"
                default: continue
                }
                if column.isHidden != hidden { column.isHidden = hidden; columnsChanged = true }
            }
            if columnsChanged { TableKit.fitVisibleColumns(table) }
            if key != previousKey { markRanking(key) }
            restoreSelection()
            previous = rows; previousKey = key; previousGrouped = grouped
            measureViewport()
        }

        /// Header height plus the style's top inset plus whole rows, read from the live table once.
        private func measureViewport() {
            guard !measured, let table, table.numberOfRows > 0 else { return }
            measured = true
            let header = table.headerView?.frame.height ?? 28
            let pitch = table.rowHeight + table.intercellSpacing.height
            let height = (header + max(0, table.rect(ofRow: 0).minY) + CGFloat(ResourceProcessTable.visibleRows) * pitch).rounded()
            if height != viewportHeight { viewportHeight = height; table.enclosingScrollView?.invalidateIntrinsicContentSize() }
        }
        func wantsExpansion(_ slot: Slot) -> Bool { slot.expandable && expandedIDs.contains(slot.contentID) }

        /// A collapsed slot can keep children cached from an earlier expansion while its contents change.
        /// After any expansion, make sure the rows shown are exactly the slot's current members.
        func reconcileChildren(_ slot: Slot) {
            guard let table, table.isItemExpanded(slot) else { return }
            let fresh = table.numberOfChildren(ofItem: slot) == slot.children.count
                && slot.children.indices.allSatisfy { (table.child($0, ofItem: slot) as? Slot) === slot.children[$0] }
            if !fresh { table.reloadItem(slot, reloadChildren: true) }
        }

        /// Selection follows content across re-ranking, including when a re-rank temporarily
        /// collapses its group. Manual collapse keeps AppKit's native selection behavior.
        func restoreSelection() {
            guard let table else { return }
            var target: Slot?
            if let selectedID {
                for slot in roots {
                    if slot.contentID == selectedID { target = slot; break }
                    if table.isItemExpanded(slot), let child = slot.children.first(where: { $0.contentID == selectedID }) { target = child; break }
                }
            }
            let row = target.map { table.row(forItem: $0) } ?? -1
            if row >= 0 { if table.selectedRow != row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } }
            else if table.selectedRow >= 0 { table.deselectAll(nil) }
        }

        /// The ranking is always descending, so the header carries emphasis rather than an arrow
        /// that would push its title out of line with the values below.
        func markRanking(_ key: String) {
            guard let table else { return }
            for column in table.tableColumns {
                table.setIndicatorImage(nil, in: column)
                let ranked = column.identifier.rawValue == key
                let cell = column.headerCell
                let size = cell.font?.pointSize ?? NSFont.smallSystemFontSize
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = cell.alignment
                cell.attributedStringValue = NSAttributedString(string: column.title, attributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: ranked ? .semibold : .regular),
                    .foregroundColor: ranked ? NSColor.labelColor : NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph
                ])
            }
            table.headerView?.needsDisplay = true
        }

        // MARK: Data source and delegate

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Slot)?.children.count ?? (item == nil ? roots.count : 0)
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            let list = (item as? Slot)?.children ?? roots
            return list.indices.contains(index) ? list[index] : placeholder
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Slot)?.expandable ?? false }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let column = tableColumn, let slot = item as? Slot else { return nil }
            let cell = outlineView.makeView(withIdentifier: column.identifier, owner: self) as? ProcessCell ?? ProcessCell(key: column.identifier.rawValue)
            configure(cell, key: column.identifier.rawValue, slot: slot)
            return cell
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            selectedID = (table.item(atRow: table.selectedRow) as? Slot)?.contentID
        }
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !updating, let slot = notification.userInfo?["NSObject"] as? Slot, let index = roots.firstIndex(of: slot) else { return }
            expandedIDs.insert(slot.contentID)
            delivered[index].children = slot.children.count
            // Checked after the expansion finishes, outside the notification.
            Task { @MainActor [weak self] in self?.reconcileChildren(slot) }
        }
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !updating, let slot = notification.userInfo?["NSObject"] as? Slot else { return }
            expandedIDs.remove(slot.contentID)
        }

        func configure(_ cell: ProcessCell, key: String, slot: Slot) {
            switch key {
            case "name":
                if slot.family != nil {
                    cell.showGroup(slot.title, count: slot.children.count)
                    cell.setIcon(slot.family.flatMap { family in family.iconPath.map { ProcessIcons.icon(forBundle: $0) } ?? family.members.first.map(ProcessIcons.icon(for:)) })
                } else {
                    cell.show(slot.title)
                    // Helpers sit under their application's icon; repeating it on each would be noise.
                    cell.setIcon(slot.isChild ? nil : slot.process.map(ProcessIcons.icon(for:)))
                }
                let tip = slot.family != nil
                    ? "\(slot.title): \(slot.children.count) \(slot.children.count == 1 ? "process" : "processes"). Values add up members; shared memory can be counted more than once."
                    : slot.process?.path ?? slot.title
                if cell.toolTip != tip { cell.toolTip = tip }
                return
            case "pid":
                // A group has no PID; a blank cell, not a dash, since nothing is missing.
                cell.show(slot.process.map { String($0.id) } ?? "", quiet: true)
            case "cpu": cell.showMeasurement(.percentage(slot.cpu), quiet: (slot.cpu ?? 1) < 0.05)
            case "gpu": cell.showMeasurement(.gpuTime(slot.gpu), quiet: slot.gpu == 0)
            case "ane":
                if slot.isChild { cell.show("group", quiet: true) }
                else { cell.showMeasurement(.gpuTime(slot.ane), quiet: slot.ane == 0) }
            case "neural": cell.showMeasurement(.byteCount(slot.neural), quiet: slot.neural == 0)
            case "memory": cell.showMeasurement(.byteCount(slot.memory))
            case "read": cell.showMeasurement(.byteRate(slot.read), quiet: slot.read == 0)
            case "write": cell.showMeasurement(.byteRate(slot.write), quiet: slot.write == 0)
            default: cell.showMeasurement(.byteRate(slot.value("disk")), quiet: slot.value("disk") == 0)
            }
            let ranked = key == monitor.resourceSort
            cell.setBar(ranked ? slot.value(key).map { $0 / maximum } : nil, tint: tint(key))
        }
        func tint(_ key: String) -> NSColor {
            key == "gpu" ? Palette.gpuNS : ["ane", "neural"].contains(key) ? Palette.neuralNS : key == "memory" ? Palette.memoryNS : key == "cpu" ? Palette.cpuNS : Palette.storageNS
        }

        /// A measurement header ranks by that column, the same as the Rank by menu (and remembered per page).
        /// Name and PID aren't rankings, so clicking them does nothing.
        func outlineView(_ outlineView: NSOutlineView, didClick tableColumn: NSTableColumn) {
            let key = tableColumn.identifier.rawValue
            guard ResourceProcesses.rankings.contains(where: { $0.key == key }), key != monitor.resourceSort else { return }
            // The monitor remembers it for this page; update() re-sorts and marks the header once it arrives.
            monitor.resourceSort = key
        }

        // MARK: Actions

        @objc func inspectClicked() { activate(row: table?.clickedRow ?? -1) }
        func inspectSelected() { activate(row: table?.selectedRow ?? -1) }
        /// A process opens in Processes with the inspector; an application group expands or collapses.
        func activate(row: Int) {
            guard let table, row >= 0, let slot = table.item(atRow: row) as? Slot else { return }
            if let process = slot.process { monitor.openProcess(process) }
            else if table.isItemExpanded(slot) { table.collapseItem(slot) }
            else { table.expandItem(slot) }
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, table.clickedRow >= 0, let slot = table.item(atRow: table.clickedRow) as? Slot else { return }
            if let process = slot.process {
                menu.addItem("Show in Processes", target: self, action: #selector(showInProcesses(_:)), represented: process)
                if let path = process.path { menu.addItem("Show in Finder", target: self, action: #selector(reveal(_:)), represented: path) }
            } else if let family = slot.family {
                menu.addItem(table.isItemExpanded(slot) ? "Collapse" : "Expand", target: self, action: #selector(toggle(_:)), represented: slot)
                if let path = family.iconPath { menu.addItem("Show in Finder", target: self, action: #selector(reveal(_:)), represented: path) }
            }
            menu.addItem(.separator())
            menu.addItem("Copy Name", target: self, action: #selector(copyName(_:)), represented: slot.title)
        }
        @objc func showInProcesses(_ item: NSMenuItem) { if let process = item.representedObject as? ProcessRow { monitor.openProcess(process) } }
        @objc func toggle(_ item: NSMenuItem) {
            guard let table, let slot = item.representedObject as? Slot else { return }
            if table.isItemExpanded(slot) { table.collapseItem(slot) } else { table.expandItem(slot) }
        }
        @objc func reveal(_ item: NSMenuItem) { if let path = item.representedObject as? String { revealInFinder(path) } }
        @objc func copyName(_ item: NSMenuItem) { if let name = item.representedObject as? String { copyToPasteboard(name) } }
    }
}
