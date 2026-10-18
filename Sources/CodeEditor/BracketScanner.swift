import Foundation
import SwiftTreeSitter

/// Compact bracket table for one document: parallel arrays, no per-bracket objects.
/// `pos` are UTF-16 offsets (NSString coordinates), strictly increasing.
struct BracketModel {
    static let kindMask: UInt8 = 3, closerBit: UInt8 = 4, unmatchedBit: UInt8 = 8

    var pos: [UInt32] = []
    var info: [UInt8] = []
    /// Nesting depth (0 based) within the bracket's counter (see `BracketScanner.independentPerType`).
    var depth: [UInt16] = []

    var count: Int { pos.count }
    func kind(_ i: Int) -> Int { Int(info[i] & Self.kindMask) }
    func isCloser(_ i: Int) -> Bool { info[i] & Self.closerBit != 0 }
    func isUnmatched(_ i: Int) -> Bool { info[i] & Self.unmatchedBit != 0 }
    func character(_ i: Int) -> Character { Array("()[]{}")[kind(i) * 2 + (isCloser(i) ? 1 : 0)] }

    /// First index whose offset is >= p.
    func lowerBound(_ p: Int) -> Int {
        var lo = 0, hi = pos.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if Int(pos[mid]) < p { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    func index(at p: Int) -> Int? {
        let i = lowerBound(p)
        return i < pos.count && Int(pos[i]) == p ? i : nil
    }

    /// Matching bracket (same counter, balanced), or nil when unmatched.
    func partner(of i: Int) -> Int? {
        let c = BracketScanner.counter(kind(i))
        var d = 1
        if !isCloser(i) {
            var j = i + 1
            while j < pos.count {
                if BracketScanner.counter(kind(j)) == c { d += isCloser(j) ? -1 : 1; if d == 0 { return j } }
                j += 1
            }
        } else {
            var j = i - 1
            while j >= 0 {
                if BracketScanner.counter(kind(j)) == c { d += isCloser(j) ? 1 : -1; if d == 0 { return j } }
                j -= 1
            }
        }
        return nil
    }

    /// Innermost opener enclosing offset `caret` (an opener before it whose pair is not closed before it).
    func enclosingOpener(before caret: Int) -> Int? {
        var need = [0, 0, 0]
        var i = lowerBound(caret) - 1
        while i >= 0 {
            let c = BracketScanner.counter(kind(i))
            if isCloser(i) { need[c] += 1 } else if need[c] > 0 { need[c] -= 1 } else { return i }
            i -= 1
        }
        return nil
    }

    /// The pair to highlight for a caret offset: bracket right after the caret, else right before it.
    /// Returns (opener index, closer index) and which of them is the one touching the caret.
    func pair(atCaret caret: Int) -> (open: Int, close: Int, touching: Int)? {
        let after = index(at: caret), before = caret > 0 ? index(at: caret - 1) : nil
        let order: [Int?] = [after.flatMap { isCloser($0) ? nil : $0 }, before.flatMap { isCloser($0) ? $0 : nil },
                             after, before]
        for case let i? in order {
            if let p = partner(of: i) { return isCloser(i) ? (p, i, i) : (i, p, i) }
        }
        return nil
    }

    /// Keeps offsets in sync with a text edit until the next rescan arrives.
    mutating func applyEdit(location: Int, oldLength: Int, newLength: Int) {
        guard !pos.isEmpty else { return }
        let lo = lowerBound(location), hi = lowerBound(location + oldLength)
        if hi > lo { pos.removeSubrange(lo..<hi); info.removeSubrange(lo..<hi); depth.removeSubrange(lo..<hi) }
        let delta = newLength - oldLength
        if delta != 0 {
            var k = lo
            let n = pos.count
            pos.withUnsafeMutableBufferPointer { p in
                while k < n { p[k] = UInt32(truncatingIfNeeded: Int(p[k]) + delta); k += 1 }
            }
        }
    }
}

/// Regions of the file whose characters are not code (or need a different lexer).
struct BracketSpan {
    enum Kind: UInt8 { case skip, js, css, blade }
    var start: Int32, end: Int32, kind: Kind
}

struct LexSpec {
    var lineSlash = false, blockSlash = false, hash = false, dashDash = false
    var template = false, regex = false, heredoc = false
    var singleQuote = true, doubleQuote = true
    var phpAttributes = false

    static let js = LexSpec(lineSlash: true, blockSlash: true, template: true, regex: true)
    static let css = LexSpec(blockSlash: true)
    static let scss = LexSpec(lineSlash: true, blockSlash: true)
    static let json = LexSpec(lineSlash: true, blockSlash: true, singleQuote: false)
    static let php = LexSpec(lineSlash: true, blockSlash: true, hash: true, heredoc: true, phpAttributes: true)
    static let sql = LexSpec(blockSlash: true, dashDash: true)
    static let bladeCode = LexSpec(blockSlash: true)
    /// Unknown languages: strings with escapes, // and /* */ and # comments.
    static let generic = LexSpec(lineSlash: true, blockSlash: true, hash: true)

    static func forExtension(_ ext: String) -> LexSpec {
        switch ext.lowercased() {
        case "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts", "vue", "svelte": return .js
        case "css": return .css
        case "scss", "less": return .scss
        case "json", "jsonc": return .json
        case "php", "phtml": return .php
        case "sql": return .sql
        default: return .generic
        }
    }
}

enum BracketScanner {
    /// VS Code's independentColorPoolPerBracketType: each pair type has its own depth counter.
    static let independentPerType = true
    @inline(__always) static func counter(_ kind: Int) -> Int { independentPerType ? kind : 0 }

    // MARK: Pure entry point (synchronous; parses with tree-sitter when a grammar exists)

    /// Scans a whole document. `range` filters the returned model to offsets inside it, keeping the
    /// depth/unmatched information computed from the whole text.
    static func scan(text: String, extension ext: String, range: NSRange? = nil) -> BracketModel {
        let units = Array(text.utf16)
        var spans: [BracketSpan]?
        if let ts = TreeScanner(extension: ext) { spans = ts.update(text: units, edit: nil) }
        var model = build(units, spans: spans, spec: .forExtension(ext))
        if let r = range {
            let lo = model.lowerBound(r.location), hi = model.lowerBound(NSMaxRange(r))
            model = BracketModel(pos: Array(model.pos[lo..<hi]), info: Array(model.info[lo..<hi]),
                                 depth: Array(model.depth[lo..<hi]))
        }
        return model
    }

    // MARK: Builder

    struct Builder {
        var model = BracketModel()
        var stacks: [[Int32]] = [[], [], []]

        mutating func add(_ p: Int, _ c: UInt16) {
            let kind: Int, closer: Bool
            switch c {
            case 40: (kind, closer) = (0, false)
            case 41: (kind, closer) = (0, true)
            case 91: (kind, closer) = (1, false)
            case 93: (kind, closer) = (1, true)
            case 123: (kind, closer) = (2, false)
            default: (kind, closer) = (2, true)
            }
            let k = BracketScanner.counter(kind)
            var flags = UInt8(kind) | (closer ? BracketModel.closerBit : 0)
            var d = 0
            if !closer {
                d = stacks[k].count
                stacks[k].append(Int32(model.pos.count))
            } else if stacks[k].isEmpty {
                flags |= BracketModel.unmatchedBit
            } else {
                stacks[k].removeLast()
                d = stacks[k].count
            }
            model.pos.append(UInt32(p)); model.info.append(flags); model.depth.append(UInt16(min(d, 65535)))
        }

        mutating func finish() -> BracketModel {
            for s in stacks { for i in s { model.info[Int(i)] |= BracketModel.unmatchedBit } }
            return model
        }
    }

    /// Scans `text`, skipping `spans` (sorted, disjoint). With `spans == nil` the tolerant lexer handles everything.
    static func build(_ text: [UInt16], spans: [BracketSpan]?, spec: LexSpec) -> BracketModel {
        var b = Builder()
        text.withUnsafeBufferPointer { t in
            guard let spans else { lex(t, 0, t.count, spec, &b); return }
            var i = 0, s = 0
            let n = t.count
            while i < n {
                let stop = s < spans.count ? Int(spans[s].start) : n
                while i < stop {
                    let c = t[i]
                    if c == 40 || c == 41 || c == 91 || c == 93 || c == 123 || c == 125 { b.add(i, c) }
                    i += 1
                }
                if s < spans.count {
                    let sp = spans[s]
                    let e = min(Int(sp.end), n)
                    switch sp.kind {
                    case .skip: break
                    case .js: lex(t, i, e, .js, &b)
                    case .css: lex(t, i, e, .css, &b)
                    case .blade: lexBlade(t, i, e, &b)
                    }
                    i = max(i, e)
                    s += 1
                }
            }
        }
        return b.finish()
    }

    // MARK: Tolerant lexer

    @inline(__always) private static func isWordChar(_ c: UInt16) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127
    }

    private static func regexAllowed(after c: UInt16) -> Bool {
        switch c {
        case 0, 40, 44, 61, 58, 91, 33, 38, 124, 63, 123, 125, 59, 43, 45, 42, 37, 126, 94: return true
        default: return false
        }
    }

    static func lex(_ t: UnsafeBufferPointer<UInt16>, _ from: Int, _ to: Int, _ spec: LexSpec, _ b: inout Builder) {
        var i = from
        var lastSig: UInt16 = 0
        var tmpl: [Int] = []   // brace depth inside each open `${ ... }`
        func at(_ k: Int) -> UInt16 { k < to ? t[k] : 0 }

        /// Skips template text from `j` (just after the backtick or `}`); returns index to resume code at.
        func templateText(_ start: Int) -> Int {
            var j = start
            while j < to {
                let ch = t[j]
                if ch == 92 { j += 2; continue }
                if ch == 96 { return j + 1 }
                if ch == 36 && at(j + 1) == 123 { tmpl.append(0); return j + 2 }
                j += 1
            }
            return to
        }

        while i < to {
            let c = t[i]
            switch c {
            case 40, 41, 91, 93, 123, 125:
                if !tmpl.isEmpty {
                    if c == 125 {
                        if tmpl[tmpl.count - 1] == 0 {
                            tmpl.removeLast()
                            i = templateText(i + 1); lastSig = 96
                            continue
                        }
                        tmpl[tmpl.count - 1] -= 1
                    } else if c == 123 { tmpl[tmpl.count - 1] += 1 }
                }
                b.add(i, c); lastSig = c; i += 1
            case 34, 39:
                if (c == 34 && !spec.doubleQuote) || (c == 39 && !spec.singleQuote) { lastSig = c; i += 1; continue }
                var j = i + 1
                while j < to {
                    let ch = t[j]
                    if ch == 92 { j += 2; continue }
                    if ch == c { j += 1; break }
                    if ch == 10 { break }
                    j += 1
                }
                i = j; lastSig = c
            case 96:
                if spec.template { i = templateText(i + 1); lastSig = 96 } else { i += 1 }
            case 47:
                let n = at(i + 1)
                if n == 47 && spec.lineSlash {
                    while i < to && t[i] != 10 { i += 1 }
                } else if n == 42 && spec.blockSlash {
                    var j = i + 2
                    while j < to && !(t[j] == 42 && at(j + 1) == 47) { j += 1 }
                    i = min(to, j + 2)
                } else if spec.regex && regexAllowed(after: lastSig) {
                    var j = i + 1, inClass = false, ok = false
                    while j < to {
                        let ch = t[j]
                        if ch == 10 { break }
                        if ch == 92 { j += 2; continue }
                        if ch == 91 { inClass = true } else if ch == 93 { inClass = false }
                        else if ch == 47 && !inClass { ok = true; break }
                        j += 1
                    }
                    if ok { i = j + 1; lastSig = 47 } else { lastSig = 47; i += 1 }
                } else { lastSig = 47; i += 1 }
            case 35:
                if spec.hash && !(spec.phpAttributes && at(i + 1) == 91) {
                    while i < to && t[i] != 10 { i += 1 }
                } else { lastSig = c; i += 1 }
            case 45:
                if spec.dashDash && at(i + 1) == 45 {
                    while i < to && t[i] != 10 { i += 1 }
                } else { lastSig = c; i += 1 }
            case 60:
                if spec.heredoc && at(i + 1) == 60 && at(i + 2) == 60, let end = heredocEnd(t, i + 3, to) {
                    i = end; lastSig = 34
                } else { lastSig = c; i += 1 }
            case 32, 9, 10, 13: i += 1
            default: lastSig = c; i += 1
            }
        }
    }

    /// `<<<ID` / `<<<"ID"` / `<<<'ID'` ... closing `ID` on its own (optionally indented) line. Returns offset after it.
    private static func heredocEnd(_ t: UnsafeBufferPointer<UInt16>, _ start: Int, _ to: Int) -> Int? {
        var j = start
        while j < to && (t[j] == 32 || t[j] == 9) { j += 1 }
        var quote: UInt16 = 0
        if j < to && (t[j] == 34 || t[j] == 39) { quote = t[j]; j += 1 }
        let idStart = j
        while j < to && isWordChar(t[j]) { j += 1 }
        let id = idStart..<j
        guard !id.isEmpty else { return nil }
        if quote != 0 { guard j < to && t[j] == quote else { return nil }; j += 1 }
        while j < to && t[j] != 10 { j += 1 }
        // Look for a line that is whitespace + ID followed by a non-word char.
        while j < to {
            j += 1   // past newline
            var k = j
            while k < to && (t[k] == 32 || t[k] == 9) { k += 1 }
            var m = 0
            while m < id.count && k + m < to && t[k + m] == t[id.lowerBound + m] { m += 1 }
            if m == id.count && (k + m >= to || !isWordChar(t[k + m])) { return k + m }
            while j < to && t[j] != 10 { j += 1 }
        }
        return to
    }

    /// Text regions of Blade / Vue templates: only `{{ }}`, `{!! !!}` and `@directive( )` contain code.
    static func lexBlade(_ t: UnsafeBufferPointer<UInt16>, _ from: Int, _ to: Int, _ b: inout Builder) {
        func at(_ k: Int) -> UInt16 { k < to ? t[k] : 0 }
        func find(_ a: UInt16, _ c: UInt16, _ c3: UInt16?, from j: Int) -> Int? {
            var k = j
            while k + 1 < to {
                if t[k] == a && t[k + 1] == c && (c3 == nil || at(k + 2) == c3!) { return k }
                k += 1
            }
            return nil
        }
        var i = from
        while i < to {
            let c = t[i]
            if c == 123 && at(i + 1) == 123 {
                if at(i + 2) == 45 && at(i + 3) == 45 {
                    i = (find(45, 45, 125, from: i + 4)).map { $0 + 4 } ?? to
                    continue
                }
                let end = find(125, 125, nil, from: i + 2) ?? to
                lex(t, i + 2, end, .bladeCode, &b)
                i = min(to, end + 2)
            } else if c == 123 && at(i + 1) == 33 && at(i + 2) == 33 {
                let end = find(33, 33, 125, from: i + 3) ?? to
                lex(t, i + 3, end, .bladeCode, &b)
                i = min(to, end + 3)
            } else if c == 64 && (i == from || !isWordChar(t[i - 1])) && at(i + 1) != 64 {
                var j = i + 1
                while j < to && ((t[j] >= 65 && t[j] <= 90) || (t[j] >= 97 && t[j] <= 122)) { j += 1 }
                var k = j
                while k < to && (t[k] == 32 || t[k] == 9) { k += 1 }
                if j > i + 1 && k < to && t[k] == 40, let end = parenEnd(t, k, to) {
                    lex(t, k, end + 1, .bladeCode, &b)
                    i = end + 1
                } else { i = max(i + 1, j) }
            } else { i += 1 }
        }
    }

    private static func parenEnd(_ t: UnsafeBufferPointer<UInt16>, _ open: Int, _ to: Int) -> Int? {
        var d = 0, j = open
        while j < to {
            let c = t[j]
            if c == 34 || c == 39 {
                j += 1
                while j < to && t[j] != c && t[j] != 10 { if t[j] == 92 { j += 1 }; j += 1 }
            } else if c == 40 { d += 1 } else if c == 41 { d -= 1; if d == 0 { return j } }
            j += 1
        }
        return nil
    }
}

// MARK: - Tree-sitter span extraction

/// Owns a parser + tree (single-thread use: the tab's background queue).
final class TreeScanner {
    private let parser = Parser()
    private var tree: MutableTree?
    private var prev: [UInt16] = []
    private var classCache: [Int: UInt8] = [:]
    private static let opaqueTypes: Set<String> = [
        "comment", "string", "encapsed_string", "heredoc", "nowdoc", "shell_command_expression", "string_value",
        "string_fragment", "string_content", "string_literal", "regex", "regex_pattern", "jsx_text", "attribute_value",
        "quoted_attribute_value", "escape_sequence", "heredoc_body", "nowdoc_body", "${", "template_chars",
    ]
    // Classes: 0 normal, 1 opaque, 2 blade text, 3 raw_text, 4 "}" (opaque only inside template_substitution)

    init?(extension ext: String) {
        guard let config = Languages.configuration(forExtension: ext) else { return nil }
        do { try parser.setLanguage(config.language) } catch { return nil }
    }

    private func cls(_ n: Node) -> UInt8 {
        let sym = n.symbol
        if let c = classCache[sym] { return c }
        let type = n.nodeType ?? ""
        let c: UInt8
        if Self.opaqueTypes.contains(type) { c = 1 }
        else if type == "text" { c = 2 }
        else if type == "raw_text" { c = 3 }
        else if type == "}" { c = 4 }
        else { c = 0 }
        classCache[sym] = c
        return c
    }

    /// Reparses (incrementally when `edit` is given relative to the previous text) and returns the spans.
    func update(text: [UInt16], edit: EditAcc?) -> [BracketSpan]? {
        var base: MutableTree?
        if let t = tree, let e = edit, !prev.isEmpty {
            t.edit(Self.inputEdit(old: prev, new: text, acc: e))
            base = t
        } else if let t = tree, edit == nil, prev == text {
            base = t
        }
        let reuse = base != nil && edit == nil
        let newTree: MutableTree? = reuse ? base : text.withUnsafeBufferPointer { buf in
            parser.parse(tree: base, readBlock: { byteOffset, _ in
                let idx = byteOffset / 2
                guard idx < buf.count, let p = buf.baseAddress else { return nil }
                let len = min(4096, buf.count - idx)
                return Data(bytes: p + idx, count: len * 2)
            })
        }
        tree = newTree
        prev = text
        guard let root = newTree?.rootNode else { return nil }
        return walk(root)
    }

    private static func point(in t: [UInt16], offset: Int, from: (row: Int, lineStart: Int, at: Int)) -> (Point, (row: Int, lineStart: Int, at: Int)) {
        var row = from.row, ls = from.lineStart
        var i = from.at
        t.withUnsafeBufferPointer { b in
            let end = min(offset, b.count)
            while i < end { if b[i] == 10 { row += 1; ls = i + 1 }; i += 1 }
        }
        return (Point(row: row, column: (offset - ls) * 2), (row, ls, offset))
    }

    private static func inputEdit(old: [UInt16], new: [UInt16], acc e: EditAcc) -> InputEdit {
        let (sp, _) = point(in: new, offset: e.start, from: (0, 0, 0))
        let start = (row: Int(sp.row), lineStart: e.start - Int(sp.column) / 2, at: e.start)
        let (op, _) = point(in: old, offset: e.oldEnd, from: start)
        let (np, _) = point(in: new, offset: e.newEnd, from: start)
        return InputEdit(startByte: e.start * 2, oldEndByte: e.oldEnd * 2, newEndByte: e.newEnd * 2,
                         startPoint: sp, oldEndPoint: op, newEndPoint: np)
    }

    private func walk(_ root: Node) -> [BracketSpan] {
        var spans: [BracketSpan] = []
        var lastEnd: Int32 = 0
        func add(_ n: Node, _ kind: BracketSpan.Kind) {
            let r = n.byteRange
            let s = Int32(r.lowerBound / 2), e = Int32(r.upperBound / 2)
            if s >= lastEnd && e > s { spans.append(BracketSpan(start: s, end: e, kind: kind)); lastEnd = e }
        }
        let cursor = root.treeCursor
        outer: while true {
            guard let n = cursor.currentNode else { break }
            var descend = true
            switch cls(n) {
            case 1: add(n, .skip); descend = false
            case 2: add(n, .blade); descend = false
            case 3:
                let parent = n.parent?.nodeType
                add(n, parent == "style_element" ? .css : .js); descend = false
            case 4:
                if n.parent?.nodeType == "template_substitution" { add(n, .skip) }
                descend = false
            default: break
            }
            if descend && cursor.goToFirstChild() { continue }
            while !cursor.gotoNextSibling() { if !cursor.gotoParent() { break outer } }
        }
        return spans
    }
}

/// Accumulated text change: [start, oldEnd) in the base text became [start, newEnd) in the current text.
struct EditAcc {
    var start: Int, oldEnd: Int, newEnd: Int

    init(location: Int, oldLength: Int, newLength: Int) {
        start = location; oldEnd = location + oldLength; newEnd = location + newLength
    }

    mutating func merge(location: Int, oldLength: Int, newLength: Int) {
        let eOld = location + oldLength, delta = newLength - oldLength
        if eOld < newEnd { newEnd += delta } else { oldEnd += eOld - newEnd; newEnd = location + newLength }
        start = min(start, location)
    }

    mutating func merge(_ later: EditAcc) {
        merge(location: later.start, oldLength: later.oldEnd - later.start, newLength: later.newEnd - later.start)
    }
}
