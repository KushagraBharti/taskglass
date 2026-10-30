import SwiftUI

struct HistoryGraph: View {
    let points: [Point]
    let memory: Bool
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                VStack { Divider(); Spacer(); Divider(); Spacer(); Divider() }.opacity(0.5)
                Sparkline(points: points, memory: memory, color: .accentColor)
            }
            HStack { Text("Earlier"); Spacer(); Text("Now") }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}
struct PlotShape: Shape {
    let points: [Point]
    let memory: Bool
    let filled: Bool
    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        var line = Path()
        for (index, p) in points.enumerated() {
            let point = CGPoint(x: rect.width * Double(index) / Double(points.count - 1), y: rect.height * (1 - min(100, max(0, memory ? p.memory : p.cpu)) / 100))
            if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        if filled { line.addLine(to: CGPoint(x: rect.width, y: rect.height)); line.addLine(to: CGPoint(x: 0, y: rect.height)); line.closeSubpath() }
        return line
    }
}
struct Sparkline: View {
    let points: [Point]
    let memory: Bool
    let color: Color
    var body: some View {
        PlotShape(points: points, memory: memory, filled: true)
            .fill(LinearGradient(colors: [color.opacity(0.2), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            .overlay(PlotShape(points: points, memory: memory, filled: false).stroke(color, lineWidth: 1.5))
            .accessibilityLabel(memory ? "Memory history" : "CPU history")
    }
}
