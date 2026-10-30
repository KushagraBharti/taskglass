import AppKit
let output = CommandLine.arguments[1]
guard let logo = NSImage(contentsOfFile: "Assets/Branding/taskglass-logo.png") else {
    fatalError("Missing project logo")
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
    // Render exact pixel dimensions. NSImage.lockFocus follows the display's
    // backing scale and was silently generating every icon at twice its size.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let rect = NSRect(x: 48, y: 48, width: 928, height: 928)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 212, yRadius: 212)
    NSColor(calibratedWhite: 0.055, alpha: 1).setFill(); shape.fill()
    NSColor.white.withAlphaComponent(0.12).setStroke(); shape.lineWidth = 2; shape.stroke()
    logo.draw(in: NSRect(x: 176, y: 176, width: 672, height: 672),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
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
