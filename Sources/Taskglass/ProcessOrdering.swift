import Foundation

enum ProcessSortKey: String {
    case name, pid, cpu, memory, resident, threads, gpu, ane, neural, disk, read, write, uid
}

func processPrecedes(_ a: ProcessRow, _ b: ProcessRow, key: String, ascending: Bool) -> Bool {
    processPrecedes(a, b, key: ProcessSortKey(rawValue: key) ?? .memory, ascending: ascending)
}

func processPrecedes(_ a: ProcessRow, _ b: ProcessRow, key: ProcessSortKey, ascending: Bool) -> Bool {
    let comparison: Bool
    switch key {
    case .name:
        let order = a.name.localizedStandardCompare(b.name)
        comparison = order == .orderedSame ? a.id < b.id : order == .orderedAscending
    case .pid: comparison = a.id < b.id
    case .neural:
        let av = OptionalCounter(a.neuralMemory), bv = OptionalCounter(b.neuralMemory)
        comparison = av == bv ? a.id < b.id : av < bv
    case .gpu, .ane:
        func value(_ p: ProcessRow) -> Double { key == .gpu ? p.gpuTime ?? -1 : p.aneGroupTime ?? -1 }
        comparison = value(a) == value(b) ? a.id < b.id : value(a) < value(b)
    case .cpu: comparison = (a.cpu ?? -1) == (b.cpu ?? -1) ? a.id < b.id : (a.cpu ?? -1) < (b.cpu ?? -1)
    case .uid: comparison = a.uid == b.uid ? a.id < b.id : a.uid < b.uid
    case .disk:
        let av = a.readRate.flatMap { r in a.writeRate.map { r + $0 } } ?? -1
        let bv = b.readRate.flatMap { r in b.writeRate.map { r + $0 } } ?? -1
        comparison = av == bv ? a.id < b.id : av < bv
    case .read: comparison = (a.readRate ?? -1) == (b.readRate ?? -1) ? a.id < b.id : (a.readRate ?? -1) < (b.readRate ?? -1)
    case .write: comparison = (a.writeRate ?? -1) == (b.writeRate ?? -1) ? a.id < b.id : (a.writeRate ?? -1) < (b.writeRate ?? -1)
    case .resident: comparison = a.resident == b.resident ? a.id < b.id : a.resident < b.resident
    case .threads: comparison = a.threads == b.threads ? a.id < b.id : a.threads < b.threads
    default: comparison = (a.footprint ?? 0) == (b.footprint ?? 0) ? a.id < b.id : (a.footprint ?? 0) < (b.footprint ?? 0)
    }
    return ascending ? comparison : (a.id == b.id ? false : !comparison)
}

/// Preserve the full integer range and keep unavailable below a measured zero.
struct OptionalCounter: Comparable {
    let available: Bool
    let value: UInt64
    init(_ value: UInt64?) { available = value != nil; self.value = value ?? 0 }
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.available == rhs.available ? lhs.value < rhs.value : !lhs.available
    }
}

/// Cache numeric keys once and sort compact indexes. Keep integer memory
/// counters exact, including values beyond Double's integral precision.
func sortProcesses(_ rows: inout [ProcessRow], key: ProcessSortKey, ascending: Bool) {
    // A tiny search result is cheaper to sort directly. Text/PID sorts often
    // arrive in long existing runs and don't need numeric key extraction.
    guard rows.count > 64, key != .name, key != .pid else {
        rows.sort { processPrecedes($0, $1, key: key, ascending: ascending) }
        return
    }
    let tie: (ProcessRow, ProcessRow) -> Bool = { ascending ? $0.id < $1.id : $0.id > $1.id }
    switch key {
    case .memory, .resident:
        sortByCachedKey(&rows, ascending: ascending, key: { key == .memory ? $0.footprint ?? 0 : $0.resident }, tie: tie)
    case .threads, .uid:
        sortByCachedKey(&rows, ascending: ascending, key: { key == .threads ? $0.threads : $0.uid }, tie: tie)
    case .neural:
        sortByCachedKey(&rows, ascending: ascending, key: { OptionalCounter($0.neuralMemory) }, tie: tie)
    case .cpu, .gpu, .ane, .read, .write, .disk:
        sortByCachedKey(&rows, ascending: ascending, key: { row -> Double in
            switch key {
            case .cpu: row.cpu ?? -1
            case .gpu: row.gpuTime ?? -1
            case .ane: row.aneGroupTime ?? -1
            case .read: row.readRate ?? -1
            case .write: row.writeRate ?? -1
            default: row.readRate.flatMap { read in row.writeRate.map { read + $0 } } ?? -1
            }
        }, tie: tie)
    case .name, .pid: break // Handled by the direct-sort path above.
    }
}

/// Missing measurements do not compete with a real zero. Ranking stays independent
/// of the process table's search/filter and is recomputed only after a sample.
func rankedProcesses(_ rows: [ProcessRow], key: String, limit: Int) -> [ProcessRow] {
    guard limit > 0 else { return [] }
    let order = ProcessSortKey(rawValue: key) ?? .memory
    // Filter while selecting the small leader set; do not copy every measured row.
    let measured = rows.lazy.filter {
        switch order {
        case .gpu: return $0.gpuTime != nil
        case .ane: return $0.aneGroupTime != nil
        case .neural: return $0.neuralMemory != nil
        case .cpu: return $0.cpu != nil
        case .read: return $0.readRate != nil
        case .write: return $0.writeRate != nil
        case .disk: return $0.readRate != nil && $0.writeRate != nil
        default: return $0.footprint != nil
        }
    }
    if limit <= 8 {
        var best: [ProcessRow] = []
        best.reserveCapacity(limit)
        for row in measured {
            if best.count == limit, let last = best.last, !processPrecedes(row, last, key: order, ascending: false) { continue }
            let position = best.firstIndex { processPrecedes(row, $0, key: order, ascending: false) } ?? best.endIndex
            best.insert(row, at: position)
            if best.count > limit { best.removeLast() }
        }
        return best
    }
    return Array(measured.sorted { processPrecedes($0, $1, key: order, ascending: false) }.prefix(limit))
}
