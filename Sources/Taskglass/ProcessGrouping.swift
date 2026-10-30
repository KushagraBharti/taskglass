import Foundation

struct ProcessFamily: Equatable {
    let id: String
    let name: String
    let members: [ProcessRow]
    let application: Bool

    var iconPath: String? { members.compactMap { ($0.application ?? processApplication($0.path))?.path }.first }
    let gpu: Double?
    let neuralMemory: UInt64?
    let ane: Double?
    let cpu: Double?
    let memory: UInt64?
    let read: Double?
    let write: Double?

    init(id: String, name: String, members: [ProcessRow], application: Bool) {
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
    func value(_ key: String) -> Double? {
        switch key {
        case "gpu": gpu
        case "ane": ane
        case "neural": neuralMemory.map { Double($0) }
        case "memory": memory.map { Double($0) }
        case "read": read
        case "write": write
        case "disk": read.flatMap { r in write.map { r + $0 } }
        default: cpu
        }
    }
}

/// Executables inside the same outer app bundle share one family, including
/// nested helper apps. Background processes remain individually identifiable.
func processFamilies(_ rows: [ProcessRow], key: String, grouped: Bool) -> [ProcessFamily] {
    var members: [String: [ProcessRow]] = [:]
    var names: [String: String] = [:]
    var applications = Set<String>()
    for row in rows {
        let id: String
        let name: String
        if key == "ane", let group = row.aneGroup {
            id = "coalition:\(group)"
            name = "Resource group \(group)"
            applications.insert(id)
        } else if grouped, let app = row.application ?? processApplication(row.path) {
            id = app.path
            name = app.name
            applications.insert(id)
        } else {
            id = "pid:\(row.id):\(row.birth)"
            name = row.name
        }
        members[id, default: []].append(row)
        names[id] = name
    }
    return members.map { id, children in
        let apps = key == "ane" ? Set(children.compactMap { ($0.application ?? processApplication($0.path))?.name }) : Set<String>()
        let title = key == "ane" && id.hasPrefix("coalition:") ? (apps.count == 1 ? apps.first! : apps.count > 1 ? "Shared: " + apps.sorted().joined(separator: ", ") : (children.first!.name + " · " + names[id]!)) : names[id]!
        return ProcessFamily(id: id, name: title, members: children.count > 1 ? children.sorted { processPrecedes($0, $1, key: key, ascending: false) } : children, application: applications.contains(id))
    }.sorted {
        let a = $0.value(key) ?? -1, b = $1.value(key) ?? -1
        if a != b { return a > b }
        return $0.id < $1.id
    }
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
