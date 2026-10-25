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
        check("sig: an unresolvable callee is left to the server", outcomeKind("mystery(") == "unknown")
        check("sig: inside a callback body is not an argument position", outcomeKind("over(() => { const q = ") == "none")
    }
}


extension SelfTestNativeJS {
    /// The TypeScript standard library: lib selection by tsconfig, globals, merged interfaces, constructors, hover and signature help.
    static func runLib() {
        guard let bundled = NJSLib.bundledDirectory() else { check("lib: bundled TsLib/ directory found", false); return }
        NJSLib.directoryOverride = bundled
        defer { NJSLib.directoryOverride = nil; NJSLib.trim() }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njslib-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        put(root, "package.json", "{}")
        func where_(_ code: String, _ needle: String, ext: String = "ts", nth: Int = 0) -> [String] {
            let url = root.appendingPathComponent("t_\(abs(code.hashValue) % 100000).\(ext)")
            let h = NativeJS.lookup(url: url, text: code as NSString, offset: off(code, needle, nth, plus: 1), root: root.path)
            return (h?.targets ?? []).map { ((($0.path as NSString).lastPathComponent) + ":\($0.line)") }
        }
        // default program: lib.es2025.full (what tsc 7 uses without a tsconfig)
        check("lib: Math.round -> lib.es5.d.ts", where_("Math.round(1)", "round").first?.hasPrefix("lib.es5.d.ts:") == true)
        check("lib: console.log -> lib.dom.d.ts", where_("console.log(1)", "log").first?.hasPrefix("lib.dom.d.ts:") == true)
        check("lib: JSON.parse", where_("JSON.parse('1')", "parse").first?.hasPrefix("lib.es5.d.ts:") == true)
        check("lib: Object.assign lives in es2015.core", where_("Object.assign({}, {})", "assign").first?.hasPrefix("lib.es2015.core.d.ts:") == true)
        let all = where_("Promise.all([])", "all")
        check("lib: merged interface members come from every declaring file (Promise.all)", all.contains { $0.hasPrefix("lib.es2015.promise.d.ts:") } && all.contains { $0.hasPrefix("lib.es2015.iterable.d.ts:") })
        check("lib: Object.entries -> es2017.object, Object.groupBy -> es2024.object, Promise.withResolvers -> es2024.promise",
              where_("Object.entries({})", "entries").first?.hasPrefix("lib.es2017.object.d.ts:") == true && where_("Object.groupBy([], x => x)", "groupBy").first?.hasPrefix("lib.es2024.object.d.ts:") == true
              && where_("Promise.withResolvers()", "withResolvers").first?.hasPrefix("lib.es2024.promise.d.ts:") == true)
        check("lib: document.title", where_("document.title", "title").first?.hasPrefix("lib.dom.d.ts:") == true)
        check("lib: constructed instances (new Map().set)", where_("const m = new Map()\nm.set(1, 2)", "set").first?.hasPrefix("lib.es2015.collection.d.ts:") == true)
        check("lib: the global itself", where_("Promise.all([])", "Promise").contains { $0.hasPrefix("lib.es") })
        check("lib: a type annotation (Promise<void>)", !where_("function f(): Promise<void> { return Promise.resolve() }", "Promise").isEmpty)
        // the lines match the file the server reports (TypeScript 7 libs)
        check("lib: exact lines of the TypeScript 7 libs", where_("Math.round(1)", "round") == ["lib.es5.d.ts:749"] && where_("JSON.parse('1')", "parse") == ["lib.es5.d.ts:1161"] && where_("Object.assign({}, {})", "assign").contains("lib.es2015.core.d.ts:284"))

        // lib selection by tsconfig
        put(root, "es5/tsconfig.json", "{\"compilerOptions\":{\"target\":\"es5\"}}")
        put(root, "es2017/tsconfig.json", "{// c\n\"compilerOptions\":{\"target\":\"es2017\",\"lib\":[\"es2017\",\"dom\"]}}")
        put(root, "es2015/tsconfig.json", "{\"compilerOptions\":{\"lib\":[\"es2015\"]}}")
        put(root, "esnext/tsconfig.json", "{\"compilerOptions\":{\"target\":\"esnext\"}}")
        func in_(_ dir: String, _ code: String, _ needle: String) -> [String] {
            let url = root.appendingPathComponent(dir + "/t.ts")
            let h = NativeJS.lookup(url: url, text: code as NSString, offset: off(code, needle, 0, plus: 1), root: root.path)
            return (h?.targets ?? []).map { (($0.path as NSString).lastPathComponent) + ":\($0.line)" }
        }
        check("lib: target es5 keeps the ES2015 libs (as tsc 7 does) but not ES2017", !in_("es5", "Object.assign({}, {})", "assign").isEmpty && in_("es5", "Object.entries({})", "entries").isEmpty)
        check("lib: lib [es2017, dom] has entries, no groupBy", !in_("es2017", "Object.entries({})", "entries").isEmpty && in_("es2017", "Object.groupBy([], x => x)", "groupBy").isEmpty && !in_("es2017", "document.title", "title").isEmpty)
        check("lib: lib [es2015] has no DOM", in_("es2015", "console.log(1)", "log").isEmpty && in_("es2015", "document.title", "title").isEmpty && !in_("es2015", "Math.round(1)", "round").isEmpty)
        check("lib: target esnext adds the esnext libs", !in_("esnext", "Array.fromAsync([])", "fromAsync").isEmpty && NativeJS.lookup(url: root.appendingPathComponent("t_x.ts"), text: "Array.fromAsync([])" as NSString, offset: 8, root: root.path) == nil)

        // hover and signature help come from the libs too
        let hov = NativeJS.lookup(url: root.appendingPathComponent("h.ts"), text: "Math.round(1)" as NSString, offset: 6, root: root.path)
        check("lib: hover shows the declaration and its doc comment", hov?.markdown.contains("round(x: number): number") == true && hov?.markdown.contains("Returns a supplied numeric expression rounded to the nearest integer") == true)
        func sig(_ code: String) -> [String] {
            guard case .help(let p) = NativeJS.signatureHelp(url: root.appendingPathComponent("s.ts"), text: code as NSString, caret: (code as NSString).length) else { return [] }
            return ((p["signatures"] as? [[String: Any]]) ?? []).map { ($0["label"] as? String) ?? "" }
        }
        check("lib: signature help of a global function", sig("parseInt(").first?.hasPrefix("parseInt(string: string, radix?: number)") == true)
        check("lib: signature help of a method and of a constructor", sig("Math.max(").first?.hasPrefix("max(...values: number[])") == true && sig("new Map(").contains { $0.hasPrefix("new Map(") })
        check("lib: no memory beyond the index: the lib files stay memory mapped", NJSLib.indexCount >= 1)
    }
}


extension SelfTestNativeJS {
    /// Ambient modules (`declare module`), `declare global` and script globals of @types packages.
    static func runAmbient() {
        guard let bundled = NJSLib.bundledDirectory() else { return }
        NJSLib.directoryOverride = bundled
        defer { NJSLib.directoryOverride = nil; NJSLib.trim() }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njsamb-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        put(root, "package.json", "{}")
        put(root, "node_modules/@types/node/package.json", "{\"name\":\"@types/node\",\"types\":\"index.d.ts\"}")
        put(root, "node_modules/@types/node/index.d.ts", "/// <reference path=\"path.d.ts\" />\n/// <reference path=\"globals.d.ts\" />\n")
        put(root, "node_modules/@types/node/path.d.ts", """
        declare module "node:path" {
            namespace path {
                interface ParsedPath { root: string; dir: string }
                interface PlatformPath {
                    /** Resolves a sequence of paths. */
                    resolve(...paths: string[]): string;
                    sep: string;
                }
            }
            const path: path.PlatformPath;
            export = path;
        }
        declare module "path" {
            import path = require("node:path");
            export = path;
        }

        """)
        put(root, "node_modules/@types/node/globals.d.ts", """
        declare function require(id: string): any;
        declare global {
            var process: NodeJS.Process;
            namespace NodeJS {
                interface Process { cwd(): string; env: ProcessEnv }
                interface ProcessEnv { [key: string]: string | undefined }
            }
        }

        """)
        put(root, "node_modules/@types/other/package.json", "{\"name\":\"@types/other\"}")
        put(root, "node_modules/@types/other/index.d.ts", "declare var otherGlobal: { go(): void };\ndeclare class Gadget { spin(): void }\n")
        func t(_ code: String, _ needle: String, nth: Int = 0) -> [String] {
            let url = root.appendingPathComponent("src/a.ts")
            let h = NativeJS.lookup(url: url, text: code as NSString, offset: off(code, needle, nth, plus: 1), root: root.path)
            return (h?.targets ?? []).map { (($0.path as NSString).lastPathComponent) + ":\($0.line)" }
        }
        check("ambient: `import path from 'path'` reaches the module (export = const of an interface type)", t("import path from 'path'\npath.resolve('x')", "resolve").first?.hasPrefix("path.d.ts:") == true)
        check("ambient: a named import from an `export =` module", t("import { resolve } from 'node:path'\nresolve('x')", "resolve").first?.hasPrefix("path.d.ts:") == true)
        check("ambient: the specifier string itself", t("import path from 'path'", "'path'").first?.hasPrefix("path.d.ts:") == true)
        check("ambient: a global declared inside `declare global` (process.cwd())", t("process.cwd()", "cwd").first?.hasPrefix("globals.d.ts:") == true)
        check("ambient: a nested namespace type through a global (process.env)", t("process.env", "env").first?.hasPrefix("globals.d.ts:") == true)
        check("ambient: script-level declarations of another @types package (class, var)", t("new Gadget().spin()", "spin").first?.hasPrefix("index.d.ts:") == true && t("otherGlobal.go()", "go").first?.hasPrefix("index.d.ts:") == true)
        check("ambient: a plain script function (require)", t("require('x')", "require").first?.hasPrefix("globals.d.ts:") == true)
        let hov = NativeJS.lookup(url: root.appendingPathComponent("src/b.ts"), text: "import path from 'path'\npath.resolve('x')" as NSString, offset: off("import path from 'path'\npath.resolve('x')", "resolve", 0, plus: 1), root: root.path)
        check("ambient: hover with the doc comment", hov?.markdown.contains("resolve(...paths: string[]): string") == true && hov?.markdown.contains("Resolves a sequence of paths") == true)
        put(root, "restricted/tsconfig.json", "{\"compilerOptions\":{\"types\":[\"other\"]}}")
        let url2 = root.appendingPathComponent("restricted/c.ts")
        check("ambient: tsconfig `types` restricts the automatic packages", NativeJS.lookup(url: url2, text: "process.cwd()" as NSString, offset: 9, root: root.path) == nil
              && NativeJS.lookup(url: url2, text: "otherGlobal.go()" as NSString, offset: 12, root: root.path) != nil)
    }
}
