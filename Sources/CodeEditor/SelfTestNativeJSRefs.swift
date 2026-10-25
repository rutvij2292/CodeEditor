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
            fputs("REFS helper: \(sm)\n", stderr)
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
            fputs("REFS name: \(sm)\n", stderr)
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
            fputs("REFS Widget: \(sm)\n", stderr)
            check("refs: class from its declaration (default import with another name)", sm.contains("src/util.ts:9:declaration") && sm.contains("src/other.ts:2:import") && sm.contains("src/other.ts:4:usage") && sm.contains("src/main.ts:14:usage"))
        } else { check("refs: class identified from declaration", false) }
        check("refs: unknown / global tokens are not native", usages(in: mainURL, text: main, "console") == nil)

        var picked: (String, Int)?
        NativeJSUI.presentHook = { t, items in picked = (t, items.count) }
        if let (r, s) = usages(in: mainURL, text: main, "VALUE as V") { NativeJSUI.present(s, result: r, window: nil) }
        NativeJSUI.presentHook = nil
        check("refs: picker title and rows", (picked?.1 ?? 0) >= 3 && picked?.0.hasPrefix("Usages of VALUE") == true)
    }
}
