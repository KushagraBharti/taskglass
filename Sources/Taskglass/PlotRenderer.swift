import SwiftUI
import AppKit

/// Draw directly into AppKit's backing store. A SwiftUI Canvas can retain large
/// graphics buffers for these small, infrequently updated charts.
/// Grid, baseline and traces share one view; labels and accessibility stay in TelemetryPlot.
struct PlotRenderer: NSViewRepresentable {
    let points: [Point]
    let layers: [PlotLayer]
    let floor: Double
    let ceiling: Double
    let window: Double
    let lineWidth: CGFloat
    let fillOpacity: Double
    let style: PlotStyle

    func makeNSView(context: Context) -> PlotView { PlotView() }
    func updateNSView(_ view: PlotView, context: Context) {
        view.points = points
        view.layers = layers
        view.floor = floor; view.ceiling = ceiling; view.timeWindow = window
        view.lineWidth = lineWidth; view.fillOpacity = fillOpacity; view.style = style
        view.needsDisplay = true
    }
    final class PlotView: NSView {
        var points: [Point] = [], layers: [PlotLayer] = []
        var floor = 0.0, ceiling = 100.0, timeWindow = 60.0
        var lineWidth: CGFloat = 1.5
        var fillOpacity = 0.13
        var style = PlotStyle.compact
        override var isFlipped: Bool { true }
        // Charts inside Overview buttons must not intercept the button's clicks.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func setFrameSize(_ size: NSSize) {
            let changed = frame.size != size
            super.setFrameSize(size)
            if changed { needsDisplay = true }
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            drawGrid(in: context)
            let plotRect: CGRect
            switch style {
            case .micro: plotRect = bounds.insetBy(dx: 0, dy: 2)
            case .inline: plotRect = bounds.insetBy(dx: 0, dy: 1)
            case .compact, .detailed: plotRect = CGRect(x: bounds.minX, y: bounds.minY + 1, width: bounds.width, height: max(0, bounds.height - 1))
            }
            context.setLineCap(.round); context.setLineJoin(.round)
            for layer in layers {
                let paths = PlotGeometry(points: points, series: layer.series, floor: floor, ceiling: ceiling,
                                         window: timeWindow, rect: plotRect, filled: layer.filled)
                let color = NSColor(layer.color).cgColor
                if let area = paths.area {
                    context.setFillColor(color.copy(alpha: color.alpha * fillOpacity) ?? color)
                    context.addPath(area); context.fillPath()
                }
                context.setStrokeColor(color)
                context.setLineWidth(layer.dashed ? lineWidth * 0.9 : lineWidth)
                context.setLineDash(phase: 0, lengths: layer.dashed ? [3, 2.5] : [])
                context.addPath(paths.line); context.strokePath()
            }
            context.restoreGState()
        }
        private static let gridColor = NSColor(Palette.grid).cgColor
        private static let baselineColor = NSColor(Palette.baseline).cgColor
        private func drawGrid(in context: CGContext) {
            guard style != .micro else { return }
            context.setLineCap(.butt); context.setLineJoin(.miter)
            context.setLineDash(phase: 0, lengths: [])
            context.setLineWidth(Metrics.hairline)
            context.setStrokeColor(Self.gridColor)
            let divisions = style == .detailed ? 4 : style == .compact ? 2 : 0
            for index in 0..<divisions {
                let y = (bounds.minY + bounds.height * CGFloat(index) / CGFloat(divisions)).rounded() + 0.25
                context.move(to: CGPoint(x: bounds.minX, y: y)); context.addLine(to: CGPoint(x: bounds.maxX, y: y))
            }
            if style == .detailed {
                let verticals = timeWindow >= 600 ? 10 : 6
                for index in 1..<verticals {
                    let x = (bounds.minX + bounds.width * CGFloat(index) / CGFloat(verticals)).rounded() + 0.25
                    context.move(to: CGPoint(x: x, y: bounds.minY)); context.addLine(to: CGPoint(x: x, y: bounds.maxY))
                }
            }
            context.strokePath()
            if style != .inline { context.setStrokeColor(Self.baselineColor) }
            context.move(to: CGPoint(x: bounds.minX, y: bounds.maxY - 0.25))
            context.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - 0.25)); context.strokePath()
            if style != .inline, let first = points.first?.time, let end = points.last?.time,
               timeWindow > 0, end - first < timeWindow * 0.97 {
                let x = (bounds.minX + bounds.width * (1 - (end - first) / timeWindow)).rounded() + 0.25
                context.setLineDash(phase: 0, lengths: [2, 3])
                context.move(to: CGPoint(x: x, y: bounds.minY)); context.addLine(to: CGPoint(x: x, y: bounds.maxY))
                context.strokePath()
            }
        }
    }
}
