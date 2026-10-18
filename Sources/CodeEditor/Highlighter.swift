import AppKit
import SwiftTreeSitter

/// Layered, incremental tree-sitter highlighter.
///
/// * The root grammar's tree is kept and updated with `Tree.edit` (see `textDidEdit`).
/// * Colours are applied as temporary attributes on the layout manager (the text storage is
///   never touched), only for the visible range plus a margin, and re-applied on scroll.
/// * Injected languages (HTML in PHP, JS in HTML, fenced code in Markdown...) are parsed
///   transiently with `setIncludedRanges` against the very same text (no substring copies, so
///   UTF-16 offsets stay exact) and painted over the parent layer. No injected tree is retained.
final class Highlighter {
    private let root: Grammar
    private var tree: MutableTree?
    private weak var textView: NSTextView?
    private var lines = LineTable()
    private var trackedLength = 0
    private var sawEdits = false
    private var treeStale = true
    private var applied: NSRange?
    private var flushScheduled = false
    private var lastCost: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private weak var clipView: NSClipView?

    private var styleIDs: [String: UInt16] = [:]
    private var styleAttrs: [[NSAttributedString.Key: Any]] = [[:]]   // index 0 = unstyled

    private static let maxDepth = 2
    private static let fullRange = TSRange(points: Point(row: 0, column: 0)..<Point(row: UInt32.max, column: UInt32.max),
                                           bytes: 0..<UInt32.max)

    convenience init?(textView: NSTextView, extension ext: String) {
        guard let key = Languages.key(forExtension: ext) else { return nil }
        self.init(textView: textView, key: key)
    }

    convenience init?(textView: NSTextView, fileName: String) {
        guard let key = Languages.key(forFileName: fileName) else { return nil }
        self.init(textView: textView, key: key)
    }

    private init?(textView: NSTextView, key: String) {
        guard let grammar = Languages.grammar(forKey: key) else { return nil }
        root = grammar
        self.textView = textView
        observe()
        reparse()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        tree = nil
    }

    private func observe() {
        if let clip = textView?.enclosingScrollView?.contentView {
            clipView = clip
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                self?.scrolled()
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.styleIDs = [:]
            self?.styleAttrs = [[:]]
            self?.apply()
        })
    }

    // MARK: Public API

    private var text: NSString? { textView?.textStorage?.mutableString }

    /// Re-parses if the text changed since the last parse (always a full parse when
    /// `textDidEdit` was never called), then repaints the visible range.
    func reparse() {
        guard let ns = text else { return }
        let afterEdit = treeStale && sawEdits
        if root.parser != nil, treeStale || tree == nil || !sawEdits {
            parseRoot(ns)
        }
        treeStale = false
        apply(margin: !afterEdit)
    }

    /// Repaints the visible range (+ margin) from the current tree.
    func apply() { apply(margin: true) }

    /// After edits only the visible lines are repainted (cheapest); the margin is filled on scroll.
    private func apply(margin: Bool) {
        guard let ns = text, ns.length > 0 else { return }
        let start = CFAbsoluteTimeGetCurrent()
        let known = window(margin: margin)
        let win = known ?? NSRange(location: 0, length: min(ns.length, 30_000))
        paintWindow(win, ns)
        applied = known == nil ? nil : win
        lastCost = CFAbsoluteTimeGetCurrent() - start
    }

    /// Feed every text-storage edit here: `range` is the edited range in the NEW text
    /// (`NSTextStorage.editedRange`), `changeInLength` the length delta. Updates the syntax tree
    /// incrementally and schedules a (cheap) re-parse + repaint at the end of the run loop.
    func textDidEdit(range: NSRange, changeInLength: Int) {
        sawEdits = true
        treeStale = true
        if let ns = text, let tree, root.parser != nil {
            let oldLen = range.length - changeInLength
            let oldEnd = range.location + oldLen
            if oldLen < 0 || oldEnd > trackedLength || NSMaxRange(range) > ns.length
                || trackedLength + changeInLength != ns.length {
                self.tree = nil   // inconsistent: next reparse is a full parse
            } else {
                let startPoint = lines.point(range.location)
                let oldEndPoint = lines.point(oldEnd)
                lines.replace(location: range.location, oldLen: oldLen, newLen: range.length, in: ns)
                trackedLength = ns.length
                tree.edit(InputEdit(startByte: range.location * 2, oldEndByte: oldEnd * 2,
                                    newEndByte: NSMaxRange(range) * 2, startPoint: startPoint,
                                    oldEndPoint: oldEndPoint,
                                    newEndPoint: lines.point(NSMaxRange(range))))
            }
        }
        applied = nil
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        let delay: TimeInterval = lastCost > 0.012 ? 0.12 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.reparse()
        }
    }

    private func scrolled() {
        guard let ns = text, ns.length > 0 else { return }
        if let a = applied, let v = window(margin: false), NSLocationInRange(v.location, a),
           NSMaxRange(v) <= NSMaxRange(a) { return }
        apply()
    }

    // MARK: Parsing

    private func makeReader(_ ns: NSString) -> Parser.ReadBlock {
        return { byteOffset, _ in
            let index = byteOffset / 2
            let length = ns.length
            guard index < length else { return nil }
            var n = min(8192, length - index)
            // Never split a surrogate pair across chunks.
            if index + n < length, UTF16.isLeadSurrogate(ns.character(at: index + n - 1)) { n += 1 }
            var data = Data(count: n * 2)
            data.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress?.assumingMemoryBound(to: unichar.self) {
                    ns.getCharacters(base, range: NSRange(location: index, length: n))
                }
            }
            return data
        }
    }

    private func parseRoot(_ ns: NSString) {
        guard let parser = root.parser else { return }
        let incremental = tree != nil && sawEdits && trackedLength == ns.length
        if !incremental { tree = nil }
        parser.includedRanges = [Highlighter.fullRange]
        let old: MutableTree? = incremental ? tree : nil
        tree = parser.parse(tree: old, readBlock: makeReader(ns))
        if !incremental {
            lines = LineTable(ns)
            trackedLength = ns.length
        }
    }

    // MARK: Visible window

    private func window(margin: Bool) -> NSRange? {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
              let ns = text else { return nil }
        var rect = tv.visibleRect
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        if margin { rect = rect.insetBy(dx: 0, dy: -rect.height / 2) }
        let origin = tv.textContainerOrigin
        rect.origin.x -= origin.x
        rect.origin.y -= origin.y
        let glyphs = lm.glyphRange(forBoundingRect: rect, in: tc)
        var chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        if chars.location > ns.length { return nil }
        chars.length = min(chars.length, ns.length - chars.location)
        if chars.length > 150_000 { chars.length = 150_000 }
        return chars
    }

    // MARK: Painting

    /// One style id per UTF-16 unit of the window; deeper layers overwrite shallower ones.
    private final class Canvas {
        let win: NSRange
        var ids: [UInt16]
        init(_ win: NSRange) { self.win = win; ids = [UInt16](repeating: 0, count: win.length) }

        func paint(_ r: NSRange, _ id: UInt16) {
            let lo = max(r.location, win.location), hi = min(NSMaxRange(r), NSMaxRange(win))
            guard lo < hi else { return }
            let a = lo - win.location, b = hi - win.location
            ids.withUnsafeMutableBufferPointer { p in
                for i in a..<b { p[i] = id }
            }
        }
    }

    private func styleID(_ name: String) -> UInt16 {
        if let id = styleIDs[name] { return id }
        var id: UInt16 = 0
        if let style = Theme.style(for: name) {
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: style.color]
            if let bg = style.background { attrs[.backgroundColor] = bg }
            if style.italic { attrs[.obliqueness] = 0.2 }
            if style.bold { attrs[.strokeWidth] = -2.5 }
            styleAttrs.append(attrs)
            id = UInt16(styleAttrs.count - 1)
        }
        styleIDs[name] = id
        return id
    }

    private func paintWindow(_ win: NSRange, _ ns: NSString) {
        guard let lm = textView?.layoutManager, win.length > 0 else { return }
        let canvas = Canvas(win)
        if let lexer = root.lexer {
            runLexer(lexer, in: win, ns, extendToLine: true, canvas)
        } else if let tree = tree?.copy() {
            paint(tree: tree, grammar: root, text: ns, offset: 0, depth: 0, canvas)
        }
        for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .obliqueness, .strokeWidth] {
            lm.removeTemporaryAttribute(key, forCharacterRange: win)
        }
        var i = 0
        let n = canvas.ids.count
        while i < n {
            let id = canvas.ids[i]
            var j = i + 1
            while j < n, canvas.ids[j] == id { j += 1 }
            if id != 0 {
                lm.addTemporaryAttributes(styleAttrs[Int(id)],
                                          forCharacterRange: NSRange(location: win.location + i, length: j - i))
            }
            i = j
        }
    }

    private func context(_ text: NSString) -> SwiftTreeSitter.Predicate.Context {
        SwiftTreeSitter.Predicate.Context(textProvider: { range, _ in
            guard range.location >= 0, NSMaxRange(range) <= text.length else { return nil }
            return text.substring(with: range)
        })
    }

    private func layerWindow(_ canvas: Canvas, offset: Int, length: Int) -> NSRange {
        let lo = max(0, canvas.win.location - offset)
        let hi = min(length, NSMaxRange(canvas.win) - offset)
        return NSRange(location: lo, length: max(0, hi - lo))
    }

    /// Paints `tree` (a layer whose positions map to document positions by `+ offset`).
    private func paint(tree: Tree, grammar: Grammar, text: NSString, offset: Int, depth: Int, _ canvas: Canvas) {
        let win = layerWindow(canvas, offset: offset, length: text.length)
        guard win.length > 0 else { return }
        let ctx = context(text)
        if let query = grammar.highlights {
            let cursor = query.execute(in: tree)
            cursor.setRange(win)
            var items: [(len: Int, comps: Int, pattern: Int, range: NSRange, id: UInt16)] = []
            for match in cursor where match.allowed(in: ctx) {
                for capture in match.captures {
                    let comps = capture.nameComponents
                    guard let first = comps.first, !first.hasPrefix("_") else { continue }
                    let id = styleID(comps.joined(separator: "."))
                    let r = capture.range
                    items.append((r.length, comps.count, match.patternIndex, r, id))
                }
            }
            // Outer spans first, inner (more specific) last; ties: longer capture name, later pattern.
            items.sort {
                if $0.len != $1.len { return $0.len > $1.len }
                if $0.comps != $1.comps { return $0.comps < $1.comps }
                return $0.pattern < $1.pattern
            }
            for item in items {
                canvas.paint(NSRange(location: item.range.location + offset, length: item.range.length), item.id)
            }
        }
        guard depth < Highlighter.maxDepth else { return }
        for injection in injections(of: grammar, tree: tree, text: text, window: win, offset: offset, ctx, canvas) {
            paint(injection, text: text, offset: offset, depth: depth + 1, canvas)
        }
    }

    private struct Injection {
        var key: String
        var ranges: [TSRange]
        var wrapped = false
    }

    private func subtractChildren(_ node: Node) -> [TSRange] {
        guard node.childCount > 0 else { return [node.tsRange] }
        var out: [TSRange] = []
        var byte = node.byteRange.lowerBound
        var point = node.pointRange.lowerBound
        func gap(to endByte: UInt32, _ endPoint: Point) {
            guard endByte > byte else { return }
            out.append(TSRange(points: Range(uncheckedBounds: (point, endPoint)), bytes: byte..<endByte))
        }
        for i in 0..<node.childCount {
            guard let child = node.child(at: i) else { continue }
            gap(to: child.byteRange.lowerBound, child.pointRange.lowerBound)
            byte = max(byte, child.byteRange.upperBound)
            point = child.pointRange.upperBound
        }
        gap(to: node.byteRange.upperBound, node.pointRange.upperBound)
        return out
    }

    private func injections(of grammar: Grammar, tree: Tree, text: NSString, window win: NSRange, offset: Int,
                            _ ctx: SwiftTreeSitter.Predicate.Context, _ canvas: Canvas) -> [Injection] {
        var result: [Injection] = []
        if let query = grammar.injections {
            let cursor = query.execute(in: tree)
            cursor.setRange(win)
            var combined: [String: Int] = [:]
            for match in cursor where match.allowed(in: ctx) {
                let contents = match.captures(named: "injection.content")
                guard !contents.isEmpty else { continue }
                var name = match.metadata["injection.language"]
                if let lc = match.captures(named: "injection.language").first,
                   NSMaxRange(lc.range) <= text.length {
                    name = text.substring(with: lc.range)
                }
                guard let name, var key = Languages.key(forInjectionName: name) else { continue }
                var ranges: [TSRange] = []
                let includeChildren = match.metadata["injection.include-children"] != nil
                for c in contents { ranges += includeChildren ? [c.node.tsRange] : subtractChildren(c.node) }
                guard !ranges.isEmpty else { continue }
                // Fenced "php" blocks usually omit the open tag: use the tag-less grammar then.
                if name.lowercased() == "php", let first = ranges.first {
                    let r = first.bytes.range
                    let head = text.substring(with: NSRange(location: r.location, length: min(8, text.length - r.location)))
                    if !head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<?") { key = "php_only" }
                }
                let wrapped = key == "css_decl"
                if wrapped { key = "css" }
                if match.metadata["injection.combined"] != nil {
                    let id = "\(match.patternIndex)|\(key)"
                    if let i = combined[id] { result[i].ranges += ranges } else {
                        combined[id] = result.count
                        result.append(Injection(key: key, ranges: ranges, wrapped: wrapped))
                    }
                } else {
                    result.append(Injection(key: key, ranges: ranges, wrapped: wrapped))
                }
            }
        }
        if grammar.findsInterpolations, let q = grammar.textQuery {
            let cursor = q.execute(in: tree)
            cursor.setRange(win)
            let id = styleID("punctuation.special")
            for match in cursor {
                for capture in match.captures {
                    let r = capture.range
                    guard r.length >= 4, NSMaxRange(r) <= text.length else { continue }
                    let s = text.substring(with: r) as NSString
                    var pos = 0
                    while pos < s.length {
                        let open = s.range(of: "{{", range: NSRange(location: pos, length: s.length - pos))
                        guard open.location != NSNotFound else { break }
                        let from = NSMaxRange(open)
                        let close = s.range(of: "}}", range: NSRange(location: from, length: s.length - from))
                        guard close.location != NSNotFound else { break }
                        canvas.paint(NSRange(location: r.location + open.location + offset, length: 2), id)
                        canvas.paint(NSRange(location: r.location + close.location + offset, length: 2), id)
                        let a = (r.location + from) * 2, b = (r.location + close.location) * 2
                        if b > a {
                            let range = TSRange(points: Point(row: 0, column: a)..<Point(row: 0, column: b),
                                                bytes: UInt32(a)..<UInt32(b))
                            result.append(Injection(key: "js", ranges: [range]))
                        }
                        pos = NSMaxRange(close)
                    }
                }
            }
        }
        return result
    }

    private func paint(_ injection: Injection, text: NSString, offset: Int, depth: Int, _ canvas: Canvas) {
        guard let grammar = Languages.grammar(forKey: injection.key) else { return }
        // Keep ranges sorted and non-overlapping, as tree-sitter requires.
        var ranges: [TSRange] = []
        for r in injection.ranges.sorted(by: { $0.bytes.lowerBound < $1.bytes.lowerBound }) {
            if let last = ranges.last, r.bytes.lowerBound < last.bytes.upperBound { continue }
            ranges.append(r)
        }
        let docRanges = ranges.map { r -> NSRange in
            let n = r.bytes.range
            return NSRange(location: n.location + offset, length: n.length)
        }
        // Skip layers entirely outside the painted window (they were only matched by margin).
        guard docRanges.contains(where: { NSIntersectionRange($0, canvas.win).length > 0 }) else { return }
        if injection.key != "md_inline" { for r in docRanges { canvas.paint(r, 0) } }

        if let lexer = grammar.lexer {
            for r in docRanges { runLexer(lexer, in: NSIntersectionRange(r, canvas.win), text, extendToLine: false, canvas) }
            return
        }
        guard let parser = grammar.parser else { return }
        defer { parser.includedRanges = [Highlighter.fullRange] }
        if injection.wrapped {
            guard let r = docRanges.first, r.length > 0 else { return }
            let synthetic = ("a{" + text.substring(with: NSRange(location: r.location - offset, length: r.length)) + "}") as NSString
            parser.includedRanges = [Highlighter.fullRange]
            guard let t = parser.parse(tree: nil as MutableTree?, readBlock: makeReader(synthetic))?.copy() else { return }
            paint(tree: t, grammar: grammar, text: synthetic, offset: r.location - 2, depth: depth, canvas)
        } else {
            parser.includedRanges = ranges
            guard let t = parser.parse(tree: nil as MutableTree?, readBlock: makeReader(text))?.copy() else { return }
            paint(tree: t, grammar: grammar, text: text, offset: offset, depth: depth, canvas)
        }
    }

    // MARK: Lexer layers (SQL, dotenv)

    private func runLexer(_ kind: SimpleLexer.Kind, in range: NSRange, _ ns: NSString, extendToLine: Bool, _ canvas: Canvas) {
        guard range.length > 0 else { return }
        var r = range
        if extendToLine {
            // Lex from the start of the file when it is small (multi-line comments/strings stay correct).
            r.location = ns.length <= 300_000 ? 0 : ns.lineRange(for: NSRange(location: range.location, length: 0)).location
            r.length = NSMaxRange(range) - r.location
        }
        var buf = [unichar](repeating: 0, count: r.length)
        ns.getCharacters(&buf, range: r)
        SimpleLexer.lex(kind, buf, base: r.location) { [self] lo, hi, name in
            let id = styleID(name)
            if id != 0 { canvas.paint(NSRange(location: lo, length: hi - lo), id) }
        }
    }
}

// MARK: - Line table (exact tree-sitter points for incremental edits)

/// Start offset (UTF-16) of every line. Lets `textDidEdit` compute the row/column of the old
/// edit end, which the deleted text no longer tells us.
struct LineTable {
    private(set) var starts: [Int] = [0]

    init() {}

    init(_ ns: NSString) {
        let length = ns.length
        var buf = [unichar](repeating: 0, count: 16_384)
        var pos = 0
        while pos < length {
            let n = min(buf.count, length - pos)
            buf.withUnsafeMutableBufferPointer { ns.getCharacters($0.baseAddress!, range: NSRange(location: pos, length: n)) }
            for i in 0..<n where buf[i] == 10 { starts.append(pos + i + 1) }
            pos += n
        }
    }

    func row(of offset: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func point(_ offset: Int) -> Point {
        let r = row(of: offset)
        return Point(row: r, column: max(0, offset - starts[r]) * 2)
    }

    mutating func replace(location: Int, oldLen: Int, newLen: Int, in ns: NSString) {
        let oldEnd = location + oldLen
        let r0 = row(of: location), r1 = row(of: oldEnd)
        var inserted: [Int] = []
        if newLen > 0 {
            var buf = [unichar](repeating: 0, count: newLen)
            ns.getCharacters(&buf, range: NSRange(location: location, length: newLen))
            for i in 0..<newLen where buf[i] == 10 { inserted.append(location + i + 1) }
        }
        let delta = newLen - oldLen
        if delta != 0, r1 + 1 < starts.count {
            for i in (r1 + 1)..<starts.count { starts[i] += delta }
        }
        starts.replaceSubrange((r0 + 1)..<(r1 + 1), with: inserted)
    }
}

// MARK: - Simple lexers

enum SimpleLexer {
    enum Kind { case sql, dotenv }

    static func lex(_ kind: Kind, _ s: [unichar], base: Int, emit: (Int, Int, String) -> Void) {
        switch kind {
        case .sql: sql(s, base, emit)
        case .dotenv: dotenv(s, base, emit)
        }
    }

    private static func isIdentStart(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }
    private static func isIdent(_ c: unichar) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) || c == 36 }
    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private static let sqlKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IS", "IN", "LIKE", "ILIKE", "BETWEEN", "JOIN", "INNER",
        "LEFT", "RIGHT", "OUTER", "FULL", "CROSS", "NATURAL", "ON", "AS", "GROUP", "BY", "ORDER", "HAVING", "LIMIT",
        "OFFSET", "UNION", "ALL", "DISTINCT", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE",
        "ALTER", "DROP", "TABLE", "INDEX", "VIEW", "DATABASE", "SCHEMA", "ADD", "COLUMN", "CONSTRAINT", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "UNIQUE", "DEFAULT", "CHECK", "CASCADE", "RESTRICT", "IF", "EXISTS",
        "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
        "TRUNCATE", "RENAME", "TO", "USING", "WITH", "RECURSIVE", "RETURNING", "AUTO_INCREMENT", "ENGINE",
        "CHARSET", "CHARACTER", "COLLATE", "UNSIGNED", "GRANT", "REVOKE", "EXPLAIN", "ANALYZE", "OVER",
        "PARTITION", "TEMPORARY", "TEMP", "REPLACE", "MODIFY", "CHANGE", "AFTER", "FIRST", "ANY", "SOME",
        "ESCAPE", "FETCH", "NEXT", "ROWS", "ONLY", "FOR", "SHARE", "LOCK", "UNLOCK", "TRIGGER", "PROCEDURE",
        "FUNCTION", "RETURNS", "DECLARE", "WHILE", "DO", "LOOP", "CALL", "USE", "SHOW", "DESCRIBE", "STORED",
        "GENERATED", "ALWAYS", "VIRTUAL", "COMMENT", "NULLS", "LAST", "OWNER", "ROLE", "USER", "INTERSECT", "EXCEPT",
    ]
    private static let sqlTypes: Set<String> = [
        "INT", "INTEGER", "BIGINT", "SMALLINT", "TINYINT", "MEDIUMINT", "VARCHAR", "CHAR", "TEXT", "LONGTEXT",
        "MEDIUMTEXT", "TINYTEXT", "DATE", "DATETIME", "TIMESTAMP", "TIME", "YEAR", "DECIMAL", "NUMERIC", "FLOAT",
        "DOUBLE", "BOOLEAN", "BOOL", "JSON", "JSONB", "UUID", "BLOB", "LONGBLOB", "BINARY", "VARBINARY", "SERIAL",
        "BIGSERIAL", "ENUM", "REAL", "BIT", "INTERVAL", "TIMESTAMPTZ", "BYTEA", "UNSIGNED",
    ]

    private static func sql(_ s: [unichar], _ base: Int, _ emit: (Int, Int, String) -> Void) {
        let n = s.count
        var i = 0
        while i < n {
            let c = s[i]
            if c == 45, i + 1 < n, s[i + 1] == 45 {                       // -- comment
                var j = i; while j < n, s[j] != 10 { j += 1 }
                emit(base + i, base + j, "comment"); i = j
            } else if c == 47, i + 1 < n, s[i + 1] == 42 {                // /* */
                var j = i + 2
                while j + 1 < n, !(s[j] == 42 && s[j + 1] == 47) { j += 1 }
                j = min(n, j + 2)
                emit(base + i, base + j, "comment"); i = j
            } else if c == 39 || c == 34 {                                // '..' or ".."
                var j = i + 1
                while j < n {
                    if s[j] == 92, j + 1 < n { j += 2; continue }
                    if s[j] == c { if j + 1 < n, s[j + 1] == c { j += 2; continue }; j += 1; break }
                    j += 1
                }
                emit(base + i, base + min(j, n), "string"); i = j
            } else if c == 96 {                                           // `ident`
                var j = i + 1; while j < n, s[j] != 96 { j += 1 }
                j = min(n, j + 1)
                emit(base + i, base + j, "property"); i = j
            } else if isDigit(c) {
                var j = i + 1; while j < n, isDigit(s[j]) || s[j] == 46 { j += 1 }
                emit(base + i, base + j, "number"); i = j
            } else if c == 64 || c == 58, i + 1 < n, isIdentStart(s[i + 1]) {   // @var, :param
                var j = i + 1; while j < n, isIdent(s[j]) { j += 1 }
                emit(base + i, base + j, "variable.builtin"); i = j
            } else if isIdentStart(c) {
                var j = i + 1; while j < n, isIdent(s[j]) { j += 1 }
                let word = String(utf16CodeUnits: Array(s[i..<j]), count: j - i).uppercased()
                var k = j; while k < n, s[k] == 32 { k += 1 }
                if word == "TRUE" || word == "FALSE" || word == "NULL" {
                    emit(base + i, base + j, "constant.builtin")
                } else if sqlTypes.contains(word) {
                    emit(base + i, base + j, "type.builtin")
                } else if sqlKeywords.contains(word) {
                    emit(base + i, base + j, "keyword")
                } else if k < n, s[k] == 40 {
                    emit(base + i, base + j, "function")
                }
                i = j
            } else if "=<>!+-*/%|&^~".utf16.contains(c) {
                emit(base + i, base + i + 1, "operator"); i += 1
            } else if c == 40 || c == 41 || c == 44 || c == 59 {
                emit(base + i, base + i + 1, "punctuation.delimiter"); i += 1
            } else { i += 1 }
        }
    }

    private static func dotenv(_ s: [unichar], _ base: Int, _ emit: (Int, Int, String) -> Void) {
        let n = s.count
        var i = 0
        while i < n {
            var eol = i; while eol < n, s[eol] != 10 { eol += 1 }
            var p = i
            while p < eol, s[p] == 32 || s[p] == 9 { p += 1 }
            if p < eol, s[p] == 35 {
                emit(base + p, base + eol, "comment")
            } else if p < eol {
                // optional `export `
                if eol - p > 7, String(utf16CodeUnits: Array(s[p..<p + 7]), count: 7) == "export " {
                    emit(base + p, base + p + 6, "keyword"); p += 7
                    while p < eol, s[p] == 32 { p += 1 }
                }
                var k = p; while k < eol, s[k] != 61 { k += 1 }
                if k < eol {
                    var ke = k; while ke > p, s[ke - 1] == 32 { ke -= 1 }
                    emit(base + p, base + ke, "property")
                    emit(base + k, base + k + 1, "operator")
                    var v = k + 1; while v < eol, s[v] == 32 || s[v] == 9 { v += 1 }
                    var end = eol
                    if v < eol, s[v] == 34 || s[v] == 39 {
                        let q = s[v]; var e = v + 1
                        while e < eol, s[e] != q { if s[e] == 92, q == 34 { e += 1 }; e += 1 }
                        end = min(eol, e + 1)
                        emit(base + v, base + end, "string")
                        var t = end; while t < eol, s[t] == 32 || s[t] == 9 { t += 1 }
                        if t < eol, s[t] == 35 { emit(base + t, base + eol, "comment") }
                    } else {
                        var e = v
                        while e < eol { if s[e] == 35, e > v, s[e - 1] == 32 || s[e - 1] == 9 { break }; e += 1 }
                        var ee = e; while ee > v, s[ee - 1] == 32 || s[ee - 1] == 9 { ee -= 1 }
                        if ee > v { emit(base + v, base + ee, "string") }
                        if e < eol { emit(base + e, base + eol, "comment") }
                    }
                    // ${VAR} references inside the value
                    var q = v
                    while q + 1 < end {
                        if s[q] == 36, s[q + 1] == 123 {
                            var e = q + 2; while e < end, s[e] != 125 { e += 1 }
                            emit(base + q, base + min(end, e + 1), "variable.builtin"); q = e
                        }
                        q += 1
                    }
                }
            }
            i = eol + 1
        }
    }
}
