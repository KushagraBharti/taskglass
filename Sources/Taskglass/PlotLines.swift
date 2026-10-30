import SwiftUI

/// Generate each line and fill together, then let SwiftUI render the vectors.
/// The existing chart keeps its sizing, compositing and accessibility behavior.
struct PlotLines: View {
    let points: [Point]
    let layers: [PlotLayer]
    let floor: Double
    let ceiling: Double
    let window: Double
    let lineWidth: CGFloat
    let fillOpacity: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(layers) { layer in
                    let paths = PlotGeometry(points: points, series: layer.series, floor: floor, ceiling: ceiling,
                                             window: window, rect: CGRect(origin: .zero, size: geometry.size), filled: layer.filled)
                    if let area = paths.area { Path(area).fill(layer.color.opacity(fillOpacity)) }
                    Path(paths.line)
                        .stroke(layer.color, style: StrokeStyle(lineWidth: layer.dashed ? lineWidth * 0.9 : lineWidth,
                                                               lineCap: .round, lineJoin: .round,
                                                               dash: layer.dashed ? [3, 2.5] : []))
                }
            }
        }
    }
}
