import Foundation

/// Axis limits and captions often ask for the same series several times in one
/// presentation. Calculate its peak and mean together, once per history change.
struct HistoryStatistics {
    struct Summary {
        let peak: Double?
        let mean: Double?
    }
    private var cached: [MetricSeries: Summary] = [:]

    mutating func invalidate() { cached.removeAll(keepingCapacity: true) }

    mutating func summary(_ series: MetricSeries, points: [Point]) -> Summary {
        if let summary = cached[series] { return summary }
        var peak: Double?, total = 0.0, count = 0
        for point in points {
            guard let value = series.value(point) else { continue }
            peak = peak.map { max($0, value) } ?? value
            total += value; count += 1
        }
        let summary = Summary(peak: peak, mean: count > 0 ? total / Double(count) : nil)
        cached[series] = summary
        return summary
    }
}
