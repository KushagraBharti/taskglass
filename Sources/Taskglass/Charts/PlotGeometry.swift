import CoreGraphics

/// Builds the stroke and its optional fill together. Both paths share the same
/// finite-value checks, time coordinates and segment boundaries.
struct PlotGeometry {
    let line: CGPath
    let area: CGPath?
    static let maximumGap = 11.0

    init(points: [Point], series: MetricSeries, floor: Double, ceiling: Double,
         window: Double, rect: CGRect, filled: Bool) {
        let line = CGMutablePath()
        let area = filled ? CGMutablePath() : nil
        self.line = line; self.area = area
        let span = ceiling - floor
        guard let end = points.last?.time, span > 0, window > 0 else { return }
        var pen = false
        var startX: CGFloat = 0, lastX: CGFloat = 0, lastTime = -Double.infinity
        func close() {
            guard pen, let area else { return }
            area.addLine(to: CGPoint(x: lastX, y: rect.maxY))
            area.addLine(to: CGPoint(x: startX, y: rect.maxY))
            area.closeSubpath()
        }
        for point in points {
            let age = end - point.time
            guard age <= window else { continue }
            let x = rect.minX + rect.width * (1 - age / window)
            if pen && (point.beginsSegment || point.time - lastTime > Self.maximumGap) {
                close(); pen = false
            }
            lastTime = point.time
            guard let value = series.value(point) else { close(); pen = false; continue }
            let y = rect.minY + rect.height * (1 - min(1, max(0, (value - floor) / span)))
            let position = CGPoint(x: x, y: y)
            if pen {
                line.addLine(to: position); area?.addLine(to: position)
            } else {
                line.move(to: position); area?.move(to: position); startX = x
            }
            lastX = x; pen = true
        }
        close()
    }
}
