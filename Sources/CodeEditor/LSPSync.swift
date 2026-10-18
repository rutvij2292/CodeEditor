import Foundation

/// Mirror of the text last reported to the servers, with an incrementally maintained line table, so a storage
/// edit can be turned into an LSP incremental `contentChanges` entry (range in the OLD document + new text).
/// Memory is O(file): one copy of the text plus one Int per line.
struct LSPShadow {
    private(set) var text: NSMutableString
    private(set) var starts: [Int]

    init(_ source: NSString) {
        text = NSMutableString(string: source)
        starts = LSPLineTable(source).starts
    }

    var length: Int { text.length }

    func position(of offset: Int) -> (line: Int, character: Int) {
        let o = max(0, min(offset, length))
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= o { lo = mid } else { hi = mid - 1 }
        }
        return (lo, o - starts[lo])
    }

    /// Applies `range -> replacement`; returns the LSP change entry, or nil if the range does not fit.
    mutating func replace(_ range: NSRange, with replacement: NSString) -> [String: Any]? {
        guard range.location >= 0, NSMaxRange(range) <= length else { return nil }
        // Edits that touch a "\r" (CRLF / lone CR terminators merge and split with their neighbours, and servers'
        // incremental line tables disagree on those cases) are not worth the risk: the caller falls back to full sync.
        func hasCR(_ r: NSRange) -> Bool { r.length > 0 && text.range(of: "\r", options: .literal, range: r).location != NSNotFound }
        let before: unichar = range.location > 0 ? text.character(at: range.location - 1) : 0
        if hasCR(range) || replacement.range(of: "\r", options: .literal).location != NSNotFound || before == 13 {
            return nil
        }
        let s = position(of: range.location), e = position(of: NSMaxRange(range))
        let change: [String: Any] = [
            "range": ["start": ["line": s.line, "character": s.character], "end": ["line": e.line, "character": e.character]],
            "text": replacement as String,
        ]
        // Line table update: drop starts inside (loc, end], shift the rest, insert the new text's line starts.
        let lo = upperBound(range.location), hi = upperBound(NSMaxRange(range))
        starts.removeSubrange(lo..<hi)
        let delta = replacement.length - range.length
        if delta != 0 { for i in lo..<starts.count { starts[i] += delta } }
        var fresh: [Int] = []
        var k = 0
        let n = replacement.length
        while k < n {
            let r = replacement.range(of: "\n", range: NSRange(location: k, length: n - k))
            if r.location == NSNotFound { break }
            fresh.append(range.location + r.location + 1)
            k = r.location + 1
        }
        if !fresh.isEmpty { starts.insert(contentsOf: fresh, at: lo) }
        text.replaceCharacters(in: range, with: replacement as String)
        return change
    }

    /// First index whose start is > value.
    private func upperBound(_ v: Int) -> Int {
        var lo = 0, hi = starts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= v { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    func matches(_ other: NSString) -> Bool { text.isEqual(other) }
}
