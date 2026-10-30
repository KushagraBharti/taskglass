import AppKit
let output = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let rect = NSRect(x: 48, y: 48, width: 928, height: 928)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 212, yRadius: 212)
    NSGradient(starting: NSColor(red: 0.11, green: 0.29, blue: 0.4, alpha: 1), ending: NSColor(red: 0.06, green: 0.11, blue: 0.2, alpha: 1))!.draw(in: shape, angle: -65)
    NSColor.white.withAlphaComponent(0.22).setStroke(); shape.lineWidth = 4; shape.stroke()
    let line = NSBezierPath(); line.move(to: NSPoint(x: 208, y: 488))
    for (x,y) in [(355,488),(420,660),(505,310),(591,588),(655,488),(816,488)] { line.line(to: NSPoint(x: x, y: y)) }
    line.lineWidth = 44; line.lineCapStyle = .round; line.lineJoinStyle = .round
    NSColor(red: 0.35, green: 0.91, blue: 0.95, alpha: 1).setStroke(); line.stroke()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name)) }
}
