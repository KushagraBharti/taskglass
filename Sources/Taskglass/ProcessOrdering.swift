import Foundation

func processPrecedes(_ a: ProcessRow, _ b: ProcessRow, key: String, ascending: Bool) -> Bool {
    let comparison: Bool
    switch key {
    case "name":
        let order = a.name.localizedStandardCompare(b.name)
        comparison = order == .orderedSame ? a.id < b.id : order == .orderedAscending
    case "pid": comparison = a.id < b.id
    case "cpu": comparison = (a.cpu ?? -1) == (b.cpu ?? -1) ? a.id < b.id : (a.cpu ?? -1) < (b.cpu ?? -1)
    case "uid": comparison = a.uid == b.uid ? a.id < b.id : a.uid < b.uid
    case "read": comparison = (a.readRate ?? -1) == (b.readRate ?? -1) ? a.id < b.id : (a.readRate ?? -1) < (b.readRate ?? -1)
    case "write": comparison = (a.writeRate ?? -1) == (b.writeRate ?? -1) ? a.id < b.id : (a.writeRate ?? -1) < (b.writeRate ?? -1)
    case "resident": comparison = a.resident == b.resident ? a.id < b.id : a.resident < b.resident
    case "threads": comparison = a.threads == b.threads ? a.id < b.id : a.threads < b.threads
    default: comparison = (a.footprint ?? 0) == (b.footprint ?? 0) ? a.id < b.id : (a.footprint ?? 0) < (b.footprint ?? 0)
    }
    return ascending ? comparison : (a.id == b.id ? false : !comparison)
}
