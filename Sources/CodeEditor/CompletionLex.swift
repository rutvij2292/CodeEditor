import Foundation

/// Cheap, allocation-light text analysis shared by the built-in completion providers (language regions,
/// comment/string detection, token scanning). Everything works on UTF-16 offsets of the caller's snapshot.
enum CompletionLex {
    enum Region { case php, js, css, html, bladeExpr }
    enum State { case code, comment, string }
    struct Info { var region: Region; var start: Int }

    static func isIdent(_ c: unichar) -> Bool {
        (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c > 127
    }

    static func isBlade(_ ctx: CompletionContext) -> Bool { ctx.fileURL.lastPathComponent.hasSuffix(".blade.php") }

    // MARK: Cache (reset by the controller at the start of each request)

    private static var cacheKey: (Int, Int, String)?
    private static var cacheInfo: Info?
    private static var cacheState: State?
    static func resetCache() { cacheKey = nil; cacheInfo = nil; cacheState = nil }

    private static func validateCache(_ ctx: CompletionContext) {
        let key = ((ctx.text as NSString).length, ctx.caret, ctx.fileExtension)
        if let k = cacheKey, k == key { return }
        cacheKey = key; cacheInfo = nil; cacheState = nil
    }

    // MARK: Regions

    static func info(_ ctx: CompletionContext) -> Info {
        validateCache(ctx)
        if let i = cacheInfo { return i }
        let i = computeInfo(ctx)
        cacheInfo = i
        return i
    }

    private static func lastRange(_ ns: NSString, _ s: String, _ head: NSRange) -> Int {
        let r = ns.range(of: s, options: [.backwards, .literal], range: head)
        return r.location == NSNotFound ? -1 : r.location
    }

    private static func computeInfo(_ ctx: CompletionContext) -> Info {
        let ns = ctx.text as NSString
        let caret = min(ctx.caret, ns.length)
        let head = NSRange(location: 0, length: caret)
        switch ctx.fileExtension.lowercased() {
        case "js", "jsx", "ts", "tsx", "mjs", "cjs": return Info(region: .js, start: 0)
        case "css", "scss", "less", "sass": return Info(region: .css, start: 0)
        case "php", "phtml":
            if isBlade(ctx) {
                let o = max(lastRange(ns, "{{", head), lastRange(ns, "{!!", head))
                let c = max(lastRange(ns, "}}", head), lastRange(ns, "!!}", head))
                if o > c, o >= 0 { return Info(region: .bladeExpr, start: o + 2) }
                let p = lastRange(ns, "@php", head), e = lastRange(ns, "@endphp", head)
                if p > e, p >= 0, p + 4 < ns.length, ns.character(at: p + 4) != 40 { return Info(region: .php, start: p + 4) }
            } else {
                let open = max(lastRange(ns, "<?php", head), lastRange(ns, "<?=", head))
                let close = lastRange(ns, "?>", head)
                if open >= 0, open > close {
                    let len = ns.substring(from: open).hasPrefix("<?php") ? 5 : 3
                    return Info(region: .php, start: open + len)
                }
            }
        default: break
        }
        for (tag, region) in [("script", Region.js), ("style", Region.css)] {
            let o = lastRange(ns, "<" + tag, head), c = lastRange(ns, "</" + tag, head)
            if o >= 0, o > c {
                let gt = ns.range(of: ">", options: .literal, range: NSRange(location: o, length: caret - o))
                if gt.location != NSNotFound { return Info(region: region, start: gt.upperBound) }
            }
        }
        return Info(region: .html, start: 0)
    }

    // MARK: Comment / string state

    static func state(_ ctx: CompletionContext) -> State {
        validateCache(ctx)
        if let s = cacheState { return s }
        let s = computeState(ctx)
        cacheState = s
        return s
    }

    private static func computeState(_ ctx: CompletionContext) -> State {
        let ns = ctx.text as NSString
        let caret = min(ctx.caret, ns.length)
        let inf = info(ctx)
        if inf.region == .html {
            let o = lastRange(ns, "<!--", NSRange(location: 0, length: caret))
            let c = lastRange(ns, "-->", NSRange(location: 0, length: caret))
            return o >= 0 && o > c ? .comment : .code
        }
        let from = inf.start
        guard caret > from, caret - from < 600_000 else { return .code }
        var buf = [unichar](repeating: 0, count: caret - from)
        ns.getCharacters(&buf, range: NSRange(location: from, length: caret - from))
        let hash = inf.region == .php
        var st = State.code
        var quote: unichar = 0
        var i = 0
        var block = false
        let n = buf.count
        while i < n {
            let c = buf[i]
            if block {
                if c == 42, i + 1 < n, buf[i + 1] == 47 { block = false; st = .code; i += 1 }
            } else if st == .comment {
                if c == 10 { st = .code }
            } else if st == .string {
                if c == 92 { i += 1 } else if c == quote { st = .code }
            } else {
                if c == 47, i + 1 < n, buf[i + 1] == 42 { block = true; st = .comment; i += 1 }
                else if c == 47, i + 1 < n, buf[i + 1] == 47, !(i > 0 && buf[i - 1] == 58) { st = .comment; i += 1 }
                else if c == 35, hash, !(i + 1 < n && buf[i + 1] == 91) { st = .comment }
                else if c == 34 || c == 39 || (c == 96 && inf.region == .js) { st = .string; quote = c }
            }
            i += 1
        }
        return st
    }

    // MARK: Token helpers

    static func lineStart(_ ns: NSString, _ loc: Int) -> Int {
        ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0)).location
    }

    /// Start of the run of characters satisfying `pred` that ends at `pos`.
    static func runStart(_ ns: NSString, _ pos: Int, floor: Int = 0, _ pred: (unichar) -> Bool) -> Int {
        var a = pos
        while a > floor, pred(ns.character(at: a - 1)) { a -= 1 }
        return a
    }

    static func before(_ ns: NSString, _ pos: Int, _ s: String) -> Bool {
        let n = s.utf16.count
        return pos >= n && ns.substring(with: NSRange(location: pos - n, length: n)) == s
    }

    static func line(before caret: Int, _ ns: NSString, maxLen: Int = 600) -> String {
        let ls = max(lineStart(ns, caret), caret - maxLen)
        return ns.substring(with: NSRange(location: ls, length: caret - ls))
    }

    /// The identifier ending exactly at `pos` (empty if none).
    static func identBefore(_ ns: NSString, _ pos: Int) -> String {
        let a = runStart(ns, pos, isIdent)
        return ns.substring(with: NSRange(location: a, length: pos - a))
    }

    /// Cheap case-insensitive ASCII subsequence test.
    static func subsequence(_ q: [UInt8], in s: String) -> Bool {
        if q.isEmpty { return true }
        var i = 0
        for b in s.utf8 {
            var c = b
            if c >= 65 && c <= 90 { c += 32 }
            if c == q[i] { i += 1; if i == q.count { return true } }
        }
        return false
    }
}
