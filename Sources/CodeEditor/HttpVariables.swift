import Foundation

/// `http-client.env.json` (+ `http-client.private.env.json`) environments and the project's `.env`.
enum HttpEnvironments {
    static let publicName = "http-client.env.json"
    static let privateName = "http-client.private.env.json"

    /// Environment file contents: env name -> variables. The private file's values win per variable.
    static func load(near file: URL, root: URL?) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for dir in searchDirs(file: file, root: root) {
            for name in [publicName, privateName] {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                for (env, vars) in obj {
                    guard let vars = vars as? [String: Any] else { continue }
                    for (k, v) in vars { result[env, default: [:]][k] = stringify(v) }
                }
            }
        }
        return result
    }

    /// The file's own directory first (its values win), then every parent up to the project root.
    private static func searchDirs(file: URL, root: URL?) -> [URL] {
        var dirs: [URL] = []
        var d = file.deletingLastPathComponent().standardizedFileURL
        let stop = root?.standardizedFileURL.path
        while true {
            dirs.append(d)
            if d.path == stop || d.path == "/" || stop == nil || !d.path.hasPrefix(stop!) { break }
            d = d.deletingLastPathComponent()
        }
        return dirs.reversed()   // outermost first, so nearer files override
    }

    static func names(_ envs: [String: [String: String]]) -> [String] { envs.keys.filter { $0 != "$shared" }.sorted() }

    /// Variables visible in `env`: `$shared` overlaid with the selected environment.
    static func variables(_ envs: [String: [String: String]], env: String?) -> [String: String] {
        var out = envs["$shared"] ?? [:]
        if let env, let e = envs[env] { for (k, v) in e { out[k] = v } }
        return out
    }

    private static func stringify(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if v is NSNull { return "" }
        if let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) { return String(decoding: d, as: UTF8.self) }
        return "\(v)"
    }

    /// `KEY=value` lines of a dotenv file (quotes stripped, `export ` and comments ignored).
    static func parseDotenv(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let q = value.first, q == "\"" || q == "'", let close = value.dropFirst().firstIndex(of: q) {
                value = String(value[value.index(after: value.startIndex)..<close])
            } else if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    static func loadDotenv(root: URL?) -> [String: String] {
        guard let root, let text = try? String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8) else { return [:] }
        return parseDotenv(text)
    }
}

/// Everything `{{name}}` can resolve against, in priority order: dynamic `$` variables, chained responses, `@vars` of the file,
/// the selected environment, the project's `.env`.
struct HttpResolver {
    var fileVariables: [String: String] = [:]
    var environment: [String: String] = [:]
    var dotenv: [String: String] = [:]
    /// Named responses of earlier runs (`# @name login` then `{{login.response.body.$.token}}`).
    var responses: [String: HttpResponse] = [:]

    struct Result { var text: String; var unresolved: [String] }

    /// Names of the responses `text` refers to (`{{name.response...}}`).
    static func referencedResponses(in text: String) -> [String] {
        var out: [String] = []
        for expr in templates(in: text) {
            let parts = expr.components(separatedBy: ".")
            if parts.count >= 3, parts[1] == "response" || parts[1] == "request", !out.contains(parts[0]) { out.append(parts[0]) }
        }
        return out
    }

    static func templates(in text: String) -> [String] {
        var out: [String] = []
        var rest = text[...]
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            out.append(rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces))
            rest = rest[close.upperBound...]
        }
        return out
    }

    func expand(_ text: String) -> Result { expand(text, depth: 0) }

    private func expand(_ text: String, depth: Int) -> Result {
        guard text.contains("{{") else { return Result(text: text, unresolved: []) }
        var out = ""
        var unresolved: [String] = []
        var rest = text[...]
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            guard let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) else { out += rest[open.lowerBound...]; rest = ""; break }
            let expr = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if let v = lookup(expr) {
                if depth < 5, v.contains("{{") {
                    let inner = expand(v, depth: depth + 1)
                    out += inner.text; unresolved += inner.unresolved
                } else { out += v }
            } else {
                out += rest[open.lowerBound..<close.upperBound]
                unresolved.append(expr)
            }
            rest = rest[close.upperBound...]
        }
        out += rest
        return Result(text: out, unresolved: unresolved)
    }

    private func lookup(_ expr: String) -> String? {
        if expr.hasPrefix("$") { return Self.dynamic(expr) }
        if let v = fileVariables[expr] ?? environment[expr] ?? dotenv[expr] { return v }
        let parts = expr.components(separatedBy: ".")
        if parts.count >= 3, parts[1] == "response", let r = responses[parts[0]] { return Self.chain(r, Array(parts.dropFirst(2)), expr: expr) }
        return nil
    }

    /// `body.$.a.b[0]`, `body.*`, `headers.Content-Type`.
    private static func chain(_ r: HttpResponse, _ parts: [String], expr: String) -> String? {
        switch parts.first {
        case "headers":
            guard parts.count >= 2 else { return nil }
            let name = parts.dropFirst().joined(separator: ".")
            return r.headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        case "body":
            guard let text = r.bodyText else { return nil }
            guard parts.count >= 2 else { return text }
            let path = parts.dropFirst().joined(separator: ".")
            if path == "*" { return text }
            guard path.hasPrefix("$") else { return nil }
            guard let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
            return JSONPath.evaluate(path, in: json)
        default: return nil
        }
    }

    private static func dynamic(_ expr: String) -> String? {
        let parts = expr.split(separator: " ").map(String.init)
        switch parts.first {
        case "$uuid", "$random.uuid": return UUID().uuidString.lowercased()
        case "$timestamp": return String(Int(Date().timeIntervalSince1970))
        case "$isoTimestamp": return ISO8601DateFormatter().string(from: Date())
        case "$randomInt", "$random.integer":
            var lo = 0, hi = 1000
            if parts.count >= 3, let a = Int(parts[1]), let b = Int(parts[2]), a <= b { lo = a; hi = b }
            return String(Int.random(in: lo...hi))
        default: return nil
        }
    }
}

/// The small JSONPath subset response chaining needs: `$`, `.key`, `['key']`, `[0]`, `[-1]`.
enum JSONPath {
    static func evaluate(_ path: String, in root: Any) -> String? {
        var cur: Any = root
        let chars = Array(path)
        var i = 0
        guard i < chars.count, chars[i] == "$" else { return nil }
        i += 1
        while i < chars.count {
            if chars[i] == "." {
                i += 1
                var key = ""
                while i < chars.count, chars[i] != ".", chars[i] != "[" { key.append(chars[i]); i += 1 }
                guard !key.isEmpty, let d = cur as? [String: Any], let v = d[key] else { return nil }
                cur = v
            } else if chars[i] == "[" {
                guard let close = chars[i...].firstIndex(of: "]") else { return nil }
                var inner = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespaces)
                i = close + 1
                if let q = inner.first, q == "'" || q == "\"", inner.last == q, inner.count >= 2 {
                    inner = String(inner.dropFirst().dropLast())
                    guard let d = cur as? [String: Any], let v = d[inner] else { return nil }
                    cur = v
                } else if let idx = Int(inner), let a = cur as? [Any] {
                    let k = idx < 0 ? a.count + idx : idx
                    guard k >= 0, k < a.count else { return nil }
                    cur = a[k]
                } else { return nil }
            } else { return nil }
        }
        if let s = cur as? String { return s }
        if let n = cur as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if cur is NSNull { return "null" }
        if let d = try? JSONSerialization.data(withJSONObject: cur, options: [.fragmentsAllowed]) { return String(decoding: d, as: UTF8.self) }
        return nil
    }
}
