// Draws Sweep's app icon at every size macOS needs and writes the PNGs into the asset catalog.
// Usage: swift scripts/make-icon.swift Sweep/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sweep/Resources/Assets.xcassets/AppIcon.appiconset")

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024

    // Squircle-ish rounded rect with the standard macOS icon margin.
    let inset = 100 * s
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let colors = [NSColor(srgbRed: 0.13, green: 0.47, blue: 0.93, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.10, green: 0.72, blue: 0.62, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Soft light from the top.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: rect.midX, y: rect.maxY), startRadius: 0,
                           endCenter: CGPoint(x: rect.midX, y: rect.maxY), endRadius: rect.height * 0.9, options: [])

    // Three sweeping arcs.
    ctx.setLineCap(.round)
    let center = CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.30)
    for (index, radius) in [300.0, 420.0, 540.0].enumerated() {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95 - Double(index) * 0.25).cgColor)
        ctx.setLineWidth((54 - CGFloat(index) * 12) * s)
        ctx.addArc(center: center, radius: radius * s, startAngle: .pi * 0.08, endAngle: .pi * 0.42, clockwise: false)
        ctx.strokePath()
    }

    // A four pointed sparkle.
    func sparkle(at point: CGPoint, radius: CGFloat, alpha: CGFloat) {
        let path = CGMutablePath()
        let inner = radius * 0.22
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 + .pi / 2
            let r = i % 2 == 0 ? radius : inner
            let p = CGPoint(x: point.x + cos(angle) * r, y: point.y + sin(angle) * r)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        ctx.fillPath()
    }
    sparkle(at: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.42), radius: 165 * s, alpha: 1)
    sparkle(at: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.76), radius: 72 * s, alpha: 0.85)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [String] = []
for (points, scale) in sizes {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let data = drawIcon(size: CGFloat(pixels)).representation(using: .png, properties: [:])!
    try! data.write(to: output.appending(path: name))
    images.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
    """)
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contents.write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Icon written to \(output.path)")
