import Foundation
import SystemProbe

struct GPUClientCounter: Sendable {
    let id: UInt64
    let pid: Int32
    let nanoseconds: UInt64
    let contexts: UInt32
}

/// GPU execution time, not a percentage of device capacity. Require the same
/// live client set, context counts and process birth identity at both ends.
/// A new/removed client, reset or failed scan leaves a gap for its process.
struct GPUAccounting {
    private struct Entry {
        let client: GPUClientCounter
        let birth: UInt64
    }
    private var previous: [UInt64: Entry] = [:]
    private var time: Double?
    mutating func reset() { previous.removeAll(keepingCapacity: true); time = nil }

    mutating func update(_ clients: [GPUClientCounter], births currentBirths: [Int32: UInt64], now: Double, available: Bool) -> [Int32: Double] {
        update(clients, birthForPID: { currentBirths[$0] }, now: now, available: available)
    }

    /// The sampler already has the current process identity map. Borrow it for
    /// these clients instead of copying every process birth into a second map.
    mutating func update<Clients: Collection>(_ clients: Clients, birthForPID: (Int32) -> UInt64?,
                                             now: Double, available: Bool) -> [Int32: Double] where Clients.Element == GPUClientCounter {
        guard available, now.isFinite else { reset(); return [:] }
        let elapsed = time.map { now - $0 }
        var current: [UInt64: Entry] = [:]
        current.reserveCapacity(clients.count)
        for client in clients {
            if let birth = birthForPID(client.pid) { current[client.id] = Entry(client: client, birth: birth) }
        }
        defer { previous = current; time = now }
        guard let elapsed, elapsed > 0 else { return [:] }
        var invalid = Set<Int32>(), totals: [Int32: Double] = [:]
        for (id, entry) in previous where current[id] == nil { invalid.insert(entry.client.pid) }
        for (id, entry) in current {
            let client = entry.client
            guard let old = previous[id], old.client.pid == client.pid,
                  old.birth == entry.birth, old.client.contexts == client.contexts,
                  client.nanoseconds >= old.client.nanoseconds else { invalid.insert(client.pid); continue }
            totals[client.pid, default: 0] += Double(client.nanoseconds - old.client.nanoseconds) / elapsed / 1_000_000
        }
        return totals.filter { !invalid.contains($0.key) && $0.value.isFinite }
    }
}

/// OS resource-group time in ms/s. Members share one counter; callers must
/// deduplicate by group ID when aggregating. It is not per-process occupancy.
struct ANEAccounting {
    private var previous: [UInt64: UInt64] = [:]
    private var time: Double?
    mutating func reset() { previous.removeAll(keepingCapacity: true); time = nil }
    mutating func update(_ current: [UInt64: UInt64], now: Double) -> [UInt64: Double] {
        let elapsed = time.map { now - $0 }
        defer { previous = current; time = now.isFinite ? now : nil }
        guard now.isFinite, let elapsed, elapsed > 0 else { return [:] }
        return current.reduce(into: [:]) { rates, item in
            guard let old = previous[item.key], item.value >= old else { return }
            let rate = Double(item.value - old) / elapsed / 1_000_000
            if rate.isFinite { rates[item.key] = rate }
        }
    }
}

func acceleratorTime(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return "—" }
    return decimal(value, places: 1) + " ms/s"
}
