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
    private var previous: [UInt64: GPUClientCounter] = [:]
    private var births: [Int32: UInt64] = [:]
    private var time: Double?
    mutating func reset() { previous.removeAll(keepingCapacity: true); births.removeAll(keepingCapacity: true); time = nil }
    mutating func update(_ clients: [GPUClientCounter], births currentBirths: [Int32: UInt64], now: Double, available: Bool) -> [Int32: Double] {
        guard available, now.isFinite else { reset(); return [:] }
        let elapsed = time.map { now - $0 }
        let current = Dictionary(clients.filter { currentBirths[$0.pid] != nil }.map { ($0.id, $0) }, uniquingKeysWith: { _, next in next })
        defer { previous = current; births = currentBirths; time = now }
        guard let elapsed, elapsed > 0 else { return [:] }
        var invalid = Set<Int32>(), totals: [Int32: Double] = [:]
        for (id, client) in previous where current[id] == nil { invalid.insert(client.pid) }
        for (id, client) in current {
            guard let old = previous[id], old.pid == client.pid,
                  births[client.pid] == currentBirths[client.pid], old.contexts == client.contexts,
                  client.nanoseconds >= old.nanoseconds else { invalid.insert(client.pid); continue }
            totals[client.pid, default: 0] += Double(client.nanoseconds - old.nanoseconds) / elapsed / 1_000_000
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
    return String(format: "%.1f ms/s", value)
}
