import Foundation
import SwiftTreeSitter

/// Headless checks of the native JS / TS service (module resolution, go to definition, hover) on a synthetic project.
enum SelfTestNativeJS {
    static func dump(_ n: Node, _ ns: NSString, _ indent: Int, field: String?, out: inout String) {
        let t = n.text(ns)
        out += String(repeating: " ", count: indent) + (field.map { $0 + ": " } ?? "") + n.kind + (n.namedChildCount == 0 ? " '\(t.prefix(40))'" : "") + "\n"
        for i in 0..<n.childCount {
            guard let c = n.child(at: i) else { continue }
            if !c.isNamed { continue }
            dump(c, ns, indent + 1, field: n.fieldNameForChild(at: i), out: &out)
        }
    }

    /// Developer hooks, run before anything else: CE_NJS_DUMP=<file> prints the syntax tree, CE_NJS_BENCH=<project> benchmarks.
    static func devHooks() {
        if let p = AppEnv.value("CE_NJS_DUMP") {
            let t = (try? String(contentsOfFile: p)) ?? ""
            guard let d = NJSDoc(path: p, text: t as NSString) else { fputs("parse failed\n", stderr); exit(1) }
            var out = ""
            dump(d.root, d.text, 0, field: nil, out: &out)
            fputs(out, stderr); exit(0)
        }
        if let p = AppEnv.value("CE_NJS_BENCH") { NativeJSBench.run(p); exit(0) }
        if AppEnv.value("CE_NJS_ONLY") != nil { run(); runRefs(); SelfTest.finish() }
    }

    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func put(_ root: URL, _ rel: String, _ text: String) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    /// Offset of the `nth` occurrence of `needle` in `text` (+ `plus` characters).
    static func off(_ text: String, _ needle: String, _ nth: Int = 0, plus: Int = 0) -> Int {
        let ns = text as NSString
        var from = 0, found = NSNotFound
        for _ in 0...nth {
            let r = ns.range(of: needle, options: [], range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { return -1 }
            found = r.location; from = NSMaxRange(r)
        }
        return found + plus
    }

    static func buildFixture(_ root: URL) {
        put(root, "package.json", "{\"name\":\"fx\"}")
        put(root, "tsconfig.json", """
        {
          // comments and trailing commas are allowed
          "compilerOptions": { "baseUrl": ".", "paths": { "@/*": ["src/*"], "~lib": ["lib/index.ts",], }, },
        }
        """)
        put(root, "src/util.ts", """
        /**
         * Formats a number.
         * @param a the number
         * @returns text
         */
        export function helper(a: number): string { return String(a) }
        export const VALUE = 1
        export const LIMIT: number = 10
        export default class Widget extends Base {
          static make(): Widget { return new Widget() }
          name: string = ''
          owner: Owner = new Owner()
          run(n: number): void {}
          get title(): string { return '' }
        }
        export class Base { baseMethod(): void {} protected base2 = 1 }
        export class Owner { email = ''; ping(): Owner { return this } }
        export type Id = number | string
        export enum Color { Red, Green }
        """)
        put(root, "src/models/user.ts", """
        export interface User { id: number; name: string; profile: Profile }
        export class Profile { bio: string = '' }
        """)
        put(root, "src/models/index.ts", """
        export * from './user'
        export { default as Widget, helper as help } from '../util'
        """)
        put(root, "lib/index.ts", "export const libValue = 2\n")
        put(root, "node_modules/pkg/package.json", "{\"name\":\"pkg\",\"main\":\"./dist/index.js\",\"types\":\"./dist/index.d.ts\"}")
        put(root, "node_modules/pkg/dist/index.d.ts", "export declare function pkgFn(x: string): number;\nexport interface PkgOpts { verbose: boolean }\n")
        put(root, "node_modules/pkg/dist/index.js", "exports.pkgFn = function () {}\n")
        put(root, "node_modules/@types/chunky/index.d.ts", """
        export = Chunky;
        declare function Chunky(x: number): void;
        declare namespace Chunky { function chunk(a: any[]): any[]; interface Options { size: number } class Thing { go(): void } }
        """)
        put(root, "node_modules/exp/package.json", "{\"name\":\"exp\",\"exports\":{\".\":{\"types\":\"./t.d.ts\",\"default\":\"./i.js\"},\"./sub\":{\"import\":\"./sub.js\"}}}")
        put(root, "node_modules/exp/t.d.ts", "export declare const expVal: number;\n")
        put(root, "node_modules/exp/i.js", "export const expVal = 1\n")
        put(root, "node_modules/exp/sub.js", "export const subVal = 1\n")
        put(root, "src/cjs.js", """
        function legacy(a) { return a }
        class Store { constructor() { this.items = [] ; this.helper = new Helper() } add(x) {} }
        class Helper { assist() {} }
        module.exports = { legacy, Store }
        exports.extra = function () {}
        """)
        put(root, "src/Card.jsx", "export default function Card({ title }) { return <div>{title}</div> }\nexport const Small = () => <i/>\n")
        put(root, "src/Comp.vue", "<template><div/></template>\n<script>\nexport default { name: 'Comp' }\n</script>\n")
        put(root, "src/data.json", "{\"a\":1}\n")
    }

    static let main = """
    import Widget, { helper, VALUE as V, Color } from '@/util'
    import { User, Profile, help } from './models'
    import type { Id } from '@/util'
    import * as util from './util'
    import { pkgFn } from 'pkg'
    import chunk, { Options } from 'chunky'
    import { expVal } from 'exp'
    import { libValue } from '~lib'
    import missing from './nope'
    import data from './data.json'
    import Comp from './Comp.vue'

    function use(u: User, id: Id) {
      const w = new Widget()
      w.name
      w.owner.email
      Widget.make().run(1)
      helper(V)
      u.profile.bio
      util.helper(2)
      pkgFn('x')
      chunk.chunk([])
      expVal + libValue
      console.log(Color.Red, Promise)
      w.baseMethod()
      w.title
      w.owner.ping().email
    }
    function shadow(helper: number) { return helper }
    class Local extends Widget {
      own = 1
      go() { this.own; this.name; this.run(2); this.baseMethod() }
    }
    export { helper as h2 }
    """

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njs-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        buildFixture(root)
        let url = root.appendingPathComponent("src/main.ts")
        put(root, "src/main.ts", main)
        let text = main as NSString

        func hit(_ needle: String, _ nth: Int = 0, plus: Int = 1, in t: String = main, file: URL? = nil) -> NPHit? {
            let u = file ?? url
            return NativeJS.lookup(url: u, text: t as NSString, offset: off(t, needle, nth, plus: plus), root: root.path)
        }
        func where_(_ h: NPHit?) -> String {
            guard let t = h?.targets.first else { return "nil" }
            let p = t.path.hasPrefix(root.path + "/") ? String(t.path.dropFirst(root.path.count + 1)) : t.path
            return "\(p):\(t.line)"
        }
        func is_(_ name: String, _ needle: String, _ nth: Int = 0, _ expect: String) {
            let got = where_(hit(needle, nth))
            check("js: \(name) -> \(expect)" + (got == expect ? "" : " (got \(got))"), got == expect)
        }
        _ = text

        // module specifiers
        is_("path string './models'", "'./models'", 0, "src/models/index.ts:1")
        is_("alias '@/util' string", "'@/util'", 0, "src/util.ts:1")
        is_("paths exact '~lib'", "'~lib'", 0, "lib/index.ts:1")
        is_("node_modules types field", "'pkg'", 0, "node_modules/pkg/dist/index.d.ts:1")
        is_("@types package", "'chunky'", 0, "node_modules/@types/chunky/index.d.ts:1")
        is_("exports map types condition", "'exp'", 0, "node_modules/exp/t.d.ts:1")
        is_("json import path", "'./data.json'", 0, "src/data.json:1")
        is_("missing module is not guessed", "'./nope'", 0, "nil")
        // import specifiers and usages
        is_("named import specifier", "helper", 0, "src/util.ts:6")
        is_("renamed import (VALUE as V)", "VALUE", 0, "src/util.ts:7")
        is_("default import binding", "Widget", 0, "src/util.ts:9")
        is_("re-export alias through index (help)", "help", 0, "src/util.ts:6")
        is_("export * chain (User)", "User", 0, "src/models/user.ts:1")
        is_("type import", "Id", 0, "src/util.ts:18")
        is_("enum import", "Color", 0, "src/util.ts:19")
        is_("usage of imported function", "helper(V)", 0, "src/util.ts:6")
        is_("usage of alias V", "V)", 0, "src/util.ts:7")
        is_("namespace import member util.helper", "helper(2)", 0, "src/util.ts:6")
        is_("namespace import identifier -> file", "util.helper", 0, "src/util.ts:1")
        is_("package function pkgFn", "pkgFn('x')", 0, "node_modules/pkg/dist/index.d.ts:1")
        is_("export = namespace member (chunk.chunk)", "chunk([", 0, "node_modules/@types/chunky/index.d.ts:3")
        is_("export = default import", "chunk, ", 0, "node_modules/@types/chunky/index.d.ts:2")
        is_("exports map value", "expVal +", 0, "node_modules/exp/t.d.ts:1")
        is_("paths alias value", "libValue\n", 0, "lib/index.ts:1")
        is_("vue default import -> file", "Comp ", 0, "src/Comp.vue:1")
        // members
        is_("member of new X (w.name)", "name\n  w.owner", 0, "src/util.ts:11")
        is_("member through typed property (w.owner.email)", "email\n  Widget", 0, "src/util.ts:17")
        is_("static method + chained return type", "run(1)", 0, "src/util.ts:13")
        is_("typed param chain (u.profile.bio)", "bio", 0, "src/models/user.ts:2")
        is_("inherited member via extends", "baseMethod()\n  w.title", 0, "src/util.ts:16")
        is_("getter", "title\n  w.owner.ping", 0, "src/util.ts:14")
        is_("method return type chain (ping().email)", "email\n}", 0, "src/util.ts:17")
        is_("this.own", "own;", 0, "src/main.ts:31")
        is_("this.name (inherited)", "name;", 0, "src/util.ts:11")
        is_("this.run", "run(2)", 0, "src/util.ts:13")
        is_("this.baseMethod (two levels)", "baseMethod()", 1, "src/util.ts:16")
        // scope
        is_("shadowing parameter beats the import", "helper }", 0, "src/main.ts:29")
        is_("builtin global stays with the server", "console", 0, "nil")
        is_("Promise stays with the server", "Promise)", 0, "nil")
        is_("declaration itself resolves to itself", "use(u", 0, "src/main.ts:13")
        is_("export specifier", "helper as h2", 0, "src/util.ts:6")

        // hover
        if let h = hit("helper(V)") {
            check("js hover: signature", h.markdown.contains("function helper(a: number): string"))
            check("js hover: jsdoc text and tags", h.markdown.contains("Formats a number.") && h.markdown.contains("*@param* `a`") && h.markdown.contains("*@returns* text"))
            check("js hover: defining file is named", h.markdown.contains("src/util.ts"))
        } else { check("js hover: resolves", false) }
        check("js hover: const with a literal", hit("VALUE", 0)?.markdown.contains("const VALUE = 1") == true)
        check("js hover: member label", hit("name\n  w.owner")?.markdown.contains("(property) Widget.name: string") == true)
        check("js hover: class shows heritage", hit("Widget", 1)?.markdown.contains("class Widget extends Base") == true)

        // JS: CommonJS, class fields assigned in the constructor, JSX
        let jsMain = """
        const { legacy, Store } = require('./cjs')
        const cjs = require('./cjs')
        const Card = require('./Card')
        import CardDefault, { Small } from './Card'
        const s = new Store()
        s.items
        s.add(1)
        s.helper.assist()
        legacy(1)
        cjs.extra()
        function View() { return <div><CardDefault title="x" /><Small /></div> }
        """
        put(root, "src/app.jsx", jsMain)
        let jsx = root.appendingPathComponent("src/app.jsx")
        func jhit(_ needle: String, _ nth: Int = 0, plus: Int = 1) -> String { where_(hit(needle, nth, plus: plus, in: jsMain, file: jsx)) }
        check("js cjs: destructured require binding -> module.exports member", jhit("legacy(1)") == "src/cjs.js:1")
        check("js cjs: class through destructured require", jhit("Store()") == "src/cjs.js:2")
        check("js cjs: require path string", jhit("'./cjs'") == "src/cjs.js:1")
        check("js cjs: this.items assigned in the constructor", jhit("items\ns.add") == "src/cjs.js:2")
        check("js cjs: method of required class", jhit("add(1)") == "src/cjs.js:2")
        check("js cjs: property typed by `new Helper()`", jhit("assist") == "src/cjs.js:3")
        check("js cjs: exports.extra", jhit("extra()") == "src/cjs.js:5")
        check("jsx: component usage resolves to its function", jhit("CardDefault title") == "src/Card.jsx:1")
        check("jsx: named component", jhit("Small />") == "src/Card.jsx:2")
        check("jsx: intrinsic element is not resolved", jhit("div>", 0, plus: 0) == "nil")

        // Vue: script block only
        let vue = "<template><button @click=\"go\">{{ go }}</button></template>\n<script lang=\"ts\">\nimport { helper } from '@/util'\nexport default { name: 'X', methods: { go() { return helper(1) } } }\n</script>\n"
        put(root, "src/Page.vue", vue)
        let vurl = root.appendingPathComponent("src/Page.vue")
        check("vue: import in the script block resolves", where_(NativeJS.lookup(url: vurl, text: vue as NSString, offset: off(vue, "helper }", 0, plus: 1), root: root.path)) == "src/util.ts:6")
        check("vue: usage in the script block resolves", where_(NativeJS.lookup(url: vurl, text: vue as NSString, offset: off(vue, "helper(1)", 0, plus: 1), root: root.path)) == "src/util.ts:6")
        check("vue: template tokens are left to the server", NativeJS.lookup(url: vurl, text: vue as NSString, offset: off(vue, "{{ go", 0, plus: 4), root: root.path) == nil)

        // resolution details
        let mods = NJSModules(root: root.path)
        check("resolve: ./x.js maps to x.ts", { put(root, "src/e.ts", "export {}"); return mods.resolve("./e.js", from: url.path)?.hasSuffix("src/e.ts") == true }())
        check("resolve: directory index", mods.resolve("./models", from: url.path)?.hasSuffix("src/models/index.ts") == true)
        check("resolve: pattern with * suffix", mods.resolve("@/models/user", from: url.path)?.hasSuffix("src/models/user.ts") == true)
        check("resolve: unknown bare package", mods.resolve("no-such-package", from: url.path) == nil)
        check("resolve: exports map subpath without types falls back to the target", mods.resolve("exp/sub", from: url.path)?.hasSuffix("node_modules/exp/sub.js") == true)
        let cfg = NJSJSON.parse(Data("{/*c*/\"a\":[1,2,],\"b\":\"x//y\",}".utf8)) as? [String: Any]
        check("jsonc: comments, trailing commas, // inside strings", (cfg?["a"] as? [Int]) == [1, 2] && (cfg?["b"] as? String) == "x//y")

        // caches stay small
        let proj = NJSProject.shared(root: root.path)
        check("caches: summaries bounded", proj.cachedSummaries <= NJSProject.maxEntries && proj.cachedCost <= NJSProject.maxCost)
        NativeJS.trimMemory()
        check("caches: trimMemory empties them", proj.queue.sync { proj.cachedSummaries } == 0)
        check("disabled by the preference", { NativeJS.enabled = false; defer { NativeJS.enabled = true }; return NativeJS.lookup(url: url, text: main as NSString, offset: off(main, "helper(V)", 0, plus: 1), root: root.path) == nil }())
    }
}
