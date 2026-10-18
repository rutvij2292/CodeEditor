import Foundation

/// Product identity in one place. Internal identifiers (bundle id, Application Support / Caches folders, defaults keys)
/// keep their original "CodeEditor" names so existing settings, sessions and history carry over.
enum Brand {
    static let name = "Kode"
    static let tagline = "A light, native code editor"
    static let repoURL = "https://github.com/rutvij2292/CodeEditor"
}
