import Foundation

struct ProcessFamily: Equatable {
    let id: String
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
        self.id = id; self.name = name; self.members = members; self.application = application
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
    struct Bucket {
        var name: String
        var members: [Int] = []
        mutating func append(_ index: Int, name: String) {
            self.name = name
            members.append(index)
        }
    }
    var buckets: [String: Bucket] = [:]
    var individuals: [Int] = []
    individuals.reserveCapacity(rows.count)
    let orderKey = ProcessSortKey(rawValue: key) ?? .memory
    let valueKey = ProcessSortKey(rawValue: key) ?? .cpu
    let byANE = orderKey == .ane
    for (index, row) in rows.enumerated() {
        let id: String
        let name: String
        if byANE, let group = row.aneGroup {
            id = "coalition:\(group)"
            name = "Resource group \(group)"
        } else if grouped, let app = row.application {
            id = app.path
            name = app.name
        } else {
            individuals.append(index)
            continue
        }
        // Mutate through the dictionary's modify accessor, without copying a
        // growing member array or maintaining separate title/application maps.
        buckets[id, default: Bucket(name: name)].append(index, name: name)
    }
    // Reserve the actual output size: ANE grouping can reduce hundreds of
    // processes to a few groups, so row-count capacity would stay mostly unused.
    var families: [ProcessFamily] = []
    families.reserveCapacity(individuals.count + buckets.count)
    for index in individuals {
        let row = rows[index]
        families.append(ProcessFamily(id: "pid:\(row.id):\(row.birth)", name: row.name, members: ProcessMembers(source: rows, index: index), application: false))
    }
    for (id, bucket) in buckets {
        var order = bucket.members
        if order.count > 1 { order.sort { processPrecedes(rows[$0], rows[$1], key: orderKey, ascending: false) } }
        let children = ProcessMembers(source: rows, order: order)
        var title = bucket.name
        if byANE && id.hasPrefix("coalition:") {
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
        return $0.id < $1.id
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
