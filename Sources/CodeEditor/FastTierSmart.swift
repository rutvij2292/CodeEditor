import Foundation

// Smart completion (Ctrl-Shift-Space): only candidates of the expected type at the caret, including ONE-step chains
// (`$cart->getOwner()->wallet()`, `$this->repo->find()`), static factories (`Money::zero()`), enum cases (`Status::Draft`),
// `new Money()` and the variables / `$this` properties of the scope that have the type. The CompletionController keeps only items
// with typeMatch > 0 in smart mode, so everything built here carries a verdict. Nothing is cached; class files come from the same
// per-request / per-project class cache the plain completion uses, and subtype checks are budgeted.

extension FTEval {
    /// A member whose value (type `vt`, reached by `base`) has a no-argument member of the expected type: `base` + `->member`.
    /// `base` is the text already offered (`getOwner()` / `owner` / `$cart->owner()`), `kind` the kind of the combined item.
    func chainItem(base: String, valueType vt: String, expected e: FTExpected, budget: inout Int, visit: inout Int,
                   insertBase: String, replaceRange: NSRange?, filter: String? = nil) -> [CompletionItem] {
        guard visit > 0, !FTEval.scalarNames.contains(vt.lowercased()) else { return [] }
        visit -= 1
        var out: [CompletionItem] = []
        var seen = Set<String>()
        for (idx, k) in hierarchy(vt).enumerated() where idx < 6 {
            for m in k.methods where m.vis == 0 && !m.isStatic && !m.name.hasPrefix("__") && m.params.trimmingCharacters(in: .whitespaces).isEmpty {
                let t = typeMatch(FTEval.valueType(m.ret, owner: k), e, budget: &budget)
                guard t > 0, seen.insert(m.name).inserted else { continue }
                var it = CI.make(base + "->" + m.name + "()", .method, detail: m.ret, insert: insertBase + "->" + m.name + "()", sort: "0" + m.name.lowercased(), range: replaceRange)
                it.filterText = filter ?? (base + "->" + m.name)
                it.typeMatch = t
                it.priority = 30
                out.append(it)
            }
            for p in k.props where p.vis == 0 && !p.isStatic {
                let t = typeMatch(FTEval.valueType(p.type, owner: k), e, budget: &budget)
                guard t > 0, seen.insert(p.name).inserted else { continue }
                var it = CI.make(base + "->" + p.name, .property, detail: p.type, insert: insertBase + "->" + p.name, sort: "0" + p.name.lowercased(), range: replaceRange)
                it.filterText = filter ?? (base + "->" + p.name)
                it.typeMatch = t
                it.priority = 30
                out.append(it)
            }
        }
        return out
    }

    /// One-step chains for the members listed after `->`: members of the receiver that are not of the expected type themselves but
    /// return an object that has a member of it. `items` are the plain member items (with `valueType`).
    func smartChains(after items: [CompletionItem], expected e: FTExpected, limit: Int = 24) -> [CompletionItem] {
        var out: [CompletionItem] = []
        var budget = 24, visit = limit
        for it in items where it.typeMatch == 0 {
            guard let vt = it.valueType, it.kind == .method || it.kind == .property || it.kind == .field else { continue }
            if it.kind == .method, !(it.insertText.hasSuffix("()") && !it.isSnippet) { continue }       // needs arguments: no chain
            let base = it.kind == .method ? it.label + "()" : it.label
            let insertBase = it.kind == .method ? it.label + "()" : it.label
            var chained = chainItem(base: base, valueType: vt, expected: e, budget: &budget, visit: &visit, insertBase: insertBase, replaceRange: it.replaceRange,
                                    filter: it.label + "->")
            for i in chained.indices { chained[i].filterText = it.label + "->" + (chained[i].label.components(separatedBy: "->").last ?? "") }
            out += chained
            if visit <= 0 { break }
        }
        return out
    }
}

extension NPResolver {
    /// Smart candidates for a position that starts an expression (`foo(|`, `return |`, `$x = |`, `$|`): typed variables, their one-step
    /// chains, `$this` properties, static factories / enum cases / `new` of the expected classes.
    func smartExpressionItems(expected e: FTExpected, lo: Int, range: NSRange, dollarTyped: Bool, caretPrefixIsName: Bool) -> [CompletionItem] {
        var out: [CompletionItem] = []
        var budget = 24, visit = 20
        let vars = typedVariables(atToken: lo)
        for v in vars where v.valueType != nil {
            let vt = v.valueType!
            let t = ev.typeMatch(vt, e, budget: &budget)
            // label `$name`; typed after a `$` the range already includes it, otherwise the identifier prefix is replaced by the whole `$name`
            if t > 0 {
                var it = CI.make(v.name, .variable, detail: (vt as NSString).lastPathComponent, range: range)
                if !dollarTyped { it.filterText = String(v.name.dropFirst()) }
                it.valueType = vt; it.typeMatch = t; it.priority = 20
                out.append(it)
            } else {
                var chained = ev.chainItem(base: v.name, valueType: vt, expected: e, budget: &budget, visit: &visit, insertBase: v.name, replaceRange: range)
                for i in chained.indices where !dollarTyped { chained[i].filterText = String(v.name.dropFirst()) + "->" + (chained[i].label.components(separatedBy: "->").last ?? "") }
                out += chained
            }
        }
        // `$this->prop` of the current class
        if let c = cur, !c.fqn.isEmpty {
            for p in c.props where !p.isStatic {
                let t = ev.typeMatch(FTEval.valueType(p.type, owner: c), e, budget: &budget)
                guard t > 0 else { continue }
                var it = CI.make("$this->" + p.name, .property, detail: p.type, range: range)
                it.filterText = dollarTyped ? "this->" + p.name : "this->" + p.name
                it.valueType = FTEval.valueType(p.type, owner: c); it.typeMatch = t; it.priority = 22
                out.append(it)
            }
        }
        if dollarTyped { return out }          // after `$` only variables / `$this` members make sense
        // classes of the expected type: factories, enum cases, `new`
        for fqn in e.classes.prefix(3) {
            let h = ev.hierarchy(fqn)
            guard let k = h.first else { continue }
            let (shortInsert, edits) = cur.map { FastEngine.importEdit(fqn, short: k.name, cur: $0, text: ns) } ?? (k.name, [])
            if k.kind == "enum" {
                for cs in k.cases {
                    var it = CI.make("\(k.name)::\(cs)", .enumMember, detail: k.name, insert: "\(shortInsert)::\(cs)", sort: "0" + cs.lowercased(), range: range)
                    it.filterText = "\(k.name)::\(cs)"; it.additionalEdits = edits
                    it.valueType = fqn; it.typeMatch = 2; it.priority = 10
                    out.append(it)
                }
            }
            var seen = Set<String>()
            for (idx, kk) in h.enumerated() where idx < 6 {
                for m in kk.methods where m.vis == 0 && m.isStatic && !m.name.hasPrefix("__") && seen.insert(m.name).inserted {
                    let t = ev.typeMatch(FTEval.valueType(m.ret, owner: kk), e, budget: &budget)
                    guard t > 0 else { continue }
                    let call = CI.callInsert(m.name, params: m.params)
                    var it = CI.make("\(k.name)::\(m.name)()", .method, detail: m.ret, insert: "\(shortInsert)::" + call, snippet: true, sort: "1" + m.name.lowercased(), range: range)
                    it.filterText = "\(k.name)::\(m.name)"; it.additionalEdits = edits
                    it.valueType = fqn; it.typeMatch = t; it.priority = 12
                    out.append(it)
                }
            }
            if k.kind == "class", !k.isAbstract {
                var params = ""
                for (idx, kk) in h.enumerated() where idx < 6 { if let c = kk.method(named: "__construct") { params = c.params; break } }
                let call = CI.callInsert(k.name, params: params)
                var it = CI.make("new \(k.name)()", .class, detail: fqn, insert: "new \(shortInsert)" + String(call.dropFirst(k.name.count)), snippet: true, sort: "2" + k.name.lowercased(), range: range)
                it.filterText = "new \(k.name)"; it.additionalEdits = edits
                it.valueType = fqn; it.typeMatch = 2; it.priority = 14
                out.append(it)
            }
        }
        return out
    }
}
