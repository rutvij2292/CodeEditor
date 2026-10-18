import Foundation

/// File types that get a viewer pane next to (or instead of) the source: Markdown preview, JSON / YAML structure tree.
enum ViewerKind: String {
    case markdown, json, yaml

    static func detect(_ url: URL) -> ViewerKind? {
        let name = url.lastPathComponent.lowercased()
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mkd", "mdx": return .markdown
        case "json", "jsonc", "json5", "webmanifest", "geojson": return .json
        case "yml", "yaml": return .yaml
        default: break
        }
        if [".eslintrc", ".babelrc", ".prettierrc", ".swcrc", "composer.lock"].contains(name) { return .json }
        return nil
    }

    /// Third segment of the Source | Split | X control.
    var previewTitle: String { self == .markdown ? "Preview" : "Tree" }
    var defaultMode: ViewerMode { self == .markdown ? .split : .source }
    var title: String { self == .markdown ? "Markdown" : (self == .json ? "JSON" : "YAML") }

    /// Remembered mode for this file type (Prefs `viewerMode.<kind>`).
    var mode: ViewerMode {
        get { ViewerMode(rawValue: Prefs.viewerMode(rawValue, fallback: defaultMode.rawValue)) ?? defaultMode }
        nonmutating set { Prefs.setViewerMode(rawValue, newValue.rawValue) }
    }
}

enum ViewerMode: String, CaseIterable {
    case source, split, preview
    var next: ViewerMode { self == .source ? .split : (self == .split ? .preview : .source) }
    var segment: Int { self == .source ? 0 : (self == .split ? 1 : 2) }
    init(segment: Int) { self = segment == 0 ? .source : (segment == 1 ? .split : .preview) }
}

/// JSON files that allow comments / trailing commas (tsconfig, .eslintrc, ...) and so are never reported as invalid for them.
enum JSONFlavor {
    static func isLenient(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "jsonc" || ext == "json5" { return true }
        let n = url.lastPathComponent.lowercased()
        return n.hasPrefix("tsconfig") || n.hasPrefix("jsconfig") || n.hasPrefix(".eslintrc") || n == ".babelrc" || n == ".swcrc"
            || n.hasSuffix(".code-workspace") || n == "settings.json" || n == "launch.json" || n == "tasks.json"
    }
}
