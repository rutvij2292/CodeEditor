// Draws the Kode app icon (1024 px master) with Core Graphics: a bold "K" (stem + two arms, the lower one in amber)
// on a deep indigo tile.  Usage: swift scripts/make-icon.swift Branding/AppIcon.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Branding/AppIcon.png"
let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext
ctx.setShouldAntialias(true)
let space = CGColorSpaceCreateDeviceRGB()

// macOS icon grid: 824 px squircle centred in 1024, soft shadow below.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: tile, xRadius: 190, yRadius: 190)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
color(0x1B1E4B).setFill()
squircle.fill()
ctx.restoreGState()

ctx.saveGState()
squircle.addClip()
let bg = CGGradient(colorsSpace: space, colors: [color(0x4B3FD6).cgColor, color(0x252A7E).cgColor, color(0x0E1033).cgColor] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 180, y: 930), end: CGPoint(x: 850, y: 100), options: [])
let glow = CGGradient(colorsSpace: space, colors: [color(0x7C6CFF, 0.35).cgColor, color(0x7C6CFF, 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 400, y: 760), startRadius: 0, endCenter: CGPoint(x: 400, y: 760), endRadius: 480, options: [])
let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.16).cgColor, color(0xFFFFFF, 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
ctx.restoreGState()

// The K: round-capped strokes so it reads as a code glyph.
let w: CGFloat = 112
func stroke(_ a: CGPoint, _ b: CGPoint, _ c: NSColor) {
    let p = NSBezierPath()
    p.lineWidth = w
    p.lineCapStyle = .round
    p.move(to: a)
    p.line(to: b)
    c.setStroke()
    p.stroke()
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: NSColor.black.withAlphaComponent(0.35).cgColor)
stroke(CGPoint(x: 400, y: 510), CGPoint(x: 690, y: 290), color(0xFFB347))        // lower arm (tucks under the white strokes)
stroke(CGPoint(x: 352, y: 292), CGPoint(x: 352, y: 732), color(0xFFFDF6))        // stem
stroke(CGPoint(x: 400, y: 520), CGPoint(x: 680, y: 736), color(0xFFFDF6))        // upper arm
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
