import AppKit

/// One row of the commit graph: where the commit's dot sits and which lane segments cross the row.
struct GitGraphRow: Equatable {
    var column = 0
    var color = 0
    /// Lane segments that enter from the top and end at this commit's dot (merged children).
    var ins: [(lane: Int, color: Int)] = []
    /// Segments from the dot down to the parents' lanes.
    var outs: [(lane: Int, color: Int)] = []
    /// Lanes that run straight through the row without touching the commit.
    var through: [(lane: Int, color: Int)] = []
    var laneCount = 1

    static func == (a: GitGraphRow, b: GitGraphRow) -> Bool {
        a.column == b.column && a.color == b.color && a.laneCount == b.laneCount
            && a.ins.map(\.lane) == b.ins.map(\.lane) && a.outs.map(\.lane) == b.outs.map(\.lane) && a.through.map(\.lane) == b.through.map(\.lane)
    }
}

enum GitGraphLayout {
    static let paletteSize = 8

    /// Lane assignment for commits in `git log` order (children before parents).
    static func rows(for commits: [GitCommit]) -> [GitGraphRow] {
        var lanes: [(hash: String, color: Int)?] = []
        var nextColor = 0
        func newColor() -> Int { defer { nextColor += 1 }; return nextColor % paletteSize }
        func freeLane() -> Int {
            if let i = lanes.firstIndex(where: { $0 == nil }) { return i }
            lanes.append(nil); return lanes.count - 1
        }
        var out: [GitGraphRow] = []
        out.reserveCapacity(commits.count)
        for c in commits {
            var row = GitGraphRow()
            let mine = lanes.indices.filter { lanes[$0]?.hash == c.hash }
            let col: Int
            if let first = mine.first { col = first } else { col = freeLane(); lanes[col] = (c.hash, newColor()) }
            row.column = col
            row.color = lanes[col]!.color
            for i in mine { row.ins.append((i, lanes[i]!.color)) }   // a branch tip (no children shown) has none
            let before = lanes
            for i in mine { lanes[i] = nil }
            // parents
            for (n, p) in c.parents.enumerated() {
                if let existing = lanes.firstIndex(where: { $0?.hash == p }) {
                    row.outs.append((existing, lanes[existing]!.color))
                } else if n == 0 {
                    lanes[col] = (p, row.color)
                    row.outs.append((col, row.color))
                } else {
                    let l = freeLane()
                    let color = newColor()
                    lanes[l] = (p, color)
                    row.outs.append((l, color))
                }
            }
            for (i, l) in before.enumerated() where l != nil && !mine.contains(i) { row.through.append((i, l!.color)) }
            row.laneCount = max(lanes.count, before.count, col + 1)
            while let last = lanes.last, last == nil { lanes.removeLast() }
            out.append(row)
        }
        return out
    }

    static let palette: [NSColor] = [
        Theme.hex(0x4CAF50), Theme.hex(0x5B9BD5), Theme.hex(0xCB8A3D), Theme.hex(0x8E5BC5),
        Theme.hex(0xD05A6E), Theme.hex(0x2FA6A6), Theme.hex(0x9BAA3A), Theme.hex(0x4A5BC7),
    ]
}

/// Draws one graph row: lane lines and the commit dot.
final class GitGraphCell: NSView {
    static let laneWidth: CGFloat = 12
    var row = GitGraphRow()
    var isMerge = false
    override var isFlipped: Bool { true }

    static func width(forLanes n: Int) -> CGFloat { CGFloat(min(max(n, 1), 10)) * laneWidth + 10 }

    private func x(_ lane: Int) -> CGFloat { 8 + CGFloat(min(lane, 9)) * Self.laneWidth }

    override func draw(_ dirtyRect: NSRect) {
        let mid = bounds.midY
        func color(_ i: Int) -> NSColor { GitGraphLayout.palette[i % GitGraphLayout.paletteSize] }
        func line(_ from: NSPoint, _ to: NSPoint, _ c: NSColor) {
            let p = NSBezierPath()
            p.move(to: from)
            if from.x == to.x { p.line(to: to) }
            else { p.curve(to: to, controlPoint1: NSPoint(x: from.x, y: (from.y + to.y) / 2), controlPoint2: NSPoint(x: to.x, y: (from.y + to.y) / 2)) }
            p.lineWidth = 1.5
            c.setStroke(); p.stroke()
        }
        for t in row.through { line(NSPoint(x: x(t.lane), y: 0), NSPoint(x: x(t.lane), y: bounds.maxY), color(t.color)) }
        for i in row.ins { line(NSPoint(x: x(i.lane), y: 0), NSPoint(x: x(row.column), y: mid), color(i.color)) }
        for o in row.outs { line(NSPoint(x: x(row.column), y: mid), NSPoint(x: x(o.lane), y: bounds.maxY), color(o.color)) }
        let c = color(row.color)
        let dot = NSRect(x: x(row.column) - 3.5, y: mid - 3.5, width: 7, height: 7)
        if isMerge {
            Theme.background.setFill(); NSBezierPath(ovalIn: dot).fill()
            c.setStroke(); let p = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1.5; p.stroke()
        } else {
            c.setFill(); NSBezierPath(ovalIn: dot).fill()
        }
    }
}
