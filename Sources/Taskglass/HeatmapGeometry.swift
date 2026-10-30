import CoreGraphics

/// Every core shares the time axis. Calculate a sample's horizontal span once,
/// then batch its core cells by the eight load levels.
struct HeatmapGeometry {
    let track: [CGRect]
    let levels: [[CGRect]]

    init(points: [Point], indices: [Int], window: Double, plotWidth: CGFloat,
         labelWidth: CGFloat, rowHeight: CGFloat, rowStep: CGFloat) {
        var track: [CGRect] = []
        track.reserveCapacity(indices.count)
        var cells = Array(repeating: [CGRect](), count: 8)
        var lastCells = [Int](repeating: -1, count: indices.count * 8)
        for row in indices.indices {
            track.append(CGRect(x: labelWidth, y: CGFloat(row) * rowStep, width: plotWidth, height: rowHeight))
        }
        self.track = track
        guard let end = points.last?.time, window > 0 else { levels = []; return }
        for (position, sample) in points.enumerated() {
            let age = end - sample.time
            guard age <= window else { continue }
            let x = labelWidth + plotWidth * (1 - age / window)
            // Restarted sampling must not paint a continuous band across a gap.
            let following = position + 1 < points.count ? points[position + 1] : nil
            let next = following.map { $0.beginsSegment ? sample.time + 2 : $0.time } ?? sample.time + 2
            let width = min(max(1, plotWidth * min(5, next - sample.time) / window), labelWidth + plotWidth - x)
            guard width > 0 else { continue }
            for (row, index) in indices.enumerated() where sample.cores.indices.contains(index) {
                let usage = sample.cores[index]
                guard usage.isFinite else { continue }
                let level = min(7, Int(min(99.9, max(0, usage)) / 12.5))
                let lane = level * indices.count + row
                let previous = lastCells[lane]
                // All cells in this lane have the same height, y and shade.
                // Union touching/overlapping intervals without bridging a gap.
                if previous >= 0, x >= cells[level][previous].minX, x <= cells[level][previous].maxX {
                    cells[level][previous].size.width = max(cells[level][previous].maxX, x + width) - cells[level][previous].minX
                } else {
                    lastCells[lane] = cells[level].count
                    cells[level].append(CGRect(x: x, y: CGFloat(row) * rowStep, width: width, height: rowHeight))
                }
            }
        }
        levels = cells
    }
}
