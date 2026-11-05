import AppKit

/// PhpStorm-style file colours: which part of the project a path belongs to, so a change list shows at a glance
/// whether it touches real source, tests, or generated / third-party output.
enum PathScope {
    case tests, generated

    private static let generatedDirs: Set<String> = [
        "node_modules", "vendor", "dist", "build", ".next", ".nuxt", ".output", "coverage", ".idea", ".vscode", ".build",
    ]
    private static let testDirs: Set<String> = ["tests", "test", "__tests__", "spec", "specs", "e2e", "cypress", "__mocks__"]

    /// `path` is relative to the project root (as Git reports it) or absolute with `root` given.
    static func of(_ path: String, root: String? = nil) -> PathScope? {
        var rel = path
        if let root, path.hasPrefix(root + "/") { rel = String(path.dropFirst(root.count + 1)) }
        let parts = rel.split(separator: "/").map(String.init)
        guard let file = parts.last else { return nil }
        let dirs = parts.dropLast().map { $0.lowercased() }
        // Generated wins: public/build, storage/framework, bootstrap/cache, vendor, node_modules, dist ...
        for (i, d) in dirs.enumerated() {
            if generatedDirs.contains(d) { return .generated }
            if i + 1 < dirs.count, (d == "public" && dirs[i + 1] == "build") || (d == "storage" && dirs[i + 1] == "framework") || (d == "bootstrap" && dirs[i + 1] == "cache") { return .generated }
        }
        if file.hasSuffix(".min.js") || file.hasSuffix(".min.css") || file.hasSuffix(".map") { return .generated }
        if dirs.contains(where: testDirs.contains) { return .tests }
        let stem = (file as NSString).deletingPathExtension
        // FooTest.php / FooTests.php (capital T: not "Latest"), foo.test.ts, foo.spec.js, foo_test.py, foo-test.js
        if stem.hasSuffix("Test") || stem.hasSuffix("Tests") { return .tests }
        let l = stem.lowercased()
        if l.hasSuffix(".test") || l.hasSuffix(".spec") || l.hasSuffix("_test") || l.hasSuffix("-test") || l.hasPrefix("test_") { return .tests }
        return nil
    }

    var tint: NSColor {
        switch self {
        case .tests: return Self.dyn(NSColor(srgbRed: 0.40, green: 0.78, blue: 0.38, alpha: 0.20), NSColor(srgbRed: 0.40, green: 0.80, blue: 0.40, alpha: 0.16))
        case .generated: return Self.dyn(NSColor(srgbRed: 0.95, green: 0.78, blue: 0.25, alpha: 0.24), NSColor(srgbRed: 0.90, green: 0.72, blue: 0.25, alpha: 0.16))
        }
    }

    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}
