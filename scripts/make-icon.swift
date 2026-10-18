// Draws the Linnet app icon (1024 px master) with Core Graphics: a small songbird whose tail feathers are lines of code.
// Usage: swift scripts/make-icon.swift Branding/AppIcon.png
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

// macOS icon grid: 824 px squircle centred in 1024, soft shadow below.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: tile, xRadius: 190, yRadius: 190)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
color(0x0A3D62).setFill()
squircle.fill()
ctx.restoreGState()

// Background: deep teal to ocean blue, with a warm glow behind the bird.
ctx.saveGState()
squircle.addClip()
let space = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: space, colors: [color(0x13C8B0).cgColor, color(0x0B6FA8).cgColor, color(0x0A3F78).cgColor] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 160, y: 920), end: CGPoint(x: 860, y: 110), options: [])
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28).cgColor, color(0xFFFFFF, 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560, y: 600), startRadius: 0, endCenter: CGPoint(x: 560, y: 600), endRadius: 420, options: [])
// subtle top sheen
let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.22).cgColor, color(0xFFFFFF, 0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
ctx.restoreGState()

// --- The bird (faces right) ---
func fill(_ path: NSBezierPath, _ c: NSColor) { c.setFill(); path.fill() }
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, rotation: CGFloat = 0) -> NSBezierPath {
    let p = NSBezierPath(ovalIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
    var t = AffineTransform(translationByX: cx, byY: cy)
    t.rotate(byDegrees: rotation)
    p.transform(using: t)
    return p
}

let cream = color(0xFFFDF6)
// Scale the whole mark up a little and centre it in the tile.
ctx.saveGState()
ctx.translateBy(x: 522, y: 514)
ctx.scaleBy(x: 1.10, y: 1.10)
ctx.translateBy(x: -505, y: -458)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -9), blur: 20, color: color(0x03233F, 0.42).cgColor)

// Tail: three parallel "lines of code", staggered like indentation, trailing down-left from the body.
let tailAngle: CGFloat = -16
let tail: [(len: CGFloat, indent: CGFloat)] = [(222, 0), (176, 30), (130, 60)]
for (i, line) in tail.enumerated() {
    let thickness: CGFloat = 38
    let bar = NSBezierPath(roundedRect: CGRect(x: -line.len, y: -thickness / 2, width: line.len, height: thickness), xRadius: 19, yRadius: 19)
    var t = AffineTransform(translationByX: 392 + line.indent * 0.2, byY: 452 - CGFloat(i) * 50)
    t.rotate(byDegrees: tailAngle)
    bar.transform(using: t)
    fill(bar, cream)
}

// Body.
fill(ellipse(515, 468, 205, 150, rotation: 14), cream)
ctx.restoreGState()

// Crimson breast (a linnet's signature): the lower chest, clipped to the body, so the head can overlap its top edge.
ctx.saveGState()
ellipse(515, 468, 205, 150, rotation: 14).addClip()
fill(ellipse(712, 430, 96, 92, rotation: 0), color(0xFF5A5F))
ctx.restoreGState()

// Head (drawn after the patch so it overlaps the patch's upper edge).
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -7), blur: 14, color: color(0x03233F, 0.32).cgColor)
fill(ellipse(668, 582, 98, 96), cream)
ctx.restoreGState()

// Wing: a darker leaf over the body, with code-line feathers.
let wing = NSBezierPath()
wing.move(to: CGPoint(x: 600, y: 522))
wing.curve(to: CGPoint(x: 350, y: 410), controlPoint1: CGPoint(x: 515, y: 546), controlPoint2: CGPoint(x: 400, y: 505))
wing.curve(to: CGPoint(x: 560, y: 368), controlPoint1: CGPoint(x: 392, y: 366), controlPoint2: CGPoint(x: 480, y: 346))
wing.curve(to: CGPoint(x: 600, y: 522), controlPoint1: CGPoint(x: 612, y: 400), controlPoint2: CGPoint(x: 628, y: 474))
wing.close()
fill(wing, color(0x0B6FA8, 0.9))
for (i, y) in [474.0, 438.0, 402.0].enumerated() {
    let line = NSBezierPath(roundedRect: CGRect(x: 424 + CGFloat(i) * 10, y: CGFloat(y) - 6, width: 124 - CGFloat(i) * 24, height: 12), xRadius: 6, yRadius: 6)
    fill(line, color(0xFFFFFF, 0.55))
}

// Beak, eye, feet.
let beak = NSBezierPath()
beak.move(to: CGPoint(x: 748, y: 606))
beak.curve(to: CGPoint(x: 828, y: 566), controlPoint1: CGPoint(x: 782, y: 604), controlPoint2: CGPoint(x: 810, y: 590))
beak.curve(to: CGPoint(x: 744, y: 548), controlPoint1: CGPoint(x: 802, y: 556), controlPoint2: CGPoint(x: 770, y: 548))
beak.close()
fill(beak, color(0xFFC857))
fill(ellipse(700, 614, 17, 17), color(0x0A2540))
fill(ellipse(706, 621, 5.5, 5.5), color(0xFFFFFF))
for dx in [-20.0, 42.0] {
    let leg = NSBezierPath(roundedRect: CGRect(x: 520 + CGFloat(dx), y: 286, width: 12, height: 66), xRadius: 6, yRadius: 6)
    fill(leg, color(0xFFC857))
    let toe = NSBezierPath(roundedRect: CGRect(x: 520 + CGFloat(dx) - 4, y: 282, width: 34, height: 11), xRadius: 5.5, yRadius: 5.5)
    fill(toe, color(0xFFC857))
}
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
