import Foundation

func processPrecedes(_ a: ProcessRow, _ b: ProcessRow, key: String, ascending: Bool) -> Bool {
    let comparison: Bool
    switch key {
    case "name":
        let order = a.name.localizedStandardCompare(b.name)
        comparison = order == .orderedSame ? a.id < b.id : order == .orderedAscending
    case "pid": comparison = a.id < b.id
    case "gpu", "ane", "neural":
        func value(_ p: ProcessRow) -> Double { key == "gpu" ? p.gpuTime ?? -1 : key == "ane" ? p.aneGroupTime ?? -1 : p.neuralMemory.map(Double.init) ?? -1 }
        comparison = value(a) == value(b) ? a.id < b.id : value(a) < value(b)
    case "cpu": comparison = (a.cpu ?? -1) == (b.cpu ?? -1) ? a.id < b.id : (a.cpu ?? -1) < (b.cpu ?? -1)
    case "uid": comparison = a.uid == b.uid ? a.id < b.id : a.uid < b.uid
    case "disk":
        let av = a.readRate.flatMap { r in a.writeRate.map { r + $0 } } ?? -1
        let bv = b.readRate.flatMap { r in b.writeRate.map { r + $0 } } ?? -1
        comparison = av == bv ? a.id < b.id : av < bv
    case "read": comparison = (a.readRate ?? -1) == (b.readRate ?? -1) ? a.id < b.id : (a.readRate ?? -1) < (b.readRate ?? -1)
    case "write": comparison = (a.writeRate ?? -1) == (b.writeRate ?? -1) ? a.id < b.id : (a.writeRate ?? -1) < (b.writeRate ?? -1)
    case "resident": comparison = a.resident == b.resident ? a.id < b.id : a.resident < b.resident
    case "threads": comparison = a.threads == b.threads ? a.id < b.id : a.threads < b.threads
    default: comparison = (a.footprint ?? 0) == (b.footprint ?? 0) ? a.id < b.id : (a.footprint ?? 0) < (b.footprint ?? 0)
    }
    return ascending ? comparison : (a.id == b.id ? false : !comparison)
}

/// Missing measurements do not compete with a real zero. Ranking stays independent
/// of the process table's search/filter and is recomputed only after a sample.
func rankedProcesses(_ rows: [ProcessRow], key: String, limit: Int) -> [ProcessRow] {
    guard limit > 0 else { return [] }
    // Filter while selecting the small leader set; do not copy every measured row.
    let measured = rows.lazy.filter {
        switch key {
        case "gpu": return $0.gpuTime != nil
        case "ane": return $0.aneGroupTime != nil
        case "neural": return $0.neuralMemory != nil
        case "cpu": return $0.cpu != nil
        case "read": return $0.readRate != nil
        case "write": return $0.writeRate != nil
        case "disk": return $0.readRate != nil && $0.writeRate != nil
        default: return $0.footprint != nil
        }
    }
    if limit <= 8 {
        var best: [ProcessRow] = []
        best.reserveCapacity(limit)
        for row in measured {
            if best.count == limit, let last = best.last, !processPrecedes(row, last, key: key, ascending: false) { continue }
            let position = best.firstIndex { processPrecedes(row, $0, key: key, ascending: false) } ?? best.endIndex
            best.insert(row, at: position)
            if best.count > limit { best.removeLast() }
        }
        return best
    }
    return Array(measured.sorted { processPrecedes($0, $1, key: key, ascending: false) }.prefix(limit))
}
