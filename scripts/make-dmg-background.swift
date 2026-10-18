// Draws the installer window background (660x400 pt, rendered at 1x and 2x).  Usage: swift scripts/make-dmg-background.swift <out-prefix>
import AppKit

let prefix = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Branding/dmg-background"

func render(scale: CGFloat, to path: String) {
    let w = Int(660 * scale), h = Int(400 * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 660, height: 400)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let space = CGColorSpaceCreateDeviceRGB()
    func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }
    let bg = CGGradient(colorsSpace: space, colors: [c(0xF4FBFA).cgColor, c(0xDCEEF4).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 400), end: CGPoint(x: 660, y: 0), options: [])

    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at p: CGPoint, centered: Bool = true) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let str = NSAttributedString(string: s, attributes: attrs)
        let width = str.size().width
        str.draw(at: CGPoint(x: centered ? p.x - width / 2 : p.x, y: p.y))
    }
    text("Kode", size: 34, weight: .bold, color: c(0x0A3F78), at: CGPoint(x: 330, y: 330))
    text("A light, native code editor", size: 14, weight: .regular, color: c(0x2F6E8F), at: CGPoint(x: 330, y: 304))

    // Arrow between the app icon (x≈180) and the Applications shortcut (x≈480), vertically at icon centre (y≈190 from bottom).
    let arrow = NSBezierPath()
    arrow.lineWidth = 7
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: CGPoint(x: 262, y: 200))
    arrow.line(to: CGPoint(x: 398, y: 200))
    arrow.move(to: CGPoint(x: 372, y: 226))
    arrow.line(to: CGPoint(x: 400, y: 200))
    arrow.line(to: CGPoint(x: 372, y: 174))
    c(0x13A89A, 0.85).setStroke()
    arrow.stroke()
    text("Drag Kode into Applications", size: 13, weight: .medium, color: c(0x2F6E8F), at: CGPoint(x: 330, y: 92))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

try? FileManager.default.createDirectory(atPath: (prefix as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
render(scale: 1, to: prefix + ".png")
render(scale: 2, to: prefix + "@2x.png")
print("wrote \(prefix).png and @2x")
