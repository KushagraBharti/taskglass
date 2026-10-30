import Foundation

/// Stable native outline identities. A child stores only its parent and index;
/// its current process comes from the family's shared snapshot.
@MainActor class ProcessOutlineItem: NSObject {
    var isChild: Bool { false }
    var process: ProcessRow? { nil }
    var family: ProcessFamily? { nil }
    var title: String { process?.name ?? family?.name ?? "" }
    var contentID: String { process.map { "pid:\($0.id):\($0.birth)" } ?? family?.id ?? "" }
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
}

@MainActor final class ProcessOutlineRoot: ProcessOutlineItem {
    private var entry: ProcessFamily?
    private var children: [ProcessOutlineChild] = []
    override var title: String { entry?.name ?? "" }
    override var contentID: String { entry?.id ?? "" }
    override var family: ProcessFamily? { entry?.application == true ? entry : nil }
    override var process: ProcessRow? { entry?.application == false ? entry?.members.first : nil }
    var childCount: Int { entry?.application == true ? entry?.members.count ?? 0 : 0 }

    func show(_ family: ProcessFamily) {
        entry = family
        // NSOutlineView strongly retains any identities it still caches. Keep
        // only the current children here; removed identities remain valid until
        // AppKit reconciles its cache, without retaining old process snapshots.
        let count = childCount
        if count == 0 { children.removeAll() }
        else if children.count > count { children.removeLast(children.count - count) }
    }

    func releaseContents() {
        entry = nil
        children.removeAll()
    }

    func child(at index: Int) -> ProcessOutlineChild? {
        guard index >= 0, index < childCount else { return nil }
        // Collapsed groups need no child objects. AppKit asks for them when it
        // expands the group; unchanged children are reused across samples.
        while children.count <= index {
            children.append(ProcessOutlineChild(parent: self, index: children.count))
        }
        return children[index]
    }

    func child(matching id: String) -> ProcessOutlineChild? {
        guard let members = family?.members else { return nil }
        for (index, row) in members.enumerated() where "pid:\(row.id):\(row.birth)" == id {
            return child(at: index)
        }
        return nil
    }

    fileprivate func process(at index: Int) -> ProcessRow? {
        guard let entry, entry.application, entry.members.indices.contains(index) else { return nil }
        return entry.members[index]
    }
}

@MainActor final class ProcessOutlineChild: ProcessOutlineItem {
    private weak var parent: ProcessOutlineRoot?
    private let index: Int
    init(parent: ProcessOutlineRoot, index: Int) { self.parent = parent; self.index = index }
    override var isChild: Bool { true }
    override var process: ProcessRow? { parent?.process(at: index) }
}
