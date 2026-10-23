import AppKit

// Pure logic behind the Claude prompt composer (ClaudeComposer.swift) and "Fix with Claude" (ClaudeComposerWiring.swift):
// `@` / `/` token detection, slash-command + skill scanning (lazy, only when the composer opens a `/` list), prompt history,
// pasted-image files and the prepared prompts. Nothing here holds state beyond a ~50 entry history and one draft string.

/// A slash command (`.claude/commands/**/*.md`) or skill (`.claude/skills/<name>/SKILL.md`).
struct SlashEntry: Equatable {
    var name: String
    var detail: String
    var isSkill: Bool
    var isProject: Bool
}

enum ComposerToken: Equatable {
    case file(query: String, range: NSRange)     // range covers the whole `@query`
    case slash(query: String, range: NSRange)    // range covers the whole `/query`
}

enum ClaudeComposerLogic {
    // MARK: tokens

    /// The `@file` or `/command` token that ends at `caret`. `/` only counts at the start of the prompt or of a line.
    static func token(in text: NSString, caret: Int) -> ComposerToken? {
        let caret = max(0, min(caret, text.length))
        var start = caret
        while start > 0 {
            let c = text.character(at: start - 1)
            if c == 32 || c == 10 || c == 9 || c == 13 { break }
            start -= 1
        }
        guard start < caret else { return nil }
        let range = NSRange(location: start, length: caret - start)
        let word = text.substring(with: range)
        if word.hasPrefix("@") { return .file(query: String(word.dropFirst()), range: range) }
        if word.hasPrefix("/"), start == 0 || text.character(at: start - 1) == 10 { return .slash(query: String(word.dropFirst()), range: range) }
        return nil
    }

    /// Text and caret after accepting a completion for `token`.
    static func apply(_ replacement: String, to text: String, token: ComposerToken) -> (text: String, caret: Int) {
        let range: NSRange
        switch token { case .file(_, let r), .slash(_, let r): range = r }
        let ns = text as NSString
        let tail = NSMaxRange(range) < ns.length && ns.character(at: NSMaxRange(range)) == 32 ? "" : " "
        let out = ns.replacingCharacters(in: range, with: replacement + tail)
        return (out, range.location + (replacement as NSString).length + 1)
    }

    // MARK: slash commands and skills

    /// Reads command / skill names + descriptions from the project and user `.claude` folders. Files are only listed, and only the
    /// head of each is read, so a big skills library costs a few KB for the lifetime of the popup list.
    static func scanSlashEntries(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SlashEntry] {
        var out: [SlashEntry] = []
        for (base, isProject) in [(root, true), (home, false)] {
            let claude = base.appendingPathComponent(".claude")
            out += commands(in: claude.appendingPathComponent("commands"), isProject: isProject)
            out += skills(in: claude.appendingPathComponent("skills"), isProject: isProject)
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.name).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func commands(in dir: URL, isProject: Bool) -> [SlashEntry] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var out: [SlashEntry] = []
        let base = dir.standardizedFileURL.path + "/"
        for case let url as URL in en where url.pathExtension == "md" {
            var rel = String(url.standardizedFileURL.path.dropFirst(min(base.count, url.standardizedFileURL.path.count)))
            rel = String(rel.dropLast(3)).replacingOccurrences(of: "/", with: ":")
            guard !rel.isEmpty else { continue }
            out.append(SlashEntry(name: rel, detail: describe(url), isSkill: false, isProject: isProject))
            if out.count >= 500 { break }
        }
        return out
    }

    private static func skills(in dir: URL, isProject: Bool) -> [SlashEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [SlashEntry] = []
        for n in names.prefix(500) where !n.hasPrefix(".") {
            let file = dir.appendingPathComponent(n).appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: file.path) else { continue }
            let meta = frontmatter(of: file)
            out.append(SlashEntry(name: meta["name"].flatMap { $0.isEmpty ? nil : $0 } ?? n, detail: meta["description"] ?? "", isSkill: true, isProject: isProject))
        }
        return out
    }

    /// Frontmatter `description`, else the first non-empty body line.
    private static func describe(_ url: URL) -> String {
        let head = headText(url)
        let meta = parseFrontmatter(head)
        if let d = meta["description"], !d.isEmpty { return d }
        var inFront = head.hasPrefix("---")
        var skipped = false
        for raw in head.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if inFront { if skipped, line == "---" { inFront = false }; skipped = true; continue }
            if line.isEmpty { continue }
            return String(line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).prefix(120))
        }
        return ""
    }

    private static func headText(_ url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        return String(decoding: (try? h.read(upToCount: 4096)) ?? Data(), as: UTF8.self)
    }

    private static func frontmatter(of url: URL) -> [String: String] { parseFrontmatter(headText(url)) }

    /// `key: value` lines between the leading `---` fences (values may be quoted; only single-line values).
    static func parseFrontmatter(_ text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
        guard lines.first == "---" else { return [:] }
        var out: [String: String] = [:]
        for line in lines.dropFirst() {
            if line == "---" { break }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f { value = String(value.dropFirst().dropLast()) }
            out[key] = value
        }
        return out
    }

    /// Fuzzy-filtered, best first (an empty query lists everything in name order).
    static func filter(_ entries: [SlashEntry], query: String, limit: Int = 50) -> [SlashEntry] {
        if query.isEmpty { return Array(entries.prefix(limit)) }
        let scored: [(Int, SlashEntry)] = entries.compactMap { e in
            Fuzzy.score(query: query, in: e.name).map { ($0, e) }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }

    // MARK: pasted images

    static let imageDirName = "kode-prompt-images"

    /// Writes PNG `data` to a temp file (older pasted images are removed first) and returns its path.
    static func saveImage(_ png: Data, now: Date = Date()) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(imageDirName, isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, now.timeIntervalSince(d) > 86_400 { try? fm.removeItem(at: f) }
        }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = dir.appendingPathComponent("paste-\(f.string(from: now)).png")
        do { try png.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - History and draft

/// Last prompts sent from the composer (newest first), persisted in UserDefaults (memory only when headless), plus the unsent draft.
enum PromptHistory {
    static let limit = 50
    private static let key = "claude.promptHistory"
    private static var memory: [String] = []
    /// Unsent text kept when the composer is closed with Esc.
    static var draft = ""

    static var entries: [String] {
        get { AppEnv.headless ? memory : (UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { if AppEnv.headless { memory = newValue } else { UserDefaults.standard.set(newValue, forKey: key) } }
    }

    static func push(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = entries.filter { $0 != t }
        list.insert(t, at: 0)
        entries = Array(list.prefix(limit))
    }

    static func reset() { entries = []; draft = "" }
}

/// Up / Down through `PromptHistory` while the box is empty or showing a history entry.
struct HistoryCursor {
    private(set) var index = -1                  // -1 = not browsing
    var browsing: Bool { index >= 0 }

    /// Next text to show for Up (older) or Down (newer); nil = nothing to do. Down past the newest returns "".
    mutating func step(older: Bool, entries: [String]) -> String? {
        if older {
            guard index + 1 < entries.count else { return nil }
            index += 1
            return entries[index]
        }
        guard index >= 0 else { return nil }
        index -= 1
        return index >= 0 ? entries[index] : ""
    }

    mutating func reset() { index = -1 }
}

// MARK: - Prepared prompts ("Fix with Claude")

enum FixWithClaude {
    /// 1-based line numbers `line - context ... line + context` of `text` clamped to the file, with that slice of text.
    static func snippet(of text: String, around line: Int, context: Int = 6) -> (start: Int, end: Int, text: String)? {
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty, line >= 1 else { return nil }
        let l = min(line, lines.count)
        let s = max(1, l - context), e = min(lines.count, l + context)
        return (s, e, lines[(s - 1)..<e].joined(separator: "\n"))
    }

    static func problemPrompt(path: String, line: Int, column: Int, severity: Int, message: String, source: String?, code: String?,
                              fileText: String?) -> String {
        var tag = [source, code].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !tag.isEmpty { tag = " [\(tag)]" }
        var s = "Fix this \(TerminalBridge.severityName(severity)) in \(path):\n\n"
        s += "\(path):\(line):\(column) \(TerminalBridge.severityName(severity)): \(message.replacingOccurrences(of: "\n", with: " "))\(tag)\n\n"
        if let fileText, let snip = snippet(of: fileText, around: line) {
            s += TerminalBridge.fencedBlock(path: path, start: snip.start, end: snip.end, text: snip.text) + "\n"
        }
        s += "Make the smallest change that resolves it, and tell me what you changed.\n"
        return s
    }

    static func testPrompt(_ r: TestResult, path: String, fileText: String?) -> String {
        let name = (r.className.map { $0 + "::" } ?? "") + r.name
        var s = "This test fails: \(name)\n"
        if !path.isEmpty { s += "File: \(path):\(r.failureLine)\n" }
        s += "\nFailure output:\n```\n\(String(r.message.prefix(4000)))\n```\n\n"
        if let fileText, !path.isEmpty, let snip = snippet(of: fileText, around: r.failureLine) {
            s += TerminalBridge.fencedBlock(path: path, start: snip.start, end: snip.end, text: snip.text) + "\n"
        }
        s += "Find the cause (the test or the code under test), fix it, and re-run the test to confirm.\n"
        return s
    }

    static func selectionPrompt(_ terminalText: String) -> String {
        var body = terminalText
        if body.count > 8000 { body = "..." + String(body.suffix(8000)) }
        var fence = "```"
        while body.contains(fence) { fence += "`" }
        return "Explain what this terminal output means and what I should do about it:\n\n\(fence)\n\(body)\n\(fence)\n"
    }

    static func diffReviewPrompt(branch: String?, changes: [GitChange], stat: String?) -> String {
        var s = "Review my current uncommitted changes" + (branch.map { " on branch \($0)" } ?? "") + ". Run `git diff HEAD` (and read the untracked files listed) to see them, then point out bugs, risky edge cases, missing tests and anything that does not match the surrounding code style. Do not edit files; list findings by file:line.\n\n"
        s += TerminalBridge.changeSummary(branch: branch, changes: changes, stat: stat)
        return s
    }
}

extension LanguageServers {
    /// Set once by ClaudeComposerWiring: the "Fix with Claude" entry of the editor's Quick Fix picker.
    static var fixWithClaude: ((LSPSession) -> Void)?
}
