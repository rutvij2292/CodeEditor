import Foundation
import SwiftTreeSitter
import TreeSitterPHP
import TreeSitterJavaScript
import TreeSitterHTML
import TreeSitterCSS
import TreeSitterJSON

/// Maps file extensions to tree-sitter grammars. Configurations are built lazily
/// and cached, so only languages you actually open cost memory.
enum Languages {
    private static var cache: [String: LanguageConfiguration] = [:]

    /// SwiftPM resource bundles keep `queries/` at the bundle root (flat layout), while
    /// SwiftTreeSitter's own lookup expects `Contents/Resources/`. Accept both, next to the
    /// executable or inside an .app's Resources.
    private static func queriesURL(for name: String) -> URL? {
        let bundle = "TreeSitter\(name)_TreeSitter\(name).bundle"
        let roots = [Bundle.main.bundleURL, Bundle.main.resourceURL,
                     Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        for root in roots {
            for sub in ["", "Contents/Resources/"] {
                let url = root.appendingPathComponent(bundle).appendingPathComponent(sub + "queries")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    private static func make(_ language: OpaquePointer, _ name: String) -> LanguageConfiguration? {
        guard let url = queriesURL(for: name) else { return nil }
        return try? LanguageConfiguration(language, name: name, queriesURL: url)
    }

    static func configuration(forExtension ext: String) -> LanguageConfiguration? {
        let key: String
        switch ext.lowercased() {
        case "php", "phtml": key = "php"
        case "js", "jsx", "mjs", "cjs": key = "js"
        case "html", "htm", "vue": key = "html"
        case "css": key = "css"
        case "json": key = "json"
        default: return nil
        }
        if let c = cache[key] { return c }
        let config: LanguageConfiguration?
        switch key {
        case "php": config = make(tree_sitter_php(), "PHP")
        case "js": config = make(tree_sitter_javascript(), "JavaScript")
        case "html": config = make(tree_sitter_html(), "HTML")
        case "css": config = make(tree_sitter_css(), "CSS")
        default: config = make(tree_sitter_json(), "JSON")
        }
        if let config { cache[key] = config }
        return config
    }
}
