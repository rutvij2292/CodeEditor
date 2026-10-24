import AppKit

// Native PHP diagnostics (phase 2c): syntax (tree-sitter), undefined classes, imports, variables, members, argument counts.
// Everything is on demand: one debounced pass per edited active file, on the project's fast-tier queue, size and result
// capped. Precision beats recall: every rule stays silent when it cannot be certain (see docs/native-php.md).

/// One native finding in UTF-16 offsets of the analysed text.
struct NPDiag: Equatable {
    var range: NSRange
    var severity: Int           // 1 error, 2 warning, 3 info, 4 hint
    var message: String
    var code: String
    var group: NPDiagGroup
}

enum NPDiagGroup: String, CaseIterable {
    case syntax, classes, imports, variables, members, args

    var key: String { "php.diag." + rawValue }
    var title: String {
        switch self {
        case .syntax: return "Syntax errors"
        case .classes: return "Undefined classes"
        case .imports: return "Unused and duplicate imports"
        case .variables: return "Undefined variables"
        case .members: return "Undefined methods and properties"
        case .args: return "Wrong argument count"
        }
    }
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum NativePHPDiag {
    static let classSeverityKey = "php.diag.classSeverity"
    /// Severity of "undefined class" findings: 1 error, 2 warning (default).
    static var classSeverity: Int {
        get { let v = UserDefaults.standard.object(forKey: classSeverityKey) as? Int ?? 2; return v == 1 ? 1 : 2 }
        set { UserDefaults.standard.set(newValue == 1 ? 1 : 2, forKey: classSeverityKey) }
    }
    static func resetPrefs() {
        for g in NPDiagGroup.allCases { UserDefaults.standard.removeObject(forKey: g.key) }
        UserDefaults.standard.removeObject(forKey: classSeverityKey)
    }
    static var enabledGroups: Set<NPDiagGroup> { Set(NPDiagGroup.allCases.filter { $0.enabled }) }

    static let maxBytes = 600_000          // larger files get syntax checking only
    static let maxTokens = 150_000
    static let maxResults = 200

    static func handles(_ url: URL) -> Bool {
        let n = url.lastPathComponent.lowercased()
        if PHPStubs.isStubFile(url.standardizedFileURL.path) { return false }   // bundled built-in stubs are read-only
        if n.hasSuffix(".blade.php") { return false }              // Blade templates: embedded PHP is never checked
        if n.hasPrefix(".phpstorm.meta") || n.hasPrefix("_ide_helper") || n.hasPrefix("phpstorm.meta") { return false }   // IDE stubs
        return n.hasSuffix(".php") || n.hasSuffix(".phtml")
    }

    /// Whole analysis of `text`. Must run on the project's fast-tier queue when `fp` is given (semantic rules need it).
    /// Syntax errors suppress every semantic rule (the token stream cannot be trusted).
    static func analyze(url: URL, text: NSString, fp: FastProject?, groups: Set<NPDiagGroup> = Set(NPDiagGroup.allCases),
                        classSeverity: Int = NativePHPDiag.classSeverity) -> [NPDiag] {
        guard handles(url), text.length > 0 else { return [] }
        var out: [NPDiag] = []
        if groups.contains(.syntax) {
            out += NPDiagSyntax.check(text)
            if !out.isEmpty { return out }
        } else if NPDiagSyntax.hasSyntaxError(text) { return [] }
        guard let fp, text.length <= maxBytes, isPureCode(text) else { return out }
        let lex = PHPLex(text)
        guard lex.count > 0, lex.count <= maxTokens else { return out }
        fp.beginRequest()
        let ctx = NPDiagContext(fp: fp, url: url, text: text, lex: lex, classSeverity: classSeverity)
        if groups.contains(.classes) || groups.contains(.imports) { out += ctx.namesPass(classes: groups.contains(.classes), imports: groups.contains(.imports)) }
        if groups.contains(.variables) { out += ctx.variablesPass() }
        if groups.contains(.members) || groups.contains(.args) { out += ctx.membersPass(members: groups.contains(.members), args: groups.contains(.args)) }
        return finish(out)
    }

    /// True when the file is PHP code only: nothing but whitespace outside `<?php ... ?>` blocks (shebang allowed). Templates mixing
    /// HTML or plain text with PHP are not analysed semantically (their text would be read as code).
    static func isPureCode(_ ns: NSString) -> Bool {
        let n = ns.length
        func skipSpace(_ i: Int) -> Int { var k = i; while k < n, [32, 9, 10, 13].contains(ns.character(at: k)) { k += 1 }; return k }
        var i = skipSpace(0)
        if i < n, ns.character(at: i) == 0xFEFF { i = skipSpace(i + 1) }
        if i + 1 < n, ns.character(at: i) == 35, ns.character(at: i + 1) == 33 {          // shebang
            i = NSMaxRange(ns.lineRange(for: NSRange(location: i, length: 0)))
            i = skipSpace(i)
        }
        guard i + 1 < n, ns.character(at: i) == 60, ns.character(at: i + 1) == 63 else { return false }   // must open with "<?"
        var guardCount = 0
        while i < n, guardCount < 10_000 {
            guardCount += 1
            let close = ns.range(of: "?>", options: .literal, range: NSRange(location: i, length: n - i))
            if close.location == NSNotFound { return true }
            let next = ns.range(of: "<?", options: .literal, range: NSRange(location: NSMaxRange(close), length: n - NSMaxRange(close)))
            let gapEnd = next.location == NSNotFound ? n : next.location
            if skipSpace(NSMaxRange(close)) < gapEnd { return false }                      // text between ?> and the next <?
            if next.location == NSNotFound { return true }
            i = next.location + 2
        }
        return false
    }

    /// Sorted, de-duplicated and capped.
    static func finish(_ list: [NPDiag]) -> [NPDiag] {
        var seen = Set<String>()
        var out: [NPDiag] = []
        for d in list.sorted(by: { ($0.range.location, $0.severity) < ($1.range.location, $1.severity) }) {
            guard seen.insert("\(d.range.location):\(d.range.length):\(d.code)").inserted else { continue }
            out.append(d)
            if out.count >= maxResults { break }
        }
        return out
    }

    // MARK: Conversion

    static func diagnostics(_ list: [NPDiag], in ns: NSString) -> [FileProblems.Diagnostic] {
        let table = NPLineStarts(ns)
        return list.map { d in
            let a = table.position(of: d.range.location), b = table.position(of: NSMaxRange(d.range))
            return FileProblems.Diagnostic(severity: d.severity, message: d.message, line: a.line, column: a.col, endLine: b.line, endColumn: b.col,
                                           source: "PHP", code: d.code)
        }
    }

    // MARK: Merge with Intelephense

    /// Native findings not already covered by `other` (language-server diagnostics): same line and overlapping range,
    /// or two errors on one line (syntax errors are worded and placed differently by every parser).
    static func dedupe(_ native: [FileProblems.Diagnostic], against other: [FileProblems.Diagnostic]) -> [FileProblems.Diagnostic] {
        guard !other.isEmpty else { return native }
        return native.filter { n in
            !other.contains { o in
                guard o.line <= n.endLine, n.line <= o.endLine else { return false }
                if n.line == o.line, n.severity == 1, o.severity == 1, n.code == "syntax" { return true }
                if n.line == o.line, n.code == "unused-import" || n.code == "duplicate-import" { return o.severity >= 2 }
                let nStart = (n.line, n.column), nEnd = (n.endLine, n.endColumn), oStart = (o.line, o.column), oEnd = (o.endLine, o.endColumn)
                return nStart < oEnd && oStart < nEnd
            }
        }
    }

    /// LSPProblems hook: the language-server list of a PHP file plus the native extras (no duplicates), in position order.
    static func merged(_ lsp: [FileProblems.Diagnostic], path: String) -> [FileProblems.Diagnostic] {
        let native = NativeProblems.diagnostics(forPath: path)
        guard !native.isEmpty else { return lsp }
        return (lsp + dedupe(native, against: lsp)).sorted { ($0.line, $0.column, $0.severity) < ($1.line, $1.column, $1.severity) }
    }
}

/// Line starts of a text for offset -> (line, column), 1-based.
struct NPLineStarts {
    let starts: [Int]
    let length: Int
    init(_ ns: NSString) {
        var s = [0]
        let n = ns.length
        var i = 0
        while i < n { if ns.character(at: i) == 10 { s.append(i + 1) }; i += 1 }
        starts = s; length = n
    }
    func position(of offset: Int) -> (line: Int, col: Int) {
        let o = max(0, min(offset, length))
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= o { lo = mid } else { hi = mid - 1 }
        }
        return (lo + 1, o - starts[lo] + 1)
    }
}
