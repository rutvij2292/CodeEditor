import Foundation
import SwiftTreeSitter

extension NJSTy {
    /// True when no part of the type is `unknown` (the evaluator's "could not decide"): only such types are ever shown.
    var fullyKnown: Bool { known(0) }
    private func known(_ d: Int) -> Bool {
        if d > 6 { return false }
        switch self {
        case .unknown: return false
        case .array(let e): return e.known(d + 1)
        case .tuple(let l), .union(let l), .inter(let l): return l.allSatisfy { $0.known(d + 1) }
        case .ref(let r): return r.args.allSatisfy { $0.known(d + 1) }
        case .fn(let f): return f.ret.known(d + 1) && f.params.allSatisfy { $0.ty.known(d + 1) }
        case .cond, .index: return false
        case .overloads(let l): return l.allSatisfy { NJSTy.fn($0).known(d + 1) }
        case .obj(let o): return o.members.allSatisfy { $0.ty.known(d + 1) }
        default: return true
        }
    }
}

/// Phase 3 entry points: definition / hover / completion for receivers and declarations whose type is inferred.
extension NJSEnv {
    /// Declarations of member `name` on the inferred type of `object`; empty when the type is not fully decided.
    func inferredMember(of object: Node, _ name: String) -> [NJSRes] {
        let t = infer.ty(object)
        if t.isUnknown || t.isAny { return [] }
        return typer.members(of: t, name: name).compactMap { $0.res }
    }

    /// Hover text with the inferred type for a declaration that leaves its type to inference; nil unless certain.
    func inferredHover(token node: Node, res r: NJSRes, current md: String) -> String? {
        var tyNode: Node = node
        if node.kind == "property_identifier", let p = node.parent, p.kind == "member_expression", p.field("property") == node { tyNode = p }
        else if node.kind != "identifier" { return nil }
        let label: String
        switch r.kind {
        case .variable, .constant: label = (r.keyword ?? "var") + " " + r.name
        case .parameter: label = "(parameter) " + r.name
        case .property: label = "(property) " + (r.owner.map { $0 + "." } ?? "") + r.name
        default: return nil
        }
        let t = typer.complete(infer.ty(tyNode))
        guard t.fullyKnown else { return nil }
        let text = label + ": " + t.describeMultiline()
        guard text.count <= 600 else { return nil }
        guard md.hasPrefix("```typescript\n"), let end = md.range(of: "\n```", range: md.index(md.startIndex, offsetBy: 14)..<md.endIndex) else { return "```typescript\n\(text)\n```" }
        return "```typescript\n\(text)" + md[end.lowerBound...]
    }

    func inferredCompletion(object: Node) -> [CompletionItem] {
        let t = infer.ty(object)
        if t.isUnknown || t.isAny { return [] }
        var out: [CompletionItem] = []
        for m in typer.allMembers(of: t) {
            var kind: CompletionKind = .property
            if let k = m.res?.kind {
                switch k {
                case .method: kind = .method
                case .function: kind = .function
                case .class: kind = .class
                case .interface, .typeAlias: kind = .interface
                case .enum: kind = .enum
                case .enumMember: kind = .enumMember
                case .namespace: kind = .module
                case .constant: kind = .constant
                case .variable: kind = .variable
                default: break
                }
            } else if case .fn = m.ty { kind = .method }
            var detail = m.ty.fullyKnown ? m.ty.describe() : ""
            if detail.count > 90 { detail = String(detail.prefix(90)) + "..." }
            out.append(CompletionItem(label: m.name, insertText: m.name, kind: kind, detail: detail))
        }
        return out
    }
}

extension NJSEnv {
    /// Developer aid (CE_NJS_WHY): the inferred type of the receiver of the member at `offset`.
    func whyReceiver(at offset: Int) -> String {
        guard let leaf = doc.leaf(at: offset), let p = leaf.parent else { return "no leaf" }
        let target: Node = (p.kind == "member_expression" ? p.field("object") : nil) ?? leaf
        let t = infer.ty(target)
        if AppEnv.value("CE_NJS_LIBDBG") != nil, let dir = NJSLib.directory(forRoot: proj.root) { fputs("LIB root=\(proj.root) dir=\(dir) roots=\(NJSLib.rootNames(dir: dir, config: proj.modules.config(for: path))) cfg=\(proj.modules.config(for: path)?.path ?? "none")\n", stderr) }
        return target.kind + " " + target.text(doc.text).prefix(60) + " : " + t.describe() + (typer.exhausted ? " (budget spent)" : "")
    }
}
