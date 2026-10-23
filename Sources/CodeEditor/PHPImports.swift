import AppKit

/// Native PHP "Import class" quick fix and "Optimize imports". Pure text logic (testable without a window): finds the
/// unresolved class name under the caret, builds the `use` edit at the sorted position, and rewrites the use block.
/// Candidates come from the existing fast-tier project class table and the vendor class index (no new index).
enum PHPImports {
    struct Edit: Equatable {
        var range: NSRange
        var text: String
    }

    enum Plan: Equatable {
        case edit(Edit)
        case alreadyImported          // the FQN is already imported (any alias)
        case sameNamespace            // the class lives in this file's namespace (or both are global)
        case conflict(String)         // the short name is already imported from another FQN
        case unsupported              // e.g. braced `namespace X { }` without a use block
    }

    // MARK: Name under the caret

    private static let declKeywords: Set<String> = ["class", "interface", "trait", "enum", "function", "const", "namespace", "use", "as", "fn"]

    /// The bare, capitalised identifier at the caret that looks like a class reference, or nil.
    static func nameAtCaret(_ ns: NSString, caret: Int) -> (name: String, range: NSRange)? {
        guard caret >= 0, caret <= ns.length else { return nil }
        var s = caret, e = caret
        func isId(_ i: Int) -> Bool { CompletionLex.isIdent(ns.character(at: i)) }
        while s > 0, isId(s - 1) { s -= 1 }
        while e < ns.length, isId(e) { e += 1 }
        guard e > s else { return nil }
        let first = ns.character(at: s)
        guard first >= 65, first <= 90 else { return nil }
        let name = ns.substring(with: NSRange(location: s, length: e - s))
        if s > 0 {
            let p = ns.character(at: s - 1)
            if p == 36 || p == 92 { return nil }                                  // $Var, \Qualified
            if p == 62, s > 1, ns.character(at: s - 2) == 45 { return nil }       // ->Name
            if p == 58, s > 1, ns.character(at: s - 2) == 58 { return nil }       // ::NAME
            if p == 62 || p == 58 || p == 63 { /* fine: `?Foo`, `: Foo`, generics */ }
        }
        if e < ns.length {
            let n = ns.character(at: e)
            if n == 92 { return nil }                                             // Foo\Bar: first segment is a namespace alias
            if n == 40 {                                                          // Foo( : only `new Foo(`
                var q = s
                while q > 0, ns.character(at: q - 1) == 32 { q -= 1 }
                guard q >= 3, ns.substring(with: NSRange(location: q - 3, length: 3)) == "new" else { return nil }
            }
        }
        // previous word: declarations introduce names rather than reference them
        var q = s
        while q > 0, ns.character(at: q - 1) == 32 || ns.character(at: q - 1) == 9 { q -= 1 }
        var w = q
        while w > 0, isId(w - 1) { w -= 1 }
        if w < q, declKeywords.contains(ns.substring(with: NSRange(location: w, length: q - w)).lowercased()) { return nil }
        return (name, NSRange(location: s, length: e - s))
    }

    // MARK: Import edit

    private static let globalBuiltins: [String] = [
        "Exception", "Error", "ErrorException", "Throwable", "TypeError", "ValueError", "ArgumentCountError", "ArithmeticError", "DivisionByZeroError",
        "InvalidArgumentException", "RuntimeException", "LogicException", "DomainException", "LengthException", "OutOfRangeException",
        "OutOfBoundsException", "OverflowException", "RangeException", "UnderflowException", "UnexpectedValueException", "BadMethodCallException",
        "BadFunctionCallException", "JsonException", "DateTime", "DateTimeImmutable", "DateTimeInterface", "DateTimeZone", "DateInterval",
        "DatePeriod", "Closure", "Countable", "ArrayAccess", "ArrayObject", "ArrayIterator", "Iterator", "IteratorAggregate", "Traversable",
        "Generator", "JsonSerializable", "Stringable", "UnitEnum", "BackedEnum", "WeakMap", "SplFileInfo", "SplObjectStorage", "SplStack",
        "SplQueue", "PDO", "PDOException", "PDOStatement", "ReflectionClass", "ReflectionMethod", "ReflectionProperty", "ReflectionObject",
        "ReflectionNamedType", "ReflectionEnum", "ReflectionFunction", "Attribute", "ReturnTypeWillChange", "SensitiveParameter", "NumberFormatter",
        "Collator", "IntlDateFormatter", "mysqli", "SimpleXMLElement", "DOMDocument", "ZipArchive", "Random\\Randomizer",
    ]

    /// Where and how to write `use <fqn>;` into `text` (the whole PHP file).
    static func plan(fqn rawFqn: String, short: String, in text: NSString) -> Plan {
        let fqn = rawFqn.hasPrefix("\\") ? String(rawFqn.dropFirst()) : rawFqn
        guard let cur = FTParser.parse(text) else { return .unsupported }
        let fqnNs = fqn.contains("\\") ? String(fqn[..<fqn.lastIndex(of: "\\")!]) : ""
        if fqnNs == cur.ns { return .sameNamespace }
        if cur.uses.values.contains(fqn) { return .alreadyImported }
        if let other = cur.uses[short], other != fqn { return .conflict(other) }
        if cur.uses.contains(where: { $0.key.caseInsensitiveCompare(short) == .orderedSame && $0.value != fqn }) { return .conflict(cur.uses[short] ?? short) }
        let eol = text.range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"
        let line = "use \(fqn);" + eol

        var stmts: [FTUseStmt] = []
        var seen = Set<Int>()
        for s in cur.useStmts where seen.insert(s.lineStart).inserted { stmts.append(s) }
        if let after = stmts.first(where: { $0.fqn.lowercased() > fqn.lowercased() }) {
            return .edit(Edit(range: NSRange(location: after.lineStart, length: 0), text: line))
        }
        if let last = stmts.last { return .edit(Edit(range: NSRange(location: last.lineEnd, length: 0), text: last.lineEnd == text.length && !endsWithNewline(text) ? eol + line.dropLast(eol.count) : line)) }

        // First use statement of the file: after `namespace X;`, else after `declare(...)`, else after the open tag.
        var anchor: Int?
        if !cur.ns.isEmpty {
            guard let n = cur.nsLineEnd else { return .unsupported }
            anchor = n
        } else {
            anchor = declareLineEnd(text) ?? cur.openTagEnd
        }
        guard let at = anchor else { return .unsupported }
        let blankAfter = at >= text.length || isBlankLine(text, at)
        return .edit(Edit(range: NSRange(location: at, length: 0), text: eol + line + (blankAfter ? "" : eol)))
    }

    private static func endsWithNewline(_ t: NSString) -> Bool { t.length > 0 && t.character(at: t.length - 1) == 10 }

    private static func isBlankLine(_ t: NSString, _ at: Int) -> Bool {
        var i = at
        while i < t.length {
            let c = t.character(at: i)
            if c == 10 { return true }
            if c != 32, c != 9, c != 13 { return false }
            i += 1
        }
        return true
    }

    /// End offset (after the newline) of a top-of-file `declare(...);` line, when one precedes any other statement.
    private static func declareLineEnd(_ t: NSString) -> Int? {
        var loc = 0, n = 0
        while loc < t.length, n < 12 {
            let r = t.lineRange(for: NSRange(location: loc, length: 0))
            let l = t.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("declare") && l.contains("(") && l.hasSuffix(";") { return r.upperBound }
            if !l.isEmpty, !l.hasPrefix("<?php"), !l.hasPrefix("//"), !l.hasPrefix("/*"), !l.hasPrefix("*"), !l.hasPrefix("#") { return nil }
            if r.upperBound <= loc { break }
            loc = r.upperBound
            n += 1
        }
        return nil
    }

    // MARK: Candidates

    struct Candidate: Equatable {
        var fqn: String
        var origin: String      // "project", "vendor" or "PHP"
    }

    /// Project classes (PSR-4 table), vendor classes (Composer metadata table) and PHP builtins whose short name is exactly `short`.
    static func candidates(for short: String, fileURL: URL) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        func add(_ fqn: String, _ origin: String) { if seen.insert(fqn).inserted { out.append(Candidate(fqn: fqn, origin: origin)) } }
        if let r = FastTier.root(for: fileURL) {
            let root = URL(fileURLWithPath: r)
            let fp = FastProject.shared(root: root)
            let project: [FTClassRef] = fp.queue.sync { fp.beginRequest(); return fp.projectClasses().filter { $0.short == short } }
            for c in project.sorted(by: { $0.fqn < $1.fqn }) { add(c.fqn, "project") }
            if VendorIndex.enabled {
                let hits = VendorIndex.shared(for: root).searchTypes(short, limit: 120).filter { $0.shortName == short && $0.member == nil }
                for e in hits.sorted(by: { $0.fqn < $1.fqn }) { add(e.fqn, "vendor") }
            }
        }
        if globalBuiltins.contains(short) { add(short, "PHP") }
        if let facade = FastProject.facadeAliases[short] { add(facade, "vendor") }
        return out
    }

    // MARK: Optimize imports

    private struct UseEntry {
        var raw: String           // original line(s), no trailing newline
        var run: Int              // blank-line separated group
        var key: String           // sort key
        var fqn: String?          // single class imports only
        var alias: String?
        var prunable: Bool
    }

    /// Sorts each blank-line separated group of top-level `use` statements, drops duplicates and (conservatively) unused
    /// single-class imports. Group, function and const imports are kept as they are. Nil when nothing would change.
    static func optimize(_ text: NSString) -> Edit? {
        let eol = text.range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"
        var entries: [UseEntry] = []
        var blockStart: Int?
        var blockEnd = 0
        var run = 0
        var sawBlankSinceEntry = false
        var loc = 0
        var lineCount = 0
        scan: while loc < text.length, lineCount < 1500 {
            let r = text.lineRange(for: NSRange(location: loc, length: 0))
            var contentRange = r
            while contentRange.length > 0, [10, 13].contains(text.character(at: NSMaxRange(contentRange) - 1)) { contentRange.length -= 1 }
            let content = text.substring(with: contentRange)
            let t = content.trimmingCharacters(in: .whitespaces)
            lineCount += 1
            if t.isEmpty {
                if blockStart != nil { sawBlankSinceEntry = true }
                loc = NSMaxRange(r); continue
            }
            if t.hasPrefix("use ") {
                var raw = content
                var end = NSMaxRange(r)
                var cur = r
                while !raw.contains(";"), NSMaxRange(cur) < text.length {     // multi-line group
                    cur = text.lineRange(for: NSRange(location: NSMaxRange(cur), length: 0))
                    var cr = cur
                    while cr.length > 0, [10, 13].contains(text.character(at: NSMaxRange(cr) - 1)) { cr.length -= 1 }
                    raw += eol + text.substring(with: cr)
                    end = NSMaxRange(cur)
                }
                if blockStart == nil { blockStart = r.location }
                if sawBlankSinceEntry { run += 1; sawBlankSinceEntry = false }
                entries.append(makeEntry(raw, run: run))
                blockEnd = end
                loc = end
                continue
            }
            if blockStart != nil { break scan }
            if t.hasPrefix("<?php") || t.hasPrefix("declare") || t.hasPrefix("namespace ") || t.hasPrefix("//") || t.hasPrefix("/*") || t.hasPrefix("*") || t.hasPrefix("#") {
                loc = NSMaxRange(r); continue
            }
            break scan
        }
        guard let start = blockStart, !entries.isEmpty else { return nil }
        let rest = text.substring(from: blockEnd)
        var kept: [UseEntry] = []
        var seen = Set<String>()
        for e in entries {
            if let fqn = e.fqn, e.prunable {
                let dupKey = fqn.lowercased() + "\u{1}" + (e.alias ?? "").lowercased()
                if !seen.insert(dupKey).inserted { continue }
                if let a = e.alias, !isReferenced(a, in: rest) { continue }
            }
            kept.append(e)
        }
        var out: [String] = []
        let runs = Set(kept.map(\.run)).sorted()
        for r in runs {
            let group = kept.filter { $0.run == r }.enumerated().sorted { a, b in
                a.element.key != b.element.key ? a.element.key < b.element.key : a.offset < b.offset
            }.map(\.element.raw)
            out.append(group.joined(separator: eol))
        }
        let newBlock = out.joined(separator: eol + eol) + eol
        let range = NSRange(location: start, length: blockEnd - start)
        if text.substring(with: range) == newBlock || (blockEnd == text.length && !endsWithNewline(text) && text.substring(with: range) + eol == newBlock) { return nil }
        return Edit(range: range, text: blockEnd == text.length && !endsWithNewline(text) ? String(newBlock.dropLast(eol.count)) : newBlock)
    }

    private static func makeEntry(_ raw: String, run: Int) -> UseEntry {
        let body = raw.trimmingCharacters(in: .whitespaces).dropFirst(4)
        let lower = body.lowercased()
        if lower.hasPrefix("function ") || lower.hasPrefix("const ") {
            return UseEntry(raw: raw, run: run, key: lower.hasPrefix("function ") ? "~f" + lower : "~g" + lower, fqn: nil, alias: nil, prunable: false)
        }
        if body.contains("{") || body.contains(",") {
            return UseEntry(raw: raw, run: run, key: lower, fqn: nil, alias: nil, prunable: false)
        }
        guard let semi = body.firstIndex(of: ";") else { return UseEntry(raw: raw, run: run, key: lower, fqn: nil, alias: nil, prunable: false) }
        let tail = body[body.index(after: semi)...].trimmingCharacters(in: .whitespaces)
        var decl = body[..<semi].trimmingCharacters(in: .whitespaces)
        var alias: String?
        if let r = decl.range(of: " as ", options: [.caseInsensitive]) {
            alias = decl[r.upperBound...].trimmingCharacters(in: .whitespaces)
            decl = decl[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        if decl.hasPrefix("\\") { decl.removeFirst() }
        let a = alias ?? String(decl.split(separator: "\\").last ?? "")
        return UseEntry(raw: raw, run: run, key: decl.lowercased() + (alias.map { " as " + $0.lowercased() } ?? ""),
                        fqn: decl, alias: a, prunable: tail.isEmpty)
    }

    private static func isReferenced(_ name: String, in rest: String) -> Bool {
        guard !name.isEmpty, let re = try? NSRegularExpression(pattern: "(?<![\\w$\\\\])" + NSRegularExpression.escapedPattern(for: name) + "(?!\\w)",
                                                                  options: [.caseInsensitive]) else { return true }
        let ns = rest as NSString
        return re.firstMatch(in: rest, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// Applies `edits` (ranges in the original text) as one undoable change and keeps the caret on its text.
    static func apply(_ edits: [Edit], in tv: NSTextView) {
        guard let storage = tv.textStorage, !edits.isEmpty else { return }
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        let caret = tv.selectedRange()
        guard tv.shouldChangeText(inRanges: sorted.map { NSValue(range: $0.range) }, replacementStrings: sorted.map(\.text)) else { return }
        tv.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        for e in sorted.reversed() { storage.replaceCharacters(in: e.range, with: NSAttributedString(string: e.text, attributes: tv.typingAttributes)) }
        storage.endEditing()
        tv.didChangeText()
        tv.undoManager?.endUndoGrouping()
        var shift = 0
        for e in sorted where e.range.location < caret.location { shift += e.text.utf16.count - e.range.length }
        tv.setSelectedRange(NSRange(location: max(0, caret.location + shift), length: caret.length))
    }
}

// MARK: - UI wiring (Alt-Return items, Code menu)

/// Quick-fix entries for PHP files, merged into the Alt-Return picker (see LanguageServers.showCodeActions).
enum PHPQuickFixes {
    static func items(for tab: EditorTab) -> [PickerItem] {
        let ext = tab.url.pathExtension.lowercased()
        guard ext == "php" || ext == "phtml" else { return [] }
        let tv = tab.textView
        let text = tv.string
        let ns = text as NSString
        guard ns.length < 2_000_000 else { return [] }
        var items: [PickerItem] = []
        let caret = min(tv.selectedRange().location, ns.length)
        if tv.selectedRange().length == 0, let hit = PHPImports.nameAtCaret(ns, caret: caret), isClassContext(text, caret: caret, tab: tab) {
            for c in PHPImports.candidates(for: hit.name, fileURL: tab.url) {
                guard case .edit(let edit) = PHPImports.plan(fqn: c.fqn, short: hit.name, in: ns) else { continue }
                items.append(PickerItem(title: "Import class \(c.fqn)", detail: c.origin, symbol: "square.and.arrow.down", key: "Import class \(c.fqn)") { [weak tv] in
                    guard let tv, tv.string == text else { return }
                    PHPImports.apply([edit], in: tv)
                })
            }
        }
        if let opt = PHPImports.optimize(ns) {
            items.append(PickerItem(title: "Optimize imports", detail: "Source", symbol: "arrow.up.arrow.down", key: "Optimize imports sort use") { [weak tv] in
                guard let tv, tv.string == text else { return }
                PHPImports.apply([opt], in: tv)
            })
        }
        return items
    }

    /// Only PHP code (and docblock type tags), not strings or HTML outside `<?php`.
    private static func isClassContext(_ text: String, caret: Int, tab: EditorTab) -> Bool {
        let ctx = CompletionContext(text: text, caret: caret, fileURL: tab.url, fileExtension: tab.url.pathExtension, triggerCharacter: nil,
                                    isManual: true, prefixRange: NSRange(location: caret, length: 0))
        let region = CompletionLex.info(ctx).region
        guard region == .php || region == .bladeExpr else { return false }
        switch CompletionLex.state(ctx) {
        case .code: return true
        case .string: return false
        case .comment:
            let ns = text as NSString
            let line = ns.substring(with: ns.lineRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0)))
            return line.contains("@")
        }
    }
}

/// Menu target for Code > Optimize Imports.
final class PHPImportActions: NSObject {
    static let shared = PHPImportActions()

    @objc func optimizeImports(_ sender: Any?) {
        guard let w = (NSApp.delegate as? AppDelegate)?.active, let tab = w.current else { return }
        let ext = tab.url.pathExtension.lowercased()
        guard ext == "php" || ext == "phtml" else { w.statusBar.flash("Optimize Imports works on PHP files"); return }
        if let edit = PHPImports.optimize(tab.textView.string as NSString) {
            PHPImports.apply([edit], in: tab.textView)
            w.statusBar.flash("Imports optimized")
        } else {
            w.statusBar.flash("Imports are already optimized")
        }
    }
}
