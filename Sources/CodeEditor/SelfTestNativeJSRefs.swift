import Foundation

extension SelfTestNativeJS {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    /// Find usages: exact (scope / import / member aware) and across files.
    static func runRefs() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njsrefs-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        buildFixture(root)
        put(root, "src/main.ts", main)
        put(root, "src/other.ts", """
        import { helper as h, VALUE } from './util'
        import W from './util'
        import * as u from './util'
        const w2 = new W()
        h(1); h(2)
        const helper = 5            // unrelated binding with the same name
        w2.name; w2.run(3)
        u.helper(4)
        function f(x) { return x.name + x.run }      // unknown receiver
        """)
        put(root, "src/third.ts", "export function helper() {}\nhelper()\n")        // another symbol named helper
        let proj = NJSProject.shared(root: root.path)
        let mainURL = root.appendingPathComponent("src/main.ts")

        func usages(in file: URL, text: String, _ needle: String, _ nth: Int = 0, plus: Int = 1) -> (NPRefsResult, NJSRefSymbol)? {
            let t = text as NSString
            let at = off(text, needle, nth, plus: plus)
            var doc: NJSDoc?
            let sym: NJSRefSymbol? = proj.queue.sync {
                guard let env = NativeJS.env(url: file, text: t, root: root.path) else { return nil }
                doc = env.doc
                return NJSRefs.identify(env: env, offset: at)
            }
            guard let s = sym else { return nil }
            return (NJSRefs.collect(s, liveDoc: doc, liveTexts: [:]), s)
        }
        func summary(_ r: NPRefsResult) -> [String] {
            r.hits.map { h in
                let rel = h.path.hasPrefix(root.path + "/") ? String(h.path.dropFirst(root.path.count + 1)) : h.path
                return "\(rel):\(h.line):\(h.role.rawValue)"
            }
        }

        if let (r, s) = usages(in: mainURL, text: main, "helper(V)") {
            let sm = summary(r)
            check("refs: function usages across files (declaration, imports, calls, namespace member)", s.name == "helper" && sm.contains("src/util.ts:6:declaration")
                  && sm.contains("src/main.ts:1:import") && sm.contains("src/main.ts:18:usage") && sm.contains("src/main.ts:20:usage")
                  && sm.contains("src/other.ts:1:import") && sm.contains("src/other.ts:5:usage") && sm.contains("src/other.ts:8:usage")
                  && sm.contains("src/models/index.ts:2:import"))
            check("refs: aliased import (h) is found without its text matching", sm.filter { $0.hasPrefix("src/other.ts:5") }.count == 2)
            check("refs: unrelated same-name bindings / symbols are excluded", !sm.contains { $0.hasPrefix("src/third.ts") } && !sm.contains("src/other.ts:6:usage") && !sm.contains("src/other.ts:6:declaration"))
            check("refs: shadowing parameter is excluded", !sm.contains("src/main.ts:29:usage") && !sm.contains("src/main.ts:29:declaration"))
        } else { check("refs: function identified", false) }

        if let (r, s) = usages(in: mainURL, text: main, "name\n  w.owner") {
            let sm = summary(r)
            check("refs: member usages via typed receivers", s.isMember && sm.contains("src/util.ts:11:declaration") && sm.contains("src/main.ts:15:usage")
                  && sm.contains("src/other.ts:7:usage") && sm.contains("src/main.ts:32:usage"))
            check("refs: untyped receivers are listed as possible, last", sm.last == "src/other.ts:9:unresolved" && r.resolvedCount < r.hits.count)
        } else { check("refs: member identified", false) }

        if let (r, _) = usages(in: mainURL, text: main, "helper }", 0) {
            let sm = summary(r)
            check("refs: local parameter is scope bounded", sm.sorted() == ["src/main.ts:29:declaration", "src/main.ts:29:usage"])
        } else { check("refs: parameter identified", false) }

        let utilText = (try? String(contentsOf: root.appendingPathComponent("src/util.ts"))) ?? ""
        if let (r, _) = usages(in: root.appendingPathComponent("src/util.ts"), text: utilText, "Widget extends", 0) {
            let sm = summary(r)
            check("refs: class from its declaration (default import with another name)", sm.contains("src/util.ts:9:declaration") && sm.contains("src/other.ts:2:import") && sm.contains("src/other.ts:4:usage") && sm.contains("src/main.ts:14:usage"))
        } else { check("refs: class identified from declaration", false) }
        check("refs: unknown / global tokens are not native", usages(in: mainURL, text: main, "console") == nil)

        // many files: the scan runs on all cores and merges in path order
        for i in 0..<40 { put(root, "src/gen/g\(String(format: "%02d", i)).ts", "import { helper } from '../util'\nexport const v\(i) = helper(\(i))\n") }
        NJSRefs.dropFileList(); NJSRefs.dropMemos()
        if let (rg, _) = usages(in: mainURL, text: main, "helper(V)") {
            let gen = rg.hits.filter { $0.path.contains("/src/gen/") }
            check("refs: 40 files scanned in parallel give 80 hits, in path order, no duplicates", gen.count == 80 && gen.map { $0.path } == gen.map { $0.path }.sorted() && Set(gen.map { "\($0.path):\($0.line)\($0.column)" }).count == 80)
        } else { check("refs: parallel search ran", false) }

        // import graph: scanner flags, pruning, memo
        let sc = NJSScanner.scan("import a, { b } from './x'\nimport * as ns from \"./n\"\nimport { c } from './c'\nexport * from './y'\nexport { a as q } from './r'\nconst z = require('./z')\nmodule.exports = require('./m')\nimport('./d')\nimport './side.css'\nexport { a }\nconst s = 'from ./not-a-spec'\n" as NSString)
        func edge(_ spec: String) -> NJSEdge? { sc.edges.first { $0.spec == spec } }
        check("graph scan: specifiers of every import form", Set(sc.edges.map(\.spec)) == ["./x", "./n", "./c", "./y", "./r", "./z", "./m", "./d", "./side.css"])
        check("graph scan: default / namespace / require bindings vs named", edge("./x")?.binding == true && edge("./n")?.binding == true && edge("./z")?.binding == true && edge("./c")?.binding == false)
        check("graph scan: re-exports and export lists", edge("./y")?.reexport == true && edge("./r")?.reexport == true && edge("./m")?.reexport == true && edge("./x")?.reexport == false && sc.exportsList)
        put(root, "src/lonely.ts", "const helper = 1\nexport function other() { return helper }\n")      // contains the word, imports nothing
        if let (r1, _) = usages(in: mainURL, text: main, "helper(V)") {
            let files1 = Set(r1.hits.map(\.path))
            check("graph: a file that cannot reach the declaration is not even parsed", !files1.contains(root.path + "/src/lonely.ts") && r1.candidates <= 50)
            let t0 = Date()
            let again = usages(in: mainURL, text: main, "helper(V)")
            let dt = Date().timeIntervalSince(t0)
            check("graph: a repeated search is answered from the memo", again?.0.hits.count == r1.hits.count && dt < 0.05)
            put(root, "src/other.ts", "import { helper } from './util'\nhelper(1)\n")
            if let (r3, _) = usages(in: mainURL, text: main, "helper(V)") { check("graph: editing a file invalidates the memo", r3.hits.count != r1.hits.count) } else { check("graph: re-run", false) }
        } else { check("graph: search ran", false) }

        var picked: (String, Int)?
        NativeJSUI.presentHook = { t, items in picked = (t, items.count) }
        if let (r, s) = usages(in: mainURL, text: main, "VALUE as V") { NativeJSUI.present(s, result: r, window: nil) }
        NativeJSUI.presentHook = nil
        check("refs: picker title and rows", (picked?.1 ?? 0) >= 3 && picked?.0.hasPrefix("Usages of VALUE") == true)
    }
}
