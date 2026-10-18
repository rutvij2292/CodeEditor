import Foundation

/// Three-way line merge (diff3). Non-overlapping changes merge, identical changes merge,
/// overlapping differing changes (including touching ones) become conflicts.
enum Diff3 {
    struct Hunk {
        enum Kind { case clean(String), conflict(ours: String, theirs: String, base: String) }
        let kind: Kind
    }

    /// One aligned region with all three sides; `merged == nil` means conflict.
    struct Detail {
        let base: String, ours: String, theirs: String
        let merged: String?
        var isConflict: Bool { merged == nil }
    }

    private struct Region { var bs: Int, be: Int, xs: Int, xe: Int }

    private static func regions(_ ops: [DiffEngine.Op]) -> [Region] {
        var out: [Region] = []
        var i = 0, j = 0, k = 0
        while k < ops.count {
            if ops[k] == .equal { i += 1; j += 1; k += 1; continue }
            let start = (i, j)
            while k < ops.count, ops[k] != .equal {
                if ops[k] == .delete { i += 1 } else { j += 1 }
                k += 1
            }
            out.append(Region(bs: start.0, be: i, xs: start.1, xe: j))
        }
        return out
    }

    static func merge(base: String?, ours: String, theirs: String) -> [Hunk] {
        var hunks: [Hunk] = []
        var pending = ""
        func flush() { if !pending.isEmpty { hunks.append(Hunk(kind: .clean(pending))); pending = "" } }
        for d in detailed(base: base, ours: ours, theirs: theirs) {
            if let m = d.merged { pending += m } else {
                flush()
                hunks.append(Hunk(kind: .conflict(ours: d.ours, theirs: d.theirs, base: d.base)))
            }
        }
        flush()
        return hunks
    }

    static func detailed(base: String?, ours: String, theirs: String) -> [Detail] {
        let o = DiffEngine.splitLines(ours), t = DiffEngine.splitLines(theirs)
        guard let baseText = base else { return twoWay(o, t) }
        let b = DiffEngine.splitLines(baseText)
        let ids = DiffEngine.intern([b, o, t])
        let ra = regions(DiffEngine.edit(ids[0], ids[1], maxD: 3000))
        let rb = regions(DiffEngine.edit(ids[0], ids[2], maxD: 3000))
        func join(_ l: [String], _ r: Range<Int>) -> String { l[r].joined() }

        var out: [Detail] = []
        var ia = 0, ib = 0, pos = 0
        while ia < ra.count || ib < rb.count {
            let gs = min(ia < ra.count ? ra[ia].bs : Int.max, ib < rb.count ? rb[ib].bs : Int.max)
            if gs > pos { let s = join(b, pos..<gs); out.append(Detail(base: s, ours: s, theirs: s, merged: s)) }
            var ga: [Region] = [], gb: [Region] = []
            var ge = gs
            var took = true
            while took {
                took = false
                if ia < ra.count, ra[ia].bs <= ge { ga.append(ra[ia]); ge = max(ge, ra[ia].be); ia += 1; took = true }
                if ib < rb.count, rb[ib].bs <= ge { gb.append(rb[ib]); ge = max(ge, rb[ib].be); ib += 1; took = true }
            }
            func side(_ g: [Region], _ lines: [String]) -> String {
                var text = "", cur = gs
                for r in g { text += join(b, cur..<r.bs) + join(lines, r.xs..<r.xe); cur = r.be }
                return text + join(b, cur..<ge)
            }
            let ot = side(ga, o), tt = side(gb, t), bt = join(b, gs..<ge)
            let merged: String? = gb.isEmpty ? ot : (ga.isEmpty ? tt : (ot == tt ? ot : nil))
            out.append(Detail(base: bt, ours: ot, theirs: tt, merged: merged))
            pos = ge
        }
        if pos < b.count { let s = join(b, pos..<b.count); out.append(Detail(base: s, ours: s, theirs: s, merged: s)) }
        return out
    }

    /// No base: common lines are clean, every differing region is an add/add style conflict.
    private static func twoWay(_ o: [String], _ t: [String]) -> [Detail] {
        let ids = DiffEngine.intern([o, t])
        var out: [Detail] = []
        var i = 0
        for r in regions(DiffEngine.edit(ids[0], ids[1], maxD: 3000)) {
            if r.bs > i { let s = o[i..<r.bs].joined(); out.append(Detail(base: s, ours: s, theirs: s, merged: s)) }
            out.append(Detail(base: "", ours: o[r.bs..<r.be].joined(), theirs: t[r.xs..<r.xe].joined(), merged: nil))
            i = r.be
        }
        if i < o.count { let s = o[i...].joined(); out.append(Detail(base: s, ours: s, theirs: s, merged: s)) }
        return out
    }
}
