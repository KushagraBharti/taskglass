import Foundation

/// Ordered members borrow the shared sample. Sorting an app's helpers moves
/// integer indices instead of copying full process records; individual rows
/// need no separate one-element allocation.
struct ProcessMembers: RandomAccessCollection, Equatable {
    typealias Index = Int
    private enum Selection {
        case range(Range<Int>)
        case ordered([Int])
    }
    private let source: [ProcessRow]
    private let selection: Selection

    init(_ source: [ProcessRow]) {
        self.source = source; selection = .range(source.indices)
    }
    init(source: [ProcessRow], index: Int) {
        self.source = source; selection = .range(index..<(index + 1))
    }
    init(source: [ProcessRow], order: [Int]) {
        self.source = source; selection = .ordered(order)
    }

    var startIndex: Int { 0 }
    var endIndex: Int {
        switch selection {
        case .range(let range): range.count
        case .ordered(let order): order.count
        }
    }
    subscript(position: Int) -> ProcessRow {
        precondition(position >= 0 && position < endIndex)
        switch selection {
        case .range(let range): return source[range.lowerBound + position]
        case .ordered(let order): return source[order[position]]
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        // Only these members matter. Unrelated processes elsewhere in the
        // shared sample must not change a family's equality.
        lhs.count == rhs.count && lhs.elementsEqual(rhs)
    }
}
