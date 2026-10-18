import AppKit

/// `php artisan route:list --json` as picker rows; Enter jumps to the controller method (or the route declaration for closures).
enum RouteBrowser {
    static func shortAction(_ action: String) -> String {
        if action == "Closure" || action.isEmpty { return "Closure" }
        let parts = action.components(separatedBy: "@")
        let cls = parts[0].split(separator: "\\").last.map(String.init) ?? parts[0]
        return parts.count > 1 ? "\(cls)@\(parts[1])" : cls
    }

    static func items(_ routes: [ArtisanRoute], open: @escaping (ArtisanRoute) -> Void) -> [PickerItem] {
        routes.map { r in
            // Name rides in the title: the picker truncates details from the head, and the action is the short part.
            return PickerItem(title: "\(r.displayMethod)  \(r.uri)" + (r.name.isEmpty ? "" : "   \(r.name)"), detail: shortAction(r.action), symbol: "arrow.triangle.branch",
                              key: "\(r.displayMethod) \(r.uri) \(r.name) \(r.action)") { open(r) }
        }
    }

    /// Controller method for the route (reusing the Laravel resolver), else the route declaration, else nil.
    static func target(for route: ArtisanRoute, in p: LaravelProject) -> LaravelTarget? {
        if route.action != "Closure", !route.action.isEmpty {
            let parts = route.action.components(separatedBy: "@")
            let method = parts.count > 1 ? parts[1] : "__invoke"
            if let t = LaravelResolver.controllerMethod(parts[0], method, p).first { return t }
        }
        return declaration(of: route, in: p)
    }

    /// First routes/*.php line that mentions the URI (or its trailing segments, since groups hide prefixes).
    static func declaration(of route: ArtisanRoute, in p: LaravelProject) -> LaravelTarget? {
        let segments = route.uri.split(separator: "/").map(String.init)
        var needles: [String] = segments.isEmpty ? ["/"] : (0..<segments.count).map { segments[$0...].joined(separator: "/") }
        if !route.name.isEmpty { needles.insert(route.name, at: 0) }
        let files = LaravelRouteIndex.routeFiles(p).filter { $0.contains("/routes/") }
        for needle in needles {
            let esc = NSRegularExpression.escapedPattern(for: needle)
            guard let re = try? NSRegularExpression(pattern: "['\"]/?" + esc + "['\"]") else { continue }
            for f in files {
                guard let text = LaravelFS.text(f) else { continue }
                if let m = re.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) {
                    let (line, col) = LaravelFS.lineCol(text, m.range.location)
                    return p.target(f, line: line, column: col)
                }
            }
        }
        return nil
    }
}
