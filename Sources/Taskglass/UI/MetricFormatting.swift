import SystemProbe

/// Fixed precision without constructing Foundation format arguments. The large
/// stack buffer covers every finite Double at the supported precision without truncation.
/// Small outputs can use Swift’s inline string storage instead of a 64-byte allocation.
func decimal(_ value: Double, places: Int32) -> String {
    precondition(places >= 0 && places <= 2)
    let capacity = abs(value) < 1e50 ? 64 : 320
    return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity) { buffer in
        let output = UnsafeMutableRawPointer(buffer.baseAddress!).assumingMemoryBound(to: CChar.self)
        let count = Int(tg_format_decimal(output, buffer.count, value, places))
        precondition(count >= 0 && count < buffer.count)
        return String(decoding: UnsafeBufferPointer(start: buffer.baseAddress!, count: count), as: UTF8.self)
    }
}
