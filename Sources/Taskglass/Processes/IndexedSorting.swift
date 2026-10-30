/// Sort compact keys and source indexes, then move each large record once.
/// This avoids repeatedly copying process records and their retained metadata
/// through the stable sort's merge buffer. An already-ordered input is untouched.
func sortByCachedKey<Element, Key: Comparable>(_ elements: inout [Element], ascending: Bool,
                                               key: (Element) -> Key, tie: (Element, Element) -> Bool) {
    guard elements.count > 1 else { return }
    var order = elements.indices.map { SortIndex(index: $0, key: key(elements[$0])) }
    order.sort {
        if $0.key != $1.key { return ascending ? $0.key < $1.key : $0.key > $1.key }
        return tie(elements[$0.index], elements[$1.index])
    }
    // Each sorted position names its original source. Follow one cycle at a
    // time; mark a visited position by making its source point to itself.
    for start in elements.indices where order[start].index != start {
        let saved = elements[start]
        var destination = start
        while true {
            let source = order[destination].index
            order[destination].index = destination
            if source == start { elements[destination] = saved; break }
            elements[destination] = elements[source]
            destination = source
        }
    }
}

private struct SortIndex<Key> {
    var index: Int
    let key: Key
}
