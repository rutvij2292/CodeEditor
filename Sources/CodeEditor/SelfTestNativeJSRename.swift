import Foundation

extension SelfTestNativeJS {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    /// Rename: exact edits across files, alias / shorthand / pattern handling, refusals and conflicts.
    static func runRename() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njsren-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        buildFixture(root)
        put(root, "src/main.ts", main)
        put(root, "src/other.ts", "import { helper as h, VALUE } from './util'\nimport W from './util'\nconst w2 = new W()\nh(1)\nw2.name\nconst { name } = w2\nconst { name: n2 } = w2\nconst o = { VALUE }\n")
        put(root, "src/Tpl.vue", "<template><p>{{ helper(1) }}</p></template>\n<script setup>\nimport { helper } from './util'\n</script>\n")
        let proj = NJSProject.shared(root: root.path)
        let mainURL = root.appendingPathComponent("src/main.ts")

        func symbol(_ file: URL, _ text: String, _ needle: String, _ nth: Int = 0, plus: Int = 1) -> (NJSRefSymbol, NJSDoc?, String?)? {
            let at = off(text, needle, nth, plus: plus)
            var doc: NJSDoc?
            var out: (NJSRefSymbol, String?)?
            proj.queue.sync {
                guard let env = NativeJS.env(url: file, text: text as NSString, root: root.path), let sym = NJSRefs.identify(env: env, offset: at) else { return }
                doc = env.doc
                out = (sym, NJSRename.refusal(sym, env: env))
            }
            return out.map { ($0.0, doc, $0.1) }
        }
        func rename(_ file: URL, _ text: String, _ needle: String, to name: String, _ nth: Int = 0) -> (NJSRenamePlan, NJSRename.ApplyResult?) {
            guard let (sym, doc, why) = symbol(file, text, needle, nth) else { var p = NJSRenamePlan(symbol: NJSRefSymbol(name: "?", decls: [], isMember: false, root: root.path, declFile: ""), newName: name); p.conflict = "not identified"; return (p, nil) }
            if let why { var p = NJSRenamePlan(symbol: sym, newName: name); p.conflict = why; return (p, nil) }
            NJSRefs.dropMemos(); NJSRefs.dropFileList()
            let plan = NJSRename.plan(sym, newName: name, liveDoc: doc, liveTexts: [:])
            guard plan.conflict == nil else { return (plan, nil) }
            return (plan, NJSRename.apply(plan, tabFor: { _ in nil }))
        }
        func read(_ rel: String) -> String { (try? String(contentsOf: root.appendingPathComponent(rel))) ?? "" }

        // a Vue file whose template uses the name blocks the rename of a symbol it imports
        let (pv, _) = rename(mainURL, main, "helper(V)", to: "fmt")
        check("rename: a .vue file that mentions the name in its template refuses", pv.conflict?.contains("template") == true)
        try? fm.removeItem(at: root.appendingPathComponent("src/Tpl.vue"))

        let (p1, r1) = rename(mainURL, main, "helper(V)", to: "fmt")
        check("rename: function renamed across declaration, imports, calls, re-export, namespace member", r1?.applied == true && p1.fileCount >= 4)
        check("rename: declaration", read("src/util.ts").contains("export function fmt(a: number)"))
        check("rename: named import and call", read("src/main.ts").contains("{ fmt, VALUE as V, Color }") && read("src/main.ts").contains("fmt(V)") && read("src/main.ts").contains("util.fmt(2)"))
        check("rename: the alias keeps its own name", read("src/other.ts").contains("{ fmt as h, VALUE }") && read("src/other.ts").contains("\nh(1)"))
        check("rename: re-export name token, alias intact", read("src/models/index.ts").contains("fmt as help"))
        check("rename: unrelated same-name binding is untouched", read("src/main.ts").contains("function shadow(helper: number) { return helper }"))

        let main2 = read("src/main.ts")
        let (p2, r2) = rename(mainURL, main2, "helper: number", to: "q")
        check("rename: a parameter changes only inside its function", r2?.applied == true && p2.editCount == 2 && read("src/main.ts").contains("function shadow(q: number) { return q }"))

        let (pc, _) = rename(mainURL, read("src/main.ts"), "VALUE as V", to: "Color")
        check("rename: collision with an existing declaration is refused", pc.conflict != nil)
        let (pr, _) = rename(mainURL, read("src/main.ts"), "VALUE as V", to: "class")
        check("rename: reserved words and bad identifiers are refused", pr.conflict?.contains("reserved") == true)
        let (pb, _) = rename(mainURL, read("src/main.ts"), "VALUE as V", to: "1abc")
        check("rename: invalid identifier is refused", pb.conflict?.contains("valid") == true)

        // members: class property, patterns
        let other = read("src/other.ts")
        let (p3, r3) = rename(root.appendingPathComponent("src/other.ts"), other, "name\nconst { name }", to: "label")
        check("rename: member renamed across files", r3?.applied == true && p3.fileCount >= 2)
        check("rename: declaration and property access", read("src/util.ts").contains("label: string = ''") && read("src/other.ts").contains("w2.label"))
        check("rename: shorthand pattern keeps the local name, pair key is renamed", read("src/other.ts").contains("const { label: name } = w2") && read("src/other.ts").contains("const { label: n2 } = w2"))
        check("rename: inherited this.name in a subclass follows", read("src/main.ts").contains("this.label"))

        // shorthand of a variable
        let (p4, r4) = rename(root.appendingPathComponent("src/other.ts"), read("src/other.ts"), "VALUE } from", to: "LIMITX")
        _ = p4
        check("rename: a shorthand property of a renamed variable keeps its key", r4?.applied == true && read("src/other.ts").contains("{ VALUE: LIMITX }"))

        // import bindings are local to their file: default, namespace and aliased imports
        put(root, "src/third.ts", "import Widget from './util'\nimport * as ut from './util'\nimport { Owner as Own } from './util'\nconst a = new Widget()\nut.helper\nnew Own()\n")
        let thirdURL = root.appendingPathComponent("src/third.ts")
        let (pd, rd) = rename(thirdURL, read("src/third.ts"), "Widget()", to: "Gadget")
        check("rename: a default import binding changes this file only", rd?.applied == true && pd.fileCount == 1 && read("src/third.ts").contains("import Gadget from './util'") && read("src/third.ts").contains("new Gadget()") && read("src/util.ts").contains("export default class Widget"))
        let (pn, rn) = rename(thirdURL, read("src/third.ts"), "ut.helper", to: "lib")
        check("rename: a namespace import binding changes this file only", rn?.applied == true && pn.fileCount == 1 && read("src/third.ts").contains("import * as lib from") && read("src/third.ts").contains("lib.helper"))
        let (pa, ra) = rename(thirdURL, read("src/third.ts"), "Own()", to: "Mine")
        check("rename: clicking an alias renames the alias, not the exported class", ra?.applied == true && pa.fileCount == 1 && read("src/third.ts").contains("{ Owner as Mine }") && read("src/third.ts").contains("new Mine()") && read("src/util.ts").contains("export class Owner"))
        let (pdup, _) = rename(thirdURL, read("src/third.ts"), "Gadget()", to: "Mine")
        check("rename: a name the file already uses is refused", pdup.conflict != nil)

        // refusals: dependency and structural members
        check("rename: a declaration in node_modules is refused", symbol(mainURL, read("src/main.ts"), "pkgFn('x')")?.2 != nil)
        check("rename: a member of an interface is refused (object literals may implement it)", symbol(mainURL, read("src/main.ts"), "bio")?.2 != nil || symbol(mainURL, read("src/main.ts"), "profile\\n") == nil)
    }
}


extension SelfTestNativeJS {
    /// Signature help.
    static func runSig() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njssig-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        buildFixture(root)
        put(root, "src/sigs.ts", "export function over(a: number): number\nexport function over(a: string, b: boolean): string\nexport function over(a: any, b?: any): any { return a }\nexport const arrow = (x: number, y = 2): number => x + y\nexport class Pt { constructor(public x: number, y?: string) {} move(dx: number, ...rest: string[]): void {} }\n")
        let head = "import { over, arrow, Pt } from './sigs'\nimport { helper, default as Widget } from './util'\nconst p = new Pt(1)\n"
        let url = root.appendingPathComponent("src/use.ts")
        func help(_ tail: String) -> (sigs: [String], active: Int, param: Int, docs: [String])? {
            let text = head + tail
            guard case .help(let payload) = NativeJS.signatureHelp(url: url, text: text as NSString, caret: (text as NSString).length) else { return nil }
            let sigs = (payload["signatures"] as? [[String: Any]]) ?? []
            let docs = ((sigs.first?["parameters"] as? [[String: Any]]) ?? []).map { ($0["documentation"] as? String) ?? "" }
            return (sigs.map { ($0["label"] as? String) ?? "" }, (payload["activeSignature"] as? Int) ?? -1, (payload["activeParameter"] as? Int) ?? -1, docs)
        }
        func outcomeKind(_ tail: String) -> String {
            let text = head + tail
            switch NativeJS.signatureHelp(url: url, text: text as NSString, caret: (text as NSString).length) { case .help: return "help"; case .notInCall: return "none"; case .unknown: return "unknown" }
        }
        let a = help("over(1, ")
        check("sig: overloads are listed, the implementation is hidden", a?.sigs == ["over(a: number): number", "over(a: string, b: boolean): string"])
        check("sig: the overload that fits the argument count is active, with the active parameter", a?.active == 1 && a?.param == 1)
        check("sig: an arrow function const", help("arrow(")?.sigs == ["arrow(x: number, y = 2): number"] && help("arrow(")?.param == 0)
        check("sig: a constructor through new (parameter properties keep their modifiers)", help("new Pt(1, ")?.sigs == ["new Pt(public x: number, y?: string)"] && help("new Pt(1, ")?.param == 1)
        check("sig: a method; the rest parameter takes the extra arguments", help("p.move(1, 'a', 'b', ")?.sigs == ["move(dx: number, ...rest: string[]): void"] && help("p.move(1, 'a', 'b', ")?.param == 1)
        check("sig: JSDoc @param text becomes the parameter documentation", help("helper(")?.docs == ["the number"])
        check("sig: a class without a constructor shows new X()", help("new Widget(")?.sigs == ["new Widget()"])
        check("sig: the nested call is the one asked about", help("over(arrow(1, ")?.sigs == ["arrow(x: number, y = 2): number"] && help("over(arrow(1, ")?.param == 1)
        check("sig: outside any call there is no popup", outcomeKind("over(1)") == "none" && outcomeKind("const z = 1") == "none")
        check("sig: an unresolvable callee is left to the server", outcomeKind("mystery(") == "unknown" && outcomeKind("console.log(") == "unknown")
        check("sig: inside a callback body is not an argument position", outcomeKind("over(() => { const q = ") == "none")
    }
}
