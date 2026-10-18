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
