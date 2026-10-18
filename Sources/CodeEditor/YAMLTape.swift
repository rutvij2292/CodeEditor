import Foundation
import SwiftTreeSitter

/// Builds a StructTape (and syntax diagnostics) from the tree-sitter YAML parse tree. Multi-document files become an array
/// of documents. Runs on any queue (it owns its Parser; only the immutable `Language` is shared).
enum YAMLTapeBuilder {
    static let maxBytes = 3_000_000

    static func parse(_ text: String, language: Language, maxNodes: Int = 300_000) -> StructTape {
        let tape = StructTape()
        tape.isJSON = false
        let ns = text as NSString
        tape.slice = { a, b in
            let lo = max(0, min(a, ns.length)), hi = max(lo, min(b, ns.length))
            return ns.substring(with: NSRange(location: lo, length: hi - lo))
        }
        tape.toUTF16 = { $0 }
        let parser = Parser()
        do { try parser.setLanguage(language) } catch { return tape }
        guard let tree = parser.parse(text), let rootNode = tree.rootNode else { return tape }
        var b = Builder(tape: tape, ns: ns, maxNodes: maxNodes)
        b.collectErrors(rootNode)
        b.checkTabs()
        var docs: [Node] = []
        for i in 0..<rootNode.namedChildCount {
            if let c = rootNode.namedChild(at: i), c.nodeType == "document" { docs.append(c) }
        }
        func content(_ doc: Node) -> Node? {
            for i in 0..<doc.namedChildCount {
                if let c = doc.namedChild(at: i), let t = c.nodeType, t == "block_node" || t == "flow_node" { return c }
            }
            return nil
        }
        if docs.count == 1 {
            if let c = content(docs[0]) { _ = b.convert(c, parent: -1, last: -1, key: nil) }
        } else if docs.count > 1 {
            let r = tape.add(.array, start: Int(docs[0].range.location), parent: -1, after: -1)
            var last: Int32 = -1
            for d in docs {
                if let c = content(d) {
                    let n = b.convert(c, parent: r, last: last, key: nil)
                    if n >= 0 { last = n }
                }
            }
            tape.close(r, end: ns.length)
        }
        return tape
    }

    private struct Builder {
        let tape: StructTape
        let ns: NSString
        let maxNodes: Int
        var depth = 0

        init(tape: StructTape, ns: NSString, maxNodes: Int) { self.tape = tape; self.ns = ns; self.maxNodes = maxNodes }

        func lineEnd(from loc: Int) -> Int {
            guard loc < ns.length else { return ns.length }
            return NSMaxRange(ns.lineRange(for: NSRange(location: loc, length: 0))) - 1
        }

        mutating func addIssue(_ sev: Int, _ message: String, _ loc: Int, _ len: Int) {
            guard tape.issues.count < 50 else { return }
            let l = max(0, min(loc, ns.length))
            let end = lineEnd(from: l)
            tape.issues.append(StructIssue(severity: sev, message: message, offset: l, length: max(1, min(len, max(1, end - l)))))
        }

        mutating func collectErrors(_ node: Node) {
            guard node.hasError || node.isMissing else { return }
            if node.isMissing {
                addIssue(1, "Missing \(node.nodeType ?? "token")", node.range.location, 1)
                return
            }
            if node.nodeType == "ERROR" {
                addIssue(1, "Syntax error", node.range.location, node.range.length)
                return
            }
            for i in 0..<node.childCount { if let c = node.child(at: i) { collectErrors(c) } }
        }

        /// Tabs in indentation are illegal YAML.
        mutating func checkTabs() {
            let len = ns.length
            var pos = 0
            var errorLines = Set(tape.issues.map { ns.lineRange(for: NSRange(location: min($0.offset, max(0, len - 1)), length: 0)).location })
            while pos < len, tape.issues.count < 50 {
                let lr = ns.lineRange(for: NSRange(location: pos, length: 0))
                var j = lr.location
                let e = NSMaxRange(lr)
                while j < e, ns.character(at: j) == 32 { j += 1 }
                if j < e, ns.character(at: j) == 9, !errorLines.contains(lr.location) {
                    // A tab right after a block scalar / plain line is content; only flag when something follows the tab.
                    var k = j
                    while k < e, ns.character(at: k) == 9 || ns.character(at: k) == 32 { k += 1 }
                    if k < e, ns.character(at: k) != 10, ns.character(at: k) != 13 {
                        addIssue(2, "Tabs must not be used for indentation", j, 1)
                        errorLines.insert(lr.location)
                    }
                }
                pos = e
            }
        }

        func scalarKind(_ node: Node) -> StructKind {
            var n = node
            // plain_scalar -> typed child
            if n.nodeType == "plain_scalar", let c = n.namedChild(at: 0) { n = c }
            switch n.nodeType ?? "" {
            case "null_scalar": return .null
            case "boolean_scalar": return .bool
            case "integer_scalar", "float_scalar": return .number
            default: return .string
            }
        }

        mutating func emit(_ k: StructKind, _ range: NSRange, parent: Int32, last: Int32, key: NSRange?) -> Int32 {
            if tape.nodeCount >= maxNodes { tape.truncated = true; return -1 }
            let idx = tape.add(k, start: range.location, keyStart: key.map { $0.location } ?? -1, keyEnd: key.map { NSMaxRange($0) } ?? -1,
                               parent: parent, after: last)
            tape.close(idx, end: NSMaxRange(range))
            return idx
        }

        /// The significant content node of a block_node / flow_node wrapper (skips anchor, tag, comment).
        func unwrap(_ node: Node) -> Node? {
            var cur = node
            for _ in 0..<8 {
                let t = cur.nodeType ?? ""
                guard t == "block_node" || t == "flow_node" else { return cur }
                var next: Node?
                for i in 0..<cur.namedChildCount {
                    guard let c = cur.namedChild(at: i), let ct = c.nodeType else { continue }
                    if ct == "anchor" || ct == "tag" || ct == "comment" { continue }
                    next = c; break
                }
                guard let n = next else { return nil }
                cur = n
            }
            return cur
        }

        mutating func convert(_ wrapper: Node, parent: Int32, last: Int32, key: NSRange?) -> Int32 {
            guard depth < 200 else { return -1 }
            depth += 1
            defer { depth -= 1 }
            guard let node = unwrap(wrapper) else {
                return emit(.null, NSRange(location: wrapper.range.location, length: 0), parent: parent, last: last, key: key)
            }
            switch node.nodeType ?? "" {
            case "block_mapping", "flow_mapping":
                let me = emit(.object, node.range, parent: parent, last: last, key: key)
                var lastChild: Int32 = -1
                var seen = Set<String>()
                for i in 0..<node.namedChildCount {
                    guard let pair = node.namedChild(at: i), let pt = pair.nodeType, pt == "block_mapping_pair" || pt == "flow_pair" else { continue }
                    let k = pair.child(byFieldName: "key")
                    let v = pair.child(byFieldName: "value")
                    let keyRange = k?.range ?? NSRange(location: pair.range.location, length: 0)
                    if let k {
                        let text = StructTape.unquote(ns.substring(with: k.range), json: false)
                        if text != "<<", !seen.insert(text).inserted { addIssue(2, "Duplicate key '\(text.prefix(40))'", keyRange.location, keyRange.length) }
                    }
                    let child: Int32
                    if let v {
                        child = convert(v, parent: me, last: lastChild, key: keyRange)
                    } else {
                        child = emit(.null, NSRange(location: NSMaxRange(pair.range), length: 0), parent: me, last: lastChild, key: keyRange)
                    }
                    if child >= 0 { lastChild = child }
                }
                return me
            case "block_sequence", "flow_sequence":
                let me = emit(.array, node.range, parent: parent, last: last, key: key)
                var lastChild: Int32 = -1
                for i in 0..<node.namedChildCount {
                    guard let item = node.namedChild(at: i), let it = item.nodeType, it != "comment" else { continue }
                    let child: Int32
                    if it == "block_sequence_item" {
                        var inner: Node?
                        for j in 0..<item.namedChildCount {
                            if let c = item.namedChild(at: j), c.nodeType != "comment" { inner = c; break }
                        }
                        if let inner { child = convert(inner, parent: me, last: lastChild, key: nil) }
                        else { child = emit(.null, NSRange(location: NSMaxRange(item.range), length: 0), parent: me, last: lastChild, key: nil) }
                    } else if it == "flow_pair" {
                        let o = emit(.object, item.range, parent: me, last: lastChild, key: nil)
                        if o >= 0, let k = item.child(byFieldName: "key") {
                            if let v = item.child(byFieldName: "value") { _ = convert(v, parent: o, last: -1, key: k.range) }
                            else { _ = emit(.null, NSRange(location: NSMaxRange(item.range), length: 0), parent: o, last: -1, key: k.range) }
                        }
                        child = o
                    } else {
                        child = convert(item, parent: me, last: lastChild, key: nil)
                    }
                    if child >= 0 { lastChild = child }
                }
                return me
            case "plain_scalar":
                return emit(scalarKind(node), node.range, parent: parent, last: last, key: key)
            case "double_quote_scalar", "single_quote_scalar", "block_scalar", "alias":
                return emit(.string, node.range, parent: parent, last: last, key: key)
            default:
                return emit(.string, node.range, parent: parent, last: last, key: key)
            }
        }
    }
}
