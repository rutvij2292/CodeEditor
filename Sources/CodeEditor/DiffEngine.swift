import Foundation

/// Line-based Myers diff with row alignment for side-by-side display, plus word-level intra-line ranges.
enum DiffEngine {
    enum Op { case equal, insert, delete }
    enum Kind { case equal, added, removed, changed }
    struct Row {
        let left: String?
        let right: String?
        let leftLine: Int?
        let rightLine: Int?
        let kind: Kind
    }

    /// Splits keeping line terminators ("a\nb" -> ["a\n", "b"]).
    static func splitLines(_ s: String) -> [String] {
        var lines: [String] = []
        let bytes = Array(s.utf8)
        var start = 0
        for i in 0..<bytes.count where bytes[i] == 10 {
            lines.append(String(decoding: bytes[start...i], as: UTF8.self))
            start = i + 1
        }
        if start < bytes.count { lines.append(String(decoding: bytes[start...], as: UTF8.self)) }
        return lines
    }

    /// CRLF and LF compare equal; a missing final newline still counts as a difference.
    private static func normalized(_ line: String) -> String {
        guard line.utf8.last == 10 else { return line }
        var u = Array(line.utf8.dropLast())
        if u.last == 13 { u.removeLast() }
        return String(decoding: u, as: UTF8.self) + "\n"
    }

    private static func display(_ line: String) -> String {
        var u = Array(line.utf8)
        if u.last == 10 { u.removeLast() }
        if u.last == 13 { u.removeLast() }
        return String(decoding: u, as: UTF8.self)
    }

    /// Interns strings to ints so the diff compares integers only.
    static func intern(_ lists: [[String]]) -> [[Int]] {
        var table: [String: Int] = [:]
        return lists.map { list in
            list.map { s in
                if let id = table[s] { return id }
                let id = table.count
                table[s] = id
                return id
            }
        }
    }

    static func rows(old: String, new: String) -> [Row] {
        let a = splitLines(old), b = splitLines(new)
        let ids = intern([a.map(normalized), b.map(normalized)])
        let ops = edit(ids[0], ids[1], maxD: 2000)
        var rows: [Row] = []
        rows.reserveCapacity(ops.count)
        var i = 0, j = 0, k = 0
        while k < ops.count {
            if ops[k] == .equal {
                rows.append(Row(left: display(a[i]), right: display(b[j]), leftLine: i + 1, rightLine: j + 1, kind: .equal))
                i += 1; j += 1; k += 1
                continue
            }
            var dels = 0, ins = 0
            while k < ops.count, ops[k] != .equal {
                if ops[k] == .delete { dels += 1 } else { ins += 1 }
                k += 1
            }
            let paired = min(dels, ins)
            for n in 0..<max(dels, ins) {
                let l = n < dels ? i + n : nil, r = n < ins ? j + n : nil
                let kind: Kind = n < paired ? .changed : (l != nil ? .removed : .added)
                rows.append(Row(left: l.map { display(a[$0]) }, right: r.map { display(b[$0]) },
                                leftLine: l.map { $0 + 1 }, rightLine: r.map { $0 + 1 }, kind: kind))
            }
            i += dels; j += ins
        }
        return rows
    }

    /// Full edit script over integer sequences. Common prefix/suffix are trimmed first; if the
    /// middle needs more than `maxD` edits it degrades to delete-all + insert-all.
    static func edit(_ a: [Int], _ b: [Int], maxD: Int) -> [Op] {
        var lo = 0
        while lo < a.count, lo < b.count, a[lo] == b[lo] { lo += 1 }
        var ea = a.count, eb = b.count
        while ea > lo, eb > lo, a[ea - 1] == b[eb - 1] { ea -= 1; eb -= 1 }
        var ops = [Op](repeating: .equal, count: lo)
        let ma = Array(a[lo..<ea]), mb = Array(b[lo..<eb])
        ops += myers(ma, mb, maxD: maxD) ?? (Array(repeating: .delete, count: ma.count) + Array(repeating: .insert, count: mb.count))
        ops += [Op](repeating: .equal, count: a.count - ea)
        return ops
    }

    private static func myers(_ a: [Int], _ b: [Int], maxD cap: Int) -> [Op]? {
        let n = a.count, m = b.count
        if n == 0 { return Array(repeating: .insert, count: m) }
        if m == 0 { return Array(repeating: .delete, count: n) }
        let maxD = min(cap, n + m)
        let off = maxD + 1
        var v = [Int](repeating: 0, count: 2 * maxD + 3)
        var trace: [[Int]] = []
        var found = -1
        outer: for d in 0...maxD {
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[off + k - 1] < v[off + k + 1]) { x = v[off + k + 1] } else { x = v[off + k - 1] + 1 }
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[off + k] = x
                if x >= n && y >= m { found = d; break outer }
                k += 2
            }
            trace.append(Array(v[(off - d)...(off + d)]))
        }
        if found < 0 { return nil }
        var ops: [Op] = []
        var x = n, y = m, d = found
        while d > 0 {
            let pv = trace[d - 1]
            let k = x - y
            let base = d - 1
            let prevK = (k == -d || (k != d && pv[k - 1 + base] < pv[k + 1 + base])) ? k + 1 : k - 1
            let prevX = pv[prevK + base], prevY = prevX - prevK
            while x > prevX, y > prevY { ops.append(.equal); x -= 1; y -= 1 }
            ops.append(x == prevX ? .insert : .delete)
            x = prevX; y = prevY; d -= 1
        }
        while x > 0, y > 0 { ops.append(.equal); x -= 1; y -= 1 }
        return ops.reversed()
    }

    // MARK: intra-line

    private static func tokens(_ s: String) -> [(Range<String.Index>, String)] {
        var out: [(Range<String.Index>, String)] = []
        var i = s.startIndex
        func cls(_ c: Character) -> Int { c.isLetter || c.isNumber || c == "_" ? 1 : (c.isWhitespace ? 2 : 0) }
        while i < s.endIndex {
            let c = cls(s[i])
            var j = s.index(after: i)
            if c != 0 { while j < s.endIndex, cls(s[j]) == c { j = s.index(after: j) } }
            out.append((i..<j, String(s[i..<j])))
            i = j
        }
        return out
    }

    static func intraLine(_ a: String, _ b: String) -> (a: [Range<String.Index>], b: [Range<String.Index>]) {
        let ta = tokens(a), tb = tokens(b)
        if ta.count > 3000 || tb.count > 3000 {
            return (a.isEmpty ? [] : [a.startIndex..<a.endIndex], b.isEmpty ? [] : [b.startIndex..<b.endIndex])
        }
        let ids = intern([ta.map { $0.1 }, tb.map { $0.1 }])
        let ops = edit(ids[0], ids[1], maxD: 600)
        var ra: [Range<String.Index>] = [], rb: [Range<String.Index>] = []
        func add(_ list: inout [Range<String.Index>], _ r: Range<String.Index>) {
            if let last = list.last, last.upperBound == r.lowerBound { list[list.count - 1] = last.lowerBound..<r.upperBound } else { list.append(r) }
        }
        var i = 0, j = 0
        for op in ops {
            switch op {
            case .equal: i += 1; j += 1
            case .delete: add(&ra, ta[i].0); i += 1
            case .insert: add(&rb, tb[j].0); j += 1
            }
        }
        return (ra, rb)
    }
}
