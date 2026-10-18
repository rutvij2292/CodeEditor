import Foundation

/// How a file is indented: `.editorconfig` first, then detected from the file's own content, else 4 spaces.
struct IndentSettings: Equatable {
    var useTabs: Bool
    var size: Int                       // columns per indent level and per tab stop

    static let standard = IndentSettings(useTabs: false, size: 4)
    var unit: String { useTabs ? "\t" : String(repeating: " ", count: size) }
    var label: String { useTabs ? "Tabs (\(size))" : "\(size) spaces" }

    static func resolve(for url: URL, text: String) -> IndentSettings {
        let ec = EditorConfig.settings(for: url)
        let detected = detect(text)
        return IndentSettings(useTabs: ec.useTabs ?? detected?.useTabs ?? false, size: ec.size ?? detected?.size ?? 4)
    }

    /// Looks at the first lines: tab-indented majority -> tabs; otherwise the most common positive indent step (2, 3, 4 or 8).
    static func detect(_ text: String) -> IndentSettings? {
        var tabLines = 0, spaceLines = 0, previous = 0
        var steps = [Int: Int]()
        var seen = 0
        for line in text.split(separator: "\n", maxSplits: 2000, omittingEmptySubsequences: true).prefix(2000) {
            guard let first = line.first, first == "\t" || first == " " else { previous = 0; continue }
            seen += 1
            if first == "\t" { tabLines += 1; continue }
            let width = line.prefix { $0 == " " }.count
            if line.dropFirst(width).isEmpty { continue }
            spaceLines += 1
            let delta = width - previous
            if (2...8).contains(delta) { steps[delta, default: 0] += 1 }
            previous = width
        }
        guard seen > 0 else { return nil }
        if tabLines > spaceLines { return IndentSettings(useTabs: true, size: 4) }
        // Prefer 4 on ties; ignore 6/5/7 which are artefacts of continuation lines.
        let candidates = [4, 2, 8, 3].compactMap { size in steps[size].map { (size, $0) } }
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 >= 3 else { return nil }
        return IndentSettings(useTabs: false, size: best.0)
    }
}

/// Minimal `.editorconfig` reader: indent_style, indent_size and tab_width with the usual glob rules.
enum EditorConfig {
    struct Result { var useTabs: Bool?; var size: Int? }

    private struct Section { let pattern: String; var props: [String: String] }
    private struct File { let dir: String; let isRoot: Bool; let sections: [Section] }
    private static var cache: [String: (Date?, File)] = [:]

    static func settings(for url: URL) -> Result {
        var files: [File] = []
        var dir = url.deletingLastPathComponent()
        while true {
            if let file = load(dir.appendingPathComponent(".editorconfig")) {
                files.append(file)
                if file.isRoot { break }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path || dir.path == "/" { break }
            dir = parent
        }
        var props: [String: String] = [:]
        for file in files.reversed() {             // outermost first, innermost wins
            let rel = url.path.hasPrefix(file.dir + "/") ? String(url.path.dropFirst(file.dir.count + 1)) : url.lastPathComponent
            for section in file.sections where matches(section.pattern, rel) { props.merge(section.props) { $1 } }
        }
        var result = Result()
        if let style = props["indent_style"]?.lowercased() { result.useTabs = style == "tab" }
        let tabWidth = props["tab_width"].flatMap { Int($0) }
        let indentSize = props["indent_size"]?.lowercased()
        let numericSize = indentSize.flatMap { Int($0) }
        if result.useTabs == true {
            result.size = tabWidth ?? numericSize           // a tab stop is as wide as tab_width (indent_size is the fallback)
        } else {
            result.size = indentSize == "tab" ? tabWidth : numericSize
        }
        if let size = result.size, !(1...16).contains(size) { result.size = nil }
        return result
    }

    private static func load(_ url: URL) -> File? {
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let hit = cache[url.path], hit.0 == date { return hit.1 }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var isRoot = false
        var sections: [Section] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append(Section(pattern: String(line.dropFirst().dropLast()), props: [:]))
            } else if let eq = line.firstIndex(of: "=") {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if sections.isEmpty { if key == "root" { isRoot = value.lowercased() == "true" } }
                else { sections[sections.count - 1].props[key] = value }
            }
        }
        let file = File(dir: url.deletingLastPathComponent().path, isRoot: isRoot, sections: sections)
        cache[url.path] = (date, file)
        return file
    }

    /// Converts an editorconfig glob (`*`, `**`, `?`, `{a,b}`, `[abc]`) to a regex over the path relative to the config's folder.
    private static func matches(_ pattern: String, _ relativePath: String) -> Bool {
        var out = ""
        var braces = 0
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            switch c {
            case "*":
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" { out += ".*"; i = next } else { out += "[^/]*" }
            case "?": out += "[^/]"
            case "{": braces += 1; out += "(?:"
            case "}": if braces > 0 { braces -= 1; out += ")" } else { out += "\\}" }
            case ",": out += braces > 0 ? "|" : ","
            case "[": out += "["
            case "]": out += "]"
            case ".", "(", ")", "+", "^", "$", "|", "\\": out += "\\" + String(c)
            default: out.append(c)
            }
            i = pattern.index(after: i)
        }
        let anchored = pattern.contains("/")
        let body = anchored ? "^" + (out.hasPrefix("/") ? String(out.dropFirst()) : out) + "$" : "(?:^|.*/)" + out + "$"
        guard let regex = try? NSRegularExpression(pattern: body) else { return false }
        return regex.firstMatch(in: relativePath, range: NSRange(location: 0, length: (relativePath as NSString).length)) != nil
    }
}
