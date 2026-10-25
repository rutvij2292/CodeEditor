import Foundation

/// CE_SELFTEST: the native engine registry (NativeEngines.swift): ordering, fall-through, suppression, reset, fan-out, settings order.
enum SelfTestNativeEngines {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("engine registry: " + name, ok()) }

    /// A scripted engine: answers (or declines) with a canned hit and records every call.
    private final class Fake: NativeEngine {
        let id: String
        let displayName: String
        let priority: Int
        let completionRank: Int
        let emptyHoverIsAnswer: Bool
        var exts: Set<String>
        var answer: NPHit?
        var suppressed: Set<String> = []
        var log: Log
        init(_ id: String, priority: Int, rank: Int = 0, exts: Set<String> = ["x"], answer: NPHit? = nil, emptyOK: Bool = false, log: Log) {
            self.id = id; displayName = id; self.priority = priority; completionRank = rank; self.exts = exts
            self.answer = answer; emptyHoverIsAnswer = emptyOK; self.log = log
        }
        func handles(_ url: URL) -> Bool { exts.contains(url.pathExtension) }
        func lookup(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) { log.events.append("lookup:" + id); completion(answer) }
        func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool { false }
        func registerCompletion() { log.events.append("register:" + id) }
        func invalidate(root: URL) { log.events.append("invalidate:" + id) }
        func trimMemory() { log.events.append("trim:" + id) }
        func resetPrefs() { log.events.append("reset:" + id) }
        func suppressesServer(_ sid: String, root: URL?) -> Bool { suppressed.contains(sid) }
    }

    private final class Log { var events: [String] = [] }

    private static func hit(_ md: String) -> NPHit { NPHit(range: NSRange(location: 0, length: 1), targets: [], markdown: md, kind: "t") }

    private static func chain(_ url: URL, _ accept: @escaping (NPHit, NativeEngine) -> Bool = { h, e in !h.markdown.isEmpty || e.emptyHoverIsAnswer }) -> (NPHit?, String?) {
        var out: (NPHit?, String?) = (nil, "unset")
        NativeEngines.lookup(url: url, text: "abc", offset: 0, accept: accept) { h, e in out = (h, e?.id) }
        return out
    }

    static func run() {
        let vue = URL(fileURLWithPath: "/p/a.vue"), x = URL(fileURLWithPath: "/p/a.x")

        // The real list: ids in list order, lookup order per file type (the hand-written chains this replaced).
        func ids(_ path: String) -> [String] { NativeEngines.engines(for: URL(fileURLWithPath: path)).map(\.id) }
        check("list order is php, python, web, js, vue", NativeEngines.all.map(\.id) == ["php", "python", "web", "js", "vue"])
        check(".vue falls through vue, js, web", ids("/p/a.vue") == ["vue", "js", "web"])
        check(".ts asks js then web (Tailwind class strings)", ids("/p/a.ts") == ["js", "web"])
        check("blade asks php then web", ids("/p/a.blade.php") == ["php", "web"])
        check("plain php, python, css, html, unknown", ids("/p/a.php") == ["php"] && ids("/p/a.py") == ["python"] && ids("/p/a.css") == ["web"]
              && ids("/p/a.html") == ["web"] && ids("/p/a.txt").isEmpty)
        check("session UI is needed for python only", NativeEngines.needsSessionUI(URL(fileURLWithPath: "/p/a.py")) && !NativeEngines.needsSessionUI(URL(fileURLWithPath: "/p/a.php")))
        check("signature help: php and js only", NativeEngines.signatureEngine(for: URL(fileURLWithPath: "/p/a.php"))?.id == "php"
              && NativeEngines.signatureEngine(for: URL(fileURLWithPath: "/p/a.tsx"))?.id == "js"
              && NativeEngines.signatureEngine(for: URL(fileURLWithPath: "/p/a.py")) == nil && NativeEngines.signatureEngine(for: vue)?.id == "js")

        // Ordering by priority, ties by list order, independent of list position.
        let log = Log()
        NativeEngines.withEngines([Fake("c", priority: 30, log: log), Fake("a", priority: 10, log: log), Fake("b", priority: 10, log: log)]) {
            check("priority then list order", NativeEngines.engines(for: x).map(\.id) == ["a", "b", "c"])
            check("settings / fan-out keep list order", NativeEngines.all.map(\.id) == ["c", "a", "b"])
        }
        check("withEngines restores the real list", NativeEngines.all.count == 5)

        // Fall-through: the .vue case (vue declines -> js declines -> web answers), then everything declines.
        let l2 = Log()
        let v = Fake("vue", priority: 10, exts: ["vue"], log: l2), j = Fake("js", priority: 20, exts: ["vue"], log: l2), w = Fake("web", priority: 40, exts: ["vue"], answer: hit("web"), log: l2)
        NativeEngines.withEngines([w, j, v]) {
            let r = chain(vue)
            check("vue case: web answers after vue and js decline", r.1 == "web" && r.0?.markdown == "web" && l2.events == ["lookup:vue", "lookup:js", "lookup:web"])
            l2.events = []; j.answer = hit("js")
            let r2 = chain(vue)
            check("first answer wins, later engines are not asked", r2.1 == "js" && l2.events == ["lookup:vue", "lookup:js"])
            l2.events = []; v.answer = hit("")
            check("empty markdown declines unless the engine counts it", chain(vue).1 == "js")
            v.answer = nil; j.answer = nil; w.answer = nil; l2.events = []
            let r3 = chain(vue)
            check("all decline: (nil, nil) so the server is asked", r3.0 == nil && r3.1 == nil && l2.events.count == 3)
            check("no engine handles the file: immediate (nil, nil)", chain(URL(fileURLWithPath: "/p/a.zzz")).1 == nil)
        }
        let l3 = Log()
        NativeEngines.withEngines([Fake("py", priority: 30, answer: hit(""), emptyOK: true, log: l3), Fake("web", priority: 40, answer: hit("web"), log: l3)]) {
            check("emptyHoverIsAnswer: an empty hit still answers", chain(x).1 == "py")
        }
        var stale = false
        let l4 = Log()
        NativeEngines.withEngines([Fake("a", priority: 1, log: l4), Fake("b", priority: 2, answer: hit("b"), log: l4)]) {
            NativeEngines.lookup(url: x, text: "abc", offset: 0, stale: { stale = true; return true }, accept: { _, _ in true }) { _, _ in l4.events.append("done") }
            check("a stale request stops the chain", stale && l4.events == ["lookup:a"])
        }

        // Suppression (what LanguageServerPrefs.isEnabled asks).
        let l5 = Log(), sup = Fake("s", priority: 1, log: l5)
        sup.suppressed = ["fakeserver"]
        check("server enabled without a suppressing engine", LanguageServerPrefs.isEnabled("fakeserver"))
        NativeEngines.withEngines([sup]) {
            check("a suppressing engine stops its server", !LanguageServerPrefs.isEnabled("fakeserver") && LanguageServerPrefs.isEnabled("other"))
        }
        check("typescript is only suppressed per root", !NativeEngines.suppressesServer("typescript"))
        check("builtin completion topics follow the web engine", NativeEngines.suppressesBuiltinCompletion(.css, for: URL(fileURLWithPath: "/p/a.css")) == NativeWeb.handles(URL(fileURLWithPath: "/p/a.css")))

        // Fan-out and completion registration order.
        let l6 = Log()
        NativeEngines.withEngines([Fake("php", priority: 30, rank: 100, log: l6), Fake("py", priority: 30, log: l6), Fake("web", priority: 40, log: l6)]) {
            NativeEngines.registerCompletions()
            check("completion registers in rank order, php last", l6.events == ["register:py", "register:web", "register:php"])
            l6.events = []
            NativeEngines.invalidate(root: URL(fileURLWithPath: "/p")); NativeEngines.trimMemory(); NativeEngines.resetPrefs()
            check("invalidate, trim and reset reach every engine", l6.events.count == 9 && Set(l6.events).count == 9)
            NativeEngines.register(Fake("py", priority: 5, log: l6))
            check("register replaces an engine with the same id", NativeEngines.all.map(\.id) == ["php", "web", "py"] && NativeEngines.engines(for: x).first?.id == "py")
        }

        // Reset: every real engine's preferences go back to their defaults.
        let d = UserDefaults.standard
        let keys = [NativePHP.nativeOnlyKey, NativePy.enabledKey, NativeWeb.enabledKey, NativeWeb.nativeOnlyKey, NativeWeb.tailwindEnabledKey,
                    NativeWeb.tailwindNativeOnlyKey, NativeJS.enabledKey, NativeJS.nativeOnlyKey, NativeJSDiag.syntaxKey, NativeJSAutoImport.key,
                    NativeJSDiag.enabledKey, NativeVue.enabledKey, NativeVue.nativeOnlyKey, NativePHPDiag.classSeverityKey]
        let saved = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        // every key set to the OPPOSITE of its default, so a reset that misses one is caught
        for k in keys { d.set(k == NativePHPDiag.classSeverityKey ? 1 : (k == NativePy.enabledKey), forKey: k) }
        NativeEngines.resetPrefs()
        check("reset removes every engine key", keys.allSatisfy { d.object(forKey: $0) == nil })
        check("reset restores the defaults", !NativePy.enabled && NativeJS.enabled && NativeVue.enabled && NativeJS.nativeOnly && NativeVue.nativeOnly
              && NativePHP.nativeOnly && NativeWeb.enabled && NativeWeb.nativeOnly && NativeJSDiag.enabled && NativePHPDiag.classSeverity == 2)

        // Settings rows: same sections, labels and order as the hand-written pane.
        var seq: [String] = []
        for s in NativeEngines.settingsSections {
            if let t = s.title { seq.append("# " + t) }
            for i in s.items {
                switch i { case .toggle(let t): seq.append(t.title); case .choice(let c): seq.append("? " + c.label) }
            }
        }
        let expected = ["# PHP", "Use native PHP engine only (stop Intelephense)", "# PHP diagnostics"]
            + NPDiagGroup.allCases.map(\.title) + ["? Undefined class severity", "# Python", "Use native Python engine"]
            + PyDiagGroup.allCases.map { "Python: " + $0.title }
            + ["# HTML / CSS", "Native HTML and CSS services", "Use native HTML / CSS only (stop the external servers)",
               "# Tailwind CSS", "Native Tailwind engine", "Use native Tailwind only (stop the Tailwind server)",
               "# JavaScript / TypeScript", "Native JavaScript / TypeScript engine", "Do not start the TypeScript server (native JS / TS only)",
               "Native JS / TS diagnostics (missing relative imports, unused imports)", "Report unclosed brackets (syntax)",
               "Report unknown names and wrong argument counts (TypeScript)", "Auto-import suggestions while typing", "Native Vue template service",
               "Do not start Volar / the TypeScript server for Vue projects"]
        check("settings rows keep their labels and order", seq == expected)
        if seq != expected { print("  settings rows were: \(seq)") }
        check("every toggle reads its preference", NativeEngines.settingsSections.flatMap(\.items).allSatisfy {
            if case .toggle(let t) = $0 { _ = t.get(); return !t.accessibility.isEmpty }
            return true
        })
    }
}
