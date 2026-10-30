import SystemProbe

/// Fixed precision without constructing Foundation format arguments. The large
/// buffer covers every finite Double at the supported precision without truncation.
func decimal(_ value: Double, places: Int32) -> String {
    precondition(places >= 0 && places <= 2)
    let capacity = abs(value) < 1e50 ? 64 : 320
    return String(unsafeUninitializedCapacity: capacity) { buffer in
        let output = UnsafeMutableRawPointer(buffer.baseAddress!).assumingMemoryBound(to: CChar.self)
        let count = Int(tg_format_decimal(output, buffer.count, value, places))
        precondition(count >= 0 && count < buffer.count)
        return count
    }
}
