import Foundation

/// Names rarely change between samples. Preserve the order of surviving names
/// and merge only new or renamed processes using the system's localized order.
/// Entries retain names and PIDs, never old samples or process metadata.
struct ProcessNameOrder {
    private struct Entry {
        let pid: Int32
        let name: String
    }
    private var entries: [Entry] = []
    private var locale: Locale?

    mutating func reset() { entries = []; locale = nil }

    mutating func sort(_ rows: inout [ProcessRow], ascending: Bool) {
        let currentLocale = Locale.current
        if locale != currentLocale { entries = []; locale = currentLocale }
        if entries.isEmpty {
            rows.sort { processPrecedes($0, $1, key: .name, ascending: true) }
            entries = rows.map { Entry(pid: $0.id, name: $0.name) }
            if !ascending { rows.reverse() }
            return
        }
        var lookup: [Int32: Int] = [:]
        lookup.reserveCapacity(rows.count)
        for index in rows.indices { lookup[rows[index].id] = index }
        var retained: [Int] = [], added: [Int] = []
        retained.reserveCapacity(min(entries.count, rows.count))
        for entry in entries {
            if let index = lookup.removeValue(forKey: entry.pid) {
                if entry.name == rows[index].name { retained.append(index) }
                else { added.append(index) }
            }
        }
        added.append(contentsOf: lookup.values)
        added.sort { processPrecedes(rows[$0], rows[$1], key: .name, ascending: true) }
        let unchanged = added.isEmpty && retained.count == entries.count
        var order: [Int]
        if added.isEmpty { order = retained }
        else {
            order = []; order.reserveCapacity(rows.count)
            var r = 0, a = 0
            while r < retained.count && a < added.count {
                if processPrecedes(rows[added[a]], rows[retained[r]], key: .name, ascending: true) {
                    order.append(added[a]); a += 1
                } else {
                    order.append(retained[r]); r += 1
                }
            }
            order.append(contentsOf: retained[r...])
            order.append(contentsOf: added[a...])
        }
        if !unchanged { entries = order.map { Entry(pid: rows[$0].id, name: rows[$0].name) } }
        if !ascending { order.reverse() }
        // Apply the destination-to-source permutation without a second row buffer.
        for start in rows.indices where order[start] != start {
            let saved = rows[start]
            var destination = start
            while true {
                let source = order[destination]
                order[destination] = destination
                if source == start { rows[destination] = saved; break }
                rows[destination] = rows[source]
                destination = source
            }
        }
    }
}
