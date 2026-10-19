import AppKit

enum FileIcon {
    static func symbol(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "php", "phtml", "html", "htm", "vue", "xml": return "chevron.left.forwardslash.chevron.right"
        case "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "json", "jsonc": return "curlybraces"
        case "css", "scss", "sass", "less": return "paintbrush"
        case "md", "markdown", "txt": return "doc.richtext"
        case "yml", "yaml", "env", "ini", "toml", "conf": return "gearshape"
        case "sh", "bash", "zsh": return "terminal"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico": return "photo"
        case "lock": return "lock"
        case "sql": return "cylinder"
        default: return "doc.text"
        }
    }

    static func tint(forExtension ext: String) -> NSColor {
        switch ext.lowercased() {
        case "php", "phtml": return .systemIndigo
        case "html", "htm", "xml": return .systemOrange
        case "js", "jsx", "mjs", "cjs": return .systemYellow
        case "ts", "tsx", "mts": return .systemBlue
        case "vue": return .systemGreen
        case "css", "scss", "sass", "less": return .systemTeal
        case "json", "jsonc", "yml", "yaml", "env": return .systemGray
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico": return .systemPink
        default: return .secondaryLabelColor
        }
    }
}

// MARK: PhpStorm-style drawn icons (tree rows)

extension FileIcon {
    private static var cache: [String: NSImage] = [:]

    /// Icon for a tree row: outline folders, a circled C for PHP classes, letter badges for common file types.
    static func treeImage(name: String, isDirectory: Bool) -> NSImage {
        let ext = (name as NSString).pathExtension.lowercased()
        let key: String
        if isDirectory { key = name.hasPrefix(".") ? "dir.dot" : "dir" }
        else if ext == "php", name.hasSuffix(".blade.php") { key = "blade" }
        else if name == "artisan" { key = "php" }
        else if ext == "php" { key = (name.first?.isUppercase == true) ? "php.class" : "php" }
        else if name.hasPrefix(".git") && name.hasSuffix("ignore") || name == ".ignore" { key = "ignore" }
        else if name.hasPrefix(".env") || name.hasPrefix(".") && ext.isEmpty { key = "lines" }
        else { key = ext.isEmpty ? "lines" : ext }
        if let img = cache[key] { return img }
        let img = draw(key: key, fallbackExt: ext)
        cache[key] = img
        return img
    }

    private static func draw(key: String, fallbackExt ext: String) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        switch key {
        case "dir", "dir.dot":
            return symbol("folder", color: key == "dir" ? Theme.hex(0x6B8CB8) : Theme.hex(0x9A7B4F), size: size)
        case "php.class":
            return NSImage(size: size, flipped: false) { r in
                let c = Theme.hex(0x4E7FD6)
                let circle = NSBezierPath(ovalIn: r.insetBy(dx: 1.2, dy: 1.2))
                c.withAlphaComponent(0.14).setFill(); circle.fill()
                c.setStroke(); circle.lineWidth = 1.1; circle.stroke()
                drawText("C", in: r, color: c, size: 9.5, weight: .semibold)
                return true
            }
        case "php": return badge("php", Theme.hex(0x6C5CC7), size: size)
        case "blade": return badge("b", Theme.hex(0xE0533D), size: size, filled: true)
        case "md", "markdown": return badge("M↓", Theme.hex(0x4E7FD6), size: size)
        case "json", "jsonc": return badge("{}", Theme.hex(0x8F5CC7), size: size)
        case "js", "mjs", "cjs", "jsx": return badge("JS", Theme.hex(0x1F1F1F), size: size, filled: true, fill: Theme.hex(0xF0C419))
        case "ts", "tsx", "mts": return badge("TS", .white, size: size, filled: true, fill: Theme.hex(0x3178C6))
        case "vue": return badge("V", .white, size: size, filled: true, fill: Theme.hex(0x41B883))
        case "css", "scss", "sass", "less": return badge("#", Theme.hex(0x2F9DB8), size: size)
        case "html", "htm", "xml": return badge("<>", Theme.hex(0xE5762E), size: size)
        case "yml", "yaml": return badge("Y", Theme.hex(0xC24A4A), size: size)
        case "ignore": return symbol("nosign", color: .secondaryLabelColor, size: size)
        case "lines": return symbol("text.alignleft", color: .secondaryLabelColor, size: size)
        case "lock": return symbol("lock", color: .secondaryLabelColor, size: size)
        default: return symbol(symbolName(forExtension: ext), color: tint(forExtension: ext), size: size)
        }
    }

    private static func symbolName(forExtension ext: String) -> String { symbol(forExtension: ext) }

    private static func symbol(_ name: String, color: NSColor, size: NSSize) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) ?? NSImage(size: size)
        return NSImage(size: size, flipped: false) { r in
            guard base.size.width > 0 else { return true }
            let s = base.size, scale = min(r.width / s.width, r.height / s.height, 1)
            let dr = NSRect(x: (r.width - s.width * scale) / 2, y: (r.height - s.height * scale) / 2,
                            width: s.width * scale, height: s.height * scale)
            base.draw(in: dr)
            color.setFill(); dr.fill(using: .sourceIn)
            return true
        }
    }

    private static func badge(_ text: String, _ color: NSColor, size: NSSize, filled: Bool = false, fill: NSColor? = nil) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            let box = NSBezierPath(roundedRect: r.insetBy(dx: 0.9, dy: 1.6), xRadius: 2.5, yRadius: 2.5)
            if filled { (fill ?? color).setFill(); box.fill() }
            else { color.withAlphaComponent(0.12).setFill(); box.fill(); color.setStroke(); box.lineWidth = 0.9; box.stroke() }
            drawText(text, in: r, color: filled ? color : color, size: text.count > 1 ? 6.8 : 8.5, weight: .bold)
            return true
        }
    }

    private static func drawText(_ s: String, in r: NSRect, color: NSColor, size: CGFloat, weight: NSFont.Weight) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let t = NSAttributedString(string: s, attributes: attrs), ts = t.size()
        t.draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2))
    }
}
