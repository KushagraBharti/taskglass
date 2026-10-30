import AppKit
import UniformTypeIdentifiers

/// Shared geometry, type and cells for both native process tables, so the Processes page
/// and every resource page read as one system.
@MainActor enum TableKit {
    static let rowHeight: CGFloat = 28
    static let nameFont = NSFont.systemFont(ofSize: 12)
    static let groupFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    static let countFont = NSFont.systemFont(ofSize: 11)
    static let gridColor = NSColor.white.withAlphaComponent(0.055)

    struct Column {
        let key: String
        let title: String
        let width: CGFloat
        let minWidth: CGFloat
        var sortable = true
        var help: String?
    }

    /// The name column absorbs width changes. Once every column is at its minimum, the table scrolls sideways.
    static func install(_ columns: [Column], in table: NSTableView, ascendingKeys: Set<String> = []) {
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.key))
            column.title = spec.title; column.width = spec.width; column.minWidth = spec.minWidth
            column.headerCell.alignment = isText(spec.key) ? .left : .right
            column.headerToolTip = spec.help
            if spec.sortable { column.sortDescriptorPrototype = NSSortDescriptor(key: spec.key, ascending: ascendingKeys.contains(spec.key)) }
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = rowHeight
        table.usesAlternatingRowBackgroundColors = false
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = gridColor
        table.allowsColumnReordering = false
        // Header clicks sort or rank; they never select a whole column.
        table.allowsColumnSelection = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
    }

    static func scrollView(for table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        return scroll
    }

    /// AppKit can retain a formerly stretched name width when columns are hidden.
    /// Refit against the viewport, preserving metric widths and horizontal scrolling.
    static func fitVisibleColumns(_ table: NSTableView) {
        guard let first = table.tableColumns.first, let clip = table.enclosingScrollView?.contentView, clip.bounds.width > 0 else { return }
        let visible = table.tableColumns.filter { !$0.isHidden }
        let otherWidth = visible.dropFirst().reduce(CGFloat(0)) { $0 + $1.width }
        let gaps = CGFloat(visible.count) * table.intercellSpacing.width
        first.width = max(first.minWidth, clip.bounds.width - otherWidth - gaps)
        let width = max(clip.bounds.width, first.width + otherWidth + gaps)
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
    }

    /// Reconfigures only the cells already on screen; never rebuilds row views.
    static func refreshVisible(_ table: NSTableView, configure: (ProcessCell, String, Int) -> Void) {
        let range = table.rows(in: table.visibleRect)
        guard range.location != NSNotFound, range.length > 0 else { return }
        let end = min(table.numberOfRows, range.location + range.length)
        guard range.location < end else { return }
        for row in range.location..<end {
            for (index, column) in table.tableColumns.enumerated() where !column.isHidden {
                if let cell = table.view(atColumn: index, row: row, makeIfNecessary: false) as? ProcessCell {
                    configure(cell, column.identifier.rawValue, row)
                }
            }
        }
    }

    static let cpuHelp = "100% equals one fully used core. A process can exceed 100%."
    static let footprintHelp = "Physical footprint. A dash means macOS denied access."
    static let memoryHelp = footprintHelp + " Application rows add up their members; shared memory can be counted more than once."
    /// Columns whose content is words rather than measurements.
    static func isText(_ key: String) -> Bool { key == "name" || key == "uid" }
    static let gpuHelp = "Driver-observed GPU execution time in milliseconds per second. Overlapping contexts can exceed 1,000 ms/s. This is not device utilization. A dash means no stable readable client counter. Short-lived clients may be missed."
    static let neuralHelp = "Memory charged to this process for Neural Engine use. An allocation does not mean the Neural Engine is currently computing. A dash means unavailable."
    static let aneHelp = "Kernel-accounted Neural Engine time in milliseconds per second for an OS resource group. An app and its helpers share one counter, counted once. This is not individual-process utilization. Available on recognized macOS 27 counter layouts."
    static let diskHelp = "Physical disk I/O. Reads served from the file cache are not included."
}

/// Icon, text and an optional relative bar. One class serves every column of both tables.
@MainActor final class ProcessCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()
    let bar = MeterBar()
    private var renderedKey = ""
    private let baseFont: NSFont

    init(key: String) {
        baseFont = key == "name" ? TableKit.nameFont : TableKit.numberFont
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier(key)
        label.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let name = key == "name"
        label.alignment = TableKit.isText(key) ? .left : .right
        label.font = baseFont
        addSubview(label); textField = label
        if name {
            addSubview(icon); imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else if TableKit.isText(key) {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            // Measurements: right-aligned to the header's edge, with room for the ranking bar on the left.
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), bar.widthAnchor.constraint(equalToConstant: 28),
                bar.heightAnchor.constraint(equalToConstant: 3), bar.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: key == "pid" ? 6 : 38),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Plain value. Missing measurements read as a tertiary dash; quiet values as secondary.
    func show(_ value: String, quiet: Bool = false) {
        if renderedKey != "" {
            // Coming back from an attributed group title: restore the column's plain type.
            renderedKey = ""; label.font = baseFont; label.stringValue = value
        } else if label.stringValue != value { label.stringValue = value }
        let color: NSColor = value == "—" ? .tertiaryLabelColor : quiet ? .secondaryLabelColor : .labelColor
        if label.textColor != color { label.textColor = color }
    }
    /// Application name with its member count set smaller and quieter, rebuilt only when either changes.
    /// A single-process application shows just its name; the disclosure triangle already says it has members.
    func showGroup(_ title: String, count: Int) {
        let key = "\(title)\u{0}\(count)"
        guard renderedKey != key else { return }
        renderedKey = key
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
        let text = NSMutableAttributedString(string: title, attributes: [.font: TableKit.groupFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
        if count > 1 {
            text.append(NSAttributedString(string: "  \(count) processes", attributes: [.font: TableKit.countFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]))
        }
        label.attributedStringValue = text
    }
    func setIcon(_ image: NSImage?) {
        if icon.image !== image { icon.image = image }
        if icon.isHidden != (image == nil) { icon.isHidden = image == nil }
    }
    func setBar(_ fraction: Double?, tint: NSColor) {
        bar.update(fraction: fraction, tint: tint)
    }
}

/// Relative level drawn once per change. A nil fraction hides the bar and its track.
@MainActor final class MeterBar: NSView {
    private var fraction: Double?
    private var tint = NSColor.controlAccentColor
    func update(fraction next: Double?, tint nextTint: NSColor) {
        let rounded = next.map { ($0 * 200).rounded() / 200 }
        guard rounded != fraction || nextTint != tint else { return }
        fraction = rounded; tint = nextTint
        isHidden = rounded == nil
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let fraction, fraction.isFinite else { return }
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
        tint.setFill()
        let width = max(fraction > 0 ? 1.5 : 0, bounds.width * min(1, max(0, fraction)))
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// App bundle icons, looked up once per bundle. Non-app executables share the generic icon.
@MainActor enum ProcessIcons {
    private static var cache: [String: NSImage] = [:]
    static let executable: NSImage = thumbnail(NSWorkspace.shared.icon(for: .unixExecutable))
    /// Uses the sampler's cached outer-app identity, the same one that groups processes.
    static func icon(for row: ProcessRow) -> NSImage { row.application.map { icon(forBundle: $0.path) } ?? executable }
    static func icon(forBundle path: String) -> NSImage {
        if let image = cache[path] { return image }
        let image = thumbnail(NSWorkspace.shared.icon(forFile: path))
        if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
        cache[path] = image
        return image
    }
    /// Keep only the largest size used by the UI (40 pt at 2x), not every
    /// representation of another app's icon. 256 cached bitmaps use at most
    /// about 6.3 MiB of pixel data, including icons inspected after scrolling.
    private static func thumbnail(_ source: NSImage) -> NSImage {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 320, bitsPerPixel: 32),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: 80, height: 80), from: .zero,
                    operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 40, height: 40))
        image.addRepresentation(bitmap)
        return image
    }
}

/// Account names for user IDs. Directory lookups can block (network accounts, a cold opendirectoryd),
/// so each UID is resolved once on a background queue; until then the numeric UID stands in.
/// `didResolve` lets on-screen cells replace the number when the name arrives.
@MainActor enum UserNames {
    static let didResolve = Notification.Name("TaskglassUserNameResolved")
    /// An empty string records a UID the directory doesn't know, so it isn't looked up again.
    private static var cache: [UInt32: String] = [:]
    private static var pending = Set<UInt32>()
    private static let queue = DispatchQueue(label: "io.github.kushagrabharti.taskglass.user-names", qos: .utility)

    /// The account name, or the UID while the name is unresolved or unknown.
    static func name(_ uid: UInt32) -> String { resolved(uid) ?? String(uid) }
    /// The account name only once it is known; nil while pending or if the directory has none.
    static func resolved(_ uid: UInt32) -> String? {
        if let name = cache[uid] { return name.isEmpty ? nil : name }
        guard pending.count < 32, pending.insert(uid).inserted else { return nil }
        queue.async {
            let name = lookup(uid)
            Task { @MainActor in
                pending.remove(uid)
                if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
                cache[uid] = name ?? ""
                if name != nil { NotificationCenter.default.post(name: didResolve, object: nil) }
            }
        }
        return nil
    }
    /// Reentrant variant: `getpwuid` shares a static buffer and isn't safe off the main thread.
    nonisolated private static func lookup(_ uid: UInt32) -> String? {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 2048)
        guard getpwuid_r(uid, &entry, &buffer, buffer.count, &result) == 0, result != nil, let name = entry.pw_name else { return nil }
        return String(cString: name)
    }
}

/// Return opens the selected row, matching double-click.
final class ProcessTableView: NSTableView {
    private var viewportWidth: CGFloat = -1
    override func layout() {
        super.layout()
        let width = enclosingScrollView?.contentView.bounds.width ?? 0
        if width != viewportWidth { viewportWidth = width; TableKit.fitVisibleColumns(self) }
    }
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, let onReturn { onReturn() } else { super.keyDown(with: event) }
    }
}
final class ProcessOutlineView: NSOutlineView {
    private var viewportWidth: CGFloat = -1
    override func layout() {
        super.layout()
        let width = enclosingScrollView?.contentView.bounds.width ?? 0
        if width != viewportWidth { viewportWidth = width; TableKit.fitVisibleColumns(self) }
    }
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, let onReturn { onReturn() } else { super.keyDown(with: event) }
    }
}

extension NSMenu {
    @discardableResult func addItem(_ title: String, target: AnyObject, action: Selector, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target; item.representedObject = represented
        addItem(item)
        return item
    }
}

@MainActor func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}
@MainActor func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
}
