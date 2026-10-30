import Foundation

struct ProcessFamily: Equatable {
    private enum Identity: Equatable {
        case named(String)
        case process(Int32, UInt64)
        var text: String {
            switch self {
            case .named(let value): value
            case .process(let pid, let birth): "pid:\(pid):\(birth)"
            }
        }
    }
    private let identity: Identity
    var id: String { identity.text }
    let name: String
    let members: ProcessMembers
    let application: Bool

    var iconPath: String? {
        for row in members {
            if let path = row.application?.path { return path }
        }
        return nil
    }
    let gpu: Double?
    let neuralMemory: UInt64?
    let ane: Double?
    let cpu: Double?
    let memory: UInt64?
    let read: Double?
    let write: Double?

    init(id: String, name: String, members: [ProcessRow], application: Bool) {
        self.init(id: id, name: name, members: ProcessMembers(members), application: application)
    }
    init(id: String, name: String, members: ProcessMembers, application: Bool) {
        self.init(identity: .named(id), name: name, members: members, application: application)
    }
    init(process: ProcessRow, members: ProcessMembers) {
        identity = .process(process.id, process.birth); name = process.name
        self.members = members; application = false
        gpu = process.gpuTime; neuralMemory = process.neuralMemory
        ane = process.aneGroup == nil ? nil : process.aneGroupTime
        cpu = process.cpu; memory = process.footprint; read = process.readRate; write = process.writeRate
    }
    private init(identity: Identity, name: String, members: ProcessMembers, application: Bool) {
        self.identity = identity; self.name = name; self.members = members; self.application = application
        if members.count == 1, let row = members.first {
            gpu = row.gpuTime; neuralMemory = row.neuralMemory
            ane = row.aneGroup == nil ? nil : row.aneGroupTime
            cpu = row.cpu; memory = row.footprint; read = row.readRate; write = row.writeRate
            return
        }
        var gpu: Double?, neuralMemory: UInt64?, ane: Double?
        var groups = Set<UInt64>()
        var cpu: Double?, read: Double?, write: Double?, memory: UInt64?
        for row in members {
            if let value = row.gpuTime { gpu = (gpu ?? 0) + value }
            if let value = row.neuralMemory {
                let next = (neuralMemory ?? 0).addingReportingOverflow(value)
                neuralMemory = next.overflow ? UInt64.max : next.partialValue
            }
            if let group = row.aneGroup, let value = row.aneGroupTime, groups.insert(group).inserted { ane = (ane ?? 0) + value }
            if let value = row.cpu { cpu = (cpu ?? 0) + value }
            if let value = row.readRate { read = (read ?? 0) + value }
            if let value = row.writeRate { write = (write ?? 0) + value }
            if let value = row.footprint {
                let next = (memory ?? 0).addingReportingOverflow(value)
                memory = next.overflow ? UInt64.max : next.partialValue
            }
        }
        self.gpu = gpu; self.neuralMemory = neuralMemory; self.ane = ane
        self.cpu = cpu; self.memory = memory; self.read = read; self.write = write
    }
    /// Named app/resource groups retain their existing ordering. Individual
    /// ties use numeric PID/birth order without allocating a display identity.
    func precedesOnTie(_ other: ProcessFamily) -> Bool {
        switch (identity, other.identity) {
        case (.named(let a), .named(let b)): a < b
        case (.process(let a, let ab), .process(let b, let bb)): a == b ? ab < bb : a < b
        case (.named, .process): true
        case (.process, .named): false
        }
    }
    func value(_ key: String) -> Double? { value(ProcessSortKey(rawValue: key) ?? .cpu) }
    func value(_ key: ProcessSortKey) -> Double? {
        switch key {
        case .gpu: gpu
        case .ane: ane
        case .neural: neuralMemory.map { Double($0) }
        case .memory: memory.map { Double($0) }
        case .read: read
        case .write: write
        case .disk: read.flatMap { r in write.map { r + $0 } }
        default: cpu
        }
    }
}

/// Executables inside the same outer app bundle share one family, including
/// nested helper apps. Background processes remain individually identifiable.
func processFamilies(_ rows: [ProcessRow], key: String, grouped: Bool) -> [ProcessFamily] {
    enum GroupKey: Hashable {
        case application(String)
        case coalition(UInt64)
    }
    struct Bucket {
        let name: String
        var members: [Int] = []
    }
    var buckets: [GroupKey: Bucket] = [:]
    var individuals: [Int] = []
    individuals.reserveCapacity(rows.count)
    let orderKey = ProcessSortKey(rawValue: key) ?? .memory
    let valueKey = ProcessSortKey(rawValue: key) ?? .cpu
    let byANE = orderKey == .ane
    for (index, row) in rows.enumerated() {
        if byANE, let group = row.aneGroup {
            // Keep the numeric coalition ID while bucketing. Its display text
            // is needed once per group, not once for every member process.
            buckets[.coalition(group), default: Bucket(name: "")].members.append(index)
        } else if grouped, let app = row.application {
            buckets[.application(app.path), default: Bucket(name: app.name)].members.append(index)
        } else {
            individuals.append(index)
        }
    }
    // Reserve the actual output size: ANE grouping can reduce hundreds of
    // processes to a few groups, so row-count capacity would stay mostly unused.
    var families: [ProcessFamily] = []
    families.reserveCapacity(individuals.count + buckets.count)
    for index in individuals {
        let row = rows[index]
        families.append(ProcessFamily(process: row, members: ProcessMembers(source: rows, index: index)))
    }
    for (groupKey, bucket) in buckets {
        var order = bucket.members
        if order.count > 1 { order.sort { processPrecedes(rows[$0], rows[$1], key: orderKey, ascending: false) } }
        let children = ProcessMembers(source: rows, order: order)
        let id: String
        var title = bucket.name
        switch groupKey {
        case .application(let path): id = path
        case .coalition(let group):
            id = "coalition:\(group)"
            title = "Resource group \(group)"
            var apps = Set<String>()
            for row in children {
                if let name = row.application?.name { apps.insert(name) }
            }
            title = apps.count == 1 ? apps.first! : apps.count > 1 ? "Shared: " + apps.sorted().joined(separator: ", ") : rows[bucket.members.first!].name + " · " + title
        }
        families.append(ProcessFamily(id: id, name: title, members: children, application: true))
    }
    families.sort {
        let a = $0.value(valueKey) ?? -1, b = $1.value(valueKey) ?? -1
        if a != b { return a > b }
        return $0.precedesOnTie($1)
    }
    return families
}

struct ProcessApplication: Sendable, Equatable {
    let path: String
    let name: String
}
func processApplication(_ path: String?) -> ProcessApplication? {
    guard let path, let range = path.range(of: ".app/") else { return nil }
    let root = String(path[..<range.lowerBound]) + ".app"
    return ProcessApplication(path: root, name: URL(fileURLWithPath: root).deletingPathExtension().lastPathComponent)
}
