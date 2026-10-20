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

// MARK: Drawn icons (tree rows): outline folders and tinted document shapes, 16 pt, paths from the Explorer design

extension FileIcon {
    private static var cache: [String: NSImage] = [:]

    /// Icon for a tree row: closed / open folder, or a document tinted by file type.
    static func treeImage(name: String, isDirectory: Bool, expanded: Bool = false) -> NSImage {
        let key: String
        if isDirectory { key = expanded ? "dir.open" : "dir" }
        else { key = documentKey(name) }
        let cacheKey = key + (Theme.isDark ? ".d" : ".l")
        if let img = cache[cacheKey] { return img }
        let img = key.hasPrefix("dir") ? folder(open: expanded) : document(tint: tint(forKey: key), label: label(forKey: key))
        cache[cacheKey] = img
        return img
    }

    /// Dropped on a theme change so dark / light variants are redrawn.
    static func resetTreeIcons() { cache.removeAll() }

    private static func documentKey(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if name == "artisan" { return "php" }
        if name.hasPrefix(".env") { return "env" }
        if ext == "php", name.hasSuffix(".blade.php") { return "blade" }
        if ext == "php", name.first?.isUppercase == true { return "php.class" }
        if ext == "mjs" || ext == "cjs" || ext == "jsx" { return "js" }
        if ext == "tsx" || ext == "mts" { return "ts" }
        if ext == "markdown" { return "md" }
        if ext == "jsonc" { return "json" }
        if ["scss", "sass", "less"].contains(ext) { return "css" }
        if ["yml", "yaml"].contains(ext) { return "yml" }
        if ["png", "jpg", "jpeg", "gif", "webp", "svg", "ico"].contains(ext) { return "img" }
        return ext.isEmpty ? "plain" : ext
    }

    private static func tintHex(_ key: String) -> UInt32 {
        switch key {
        case "vue": return 0x23885A
        case "js": return 0x9A7300
        case "php", "php.class": return 0x5B59C2
        case "blade": return 0xE0533D
        case "env": return 0xB4530F
        case "ts": return 0x3178C6
        case "css": return 0x2F9DB8
        case "html", "htm", "xml": return 0xC2570C
        case "md": return 0x4E7FD6
        case "json": return 0x8F5CC7
        case "yml": return 0xC24A4A
        case "img": return 0xC2418A
        default: return 0x6B7280     // .editorconfig, .gitignore, plain text and anything unknown
        }
    }

    /// Short type prefix drawn on the badge, so PHP / Blade / JS / etc. stay readable at a glance.
    private static func label(forKey key: String) -> String? {
        switch key {
        case "php", "php.class": return "php"
        case "blade": return "blade"
        case "js": return "JS"
        case "ts": return "TS"
        case "vue": return "V"
        case "css": return "#"
        case "html", "htm", "xml": return "<>"
        case "md": return "M↓"
        case "json": return "{}"
        case "yml": return "Y"
        case "env": return "env"
        default: return nil
        }
    }

    private static func tint(forKey key: String) -> NSColor { Theme.hex(tintHex(key)) }

    /// 16×16 image drawn top-left origin so the coordinates read like the design's SVG viewBox.
    private static func canvas(_ draw: @escaping () -> Void) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in draw(); return true }
    }

    private static func stroke(_ path: NSBezierPath, _ color: NSColor, fill alpha: CGFloat?) {
        if let alpha { color.withAlphaComponent(alpha).setFill(); path.fill() }
        color.setStroke(); path.lineWidth = 1.3; path.lineJoinStyle = .round; path.stroke()
    }

    private static func folder(open: Bool) -> NSImage {
        let color = Theme.hex(Theme.isDark ? 0x8B96A8 : 0x6F7988)
        return canvas {
            if !open {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 2, y: 4.5))
                p.curve(to: NSPoint(x: 3.5, y: 3), controlPoint1: NSPoint(x: 2, y: 3.67), controlPoint2: NSPoint(x: 2.67, y: 3))
                p.line(to: NSPoint(x: 6.1, y: 3)); p.line(to: NSPoint(x: 7.5, y: 4.5)); p.line(to: NSPoint(x: 12.5, y: 4.5))
                p.curve(to: NSPoint(x: 14, y: 6), controlPoint1: NSPoint(x: 13.33, y: 4.5), controlPoint2: NSPoint(x: 14, y: 5.17))
                p.line(to: NSPoint(x: 14, y: 11.5))
                p.curve(to: NSPoint(x: 12.5, y: 13), controlPoint1: NSPoint(x: 14, y: 12.33), controlPoint2: NSPoint(x: 13.33, y: 13))
                p.line(to: NSPoint(x: 3.5, y: 13))
                p.curve(to: NSPoint(x: 2, y: 11.5), controlPoint1: NSPoint(x: 2.67, y: 13), controlPoint2: NSPoint(x: 2, y: 12.33))
                p.close()
                stroke(p, color, fill: 0.12)
                return
            }
            let back = NSBezierPath()
            back.move(to: NSPoint(x: 2, y: 11.5)); back.line(to: NSPoint(x: 2, y: 4.5))
            back.curve(to: NSPoint(x: 3.5, y: 3), controlPoint1: NSPoint(x: 2, y: 3.67), controlPoint2: NSPoint(x: 2.67, y: 3))
            back.line(to: NSPoint(x: 6.1, y: 3)); back.line(to: NSPoint(x: 7.5, y: 4.5)); back.line(to: NSPoint(x: 11.5, y: 4.5))
            back.curve(to: NSPoint(x: 13, y: 6), controlPoint1: NSPoint(x: 12.33, y: 4.5), controlPoint2: NSPoint(x: 13, y: 5.17))
            back.line(to: NSPoint(x: 13, y: 7))
            stroke(back, color, fill: nil)
            let front = NSBezierPath()
            front.move(to: NSPoint(x: 2, y: 11.5)); front.line(to: NSPoint(x: 3.6, y: 7.9))
            front.curve(to: NSPoint(x: 5, y: 7), controlPoint1: NSPoint(x: 3.85, y: 7.35), controlPoint2: NSPoint(x: 4.4, y: 7))
            front.line(to: NSPoint(x: 13.3, y: 7))
            front.curve(to: NSPoint(x: 14, y: 8.1), controlPoint1: NSPoint(x: 13.8, y: 7), controlPoint2: NSPoint(x: 14.15, y: 7.65))
            front.line(to: NSPoint(x: 12.6, y: 12))
            front.curve(to: NSPoint(x: 11.2, y: 13), controlPoint1: NSPoint(x: 12.4, y: 12.55), controlPoint2: NSPoint(x: 11.8, y: 13))
            front.line(to: NSPoint(x: 3.5, y: 13))
            front.curve(to: NSPoint(x: 2, y: 11.5), controlPoint1: NSPoint(x: 2.67, y: 13), controlPoint2: NSPoint(x: 2, y: 12.33))
            front.close()
            stroke(front, color, fill: 0.15)
        }
    }

    private static func document(tint: NSColor, label: String?) -> NSImage {
        let color = Theme.isDark ? tint.blended(withFraction: 0.25, of: .white) ?? tint : tint
        if let label {
            return canvas {
                let box = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 3, width: 15, height: 10), xRadius: 2.5, yRadius: 2.5)
                color.withAlphaComponent(0.16).setFill(); box.fill()
                color.setStroke(); box.lineWidth = 1; box.stroke()
                let size: CGFloat = label.count >= 5 ? 5.2 : label.count == 3 ? 6.2 : label.count == 2 ? 6.8 : 8
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: color]
                let t = NSAttributedString(string: label, attributes: attrs), ts = t.size()
                t.draw(at: NSPoint(x: 8 - ts.width / 2, y: 8 - ts.height / 2))
            }
        }
        return canvas {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 4.5, y: 2)); p.line(to: NSPoint(x: 9.3, y: 2)); p.line(to: NSPoint(x: 12, y: 4.7))
            p.line(to: NSPoint(x: 12, y: 13.5))
            p.curve(to: NSPoint(x: 11.5, y: 14), controlPoint1: NSPoint(x: 12, y: 13.78), controlPoint2: NSPoint(x: 11.78, y: 14))
            p.line(to: NSPoint(x: 4.5, y: 14))
            p.curve(to: NSPoint(x: 4, y: 13.5), controlPoint1: NSPoint(x: 4.22, y: 14), controlPoint2: NSPoint(x: 4, y: 13.78))
            p.line(to: NSPoint(x: 4, y: 2.5))
            p.curve(to: NSPoint(x: 4.5, y: 2), controlPoint1: NSPoint(x: 4, y: 2.22), controlPoint2: NSPoint(x: 4.22, y: 2))
            p.close()
            stroke(p, color, fill: 0.14)
        }
    }
}
