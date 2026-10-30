import SwiftUI

/// One drawing operation per chart avoids a separate SwiftUI subtree for every
/// stroke and fill. The surrounding plot still owns axes and accessibility.
struct PlotLines: View {
    let points: [Point]
    let layers: [PlotLayer]
    let floor: Double
    let ceiling: Double
    let window: Double
    let lineWidth: CGFloat
    let fillOpacity: Double

    var body: some View {
        Canvas { context, size in
            for layer in layers {
                let paths = PlotGeometry(points: points, series: layer.series, floor: floor, ceiling: ceiling,
                                         window: window, rect: CGRect(origin: .zero, size: size), filled: layer.filled)
                if let area = paths.area { context.fill(Path(area), with: .color(layer.color.opacity(fillOpacity))) }
                context.stroke(Path(paths.line), with: .color(layer.color),
                               style: StrokeStyle(lineWidth: layer.dashed ? lineWidth * 0.9 : lineWidth,
                                                  lineCap: .round, lineJoin: .round,
                                                  dash: layer.dashed ? [3, 2.5] : []))
            }
        }
    }
}
