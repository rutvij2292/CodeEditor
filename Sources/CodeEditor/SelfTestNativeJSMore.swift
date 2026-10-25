import Foundation

extension SelfTestNativeJS {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    private static func complete(_ url: URL, _ text: String, caretAfter needle: String, nth: Int = 0, typed: Int = 0) -> [CompletionItem] {
        let ns = text as NSString
        let caret = off(text, needle, nth) + (needle as NSString).length
        var s = caret
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        let ctx = CompletionContext(text: text, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil, isManual: true,
                                    prefixRange: NSRange(location: s, length: caret - s))
        var out: [CompletionItem] = []
        let sem = DispatchSemaphore(value: 0)
        let p = NativeJSCompletionProvider()
        p.complete(ctx) { items, _ in out = items; sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
        return out
    }

    /// Provably correct completion and diagnostics.
    static func runExtras() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njsx-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        buildFixture(root)
        put(root, "src/main.ts", main)
        let url = root.appendingPathComponent("src/main.ts")

        // diagnostics
        let diags = NativeJSDiag.analyze(url: url, text: main as NSString)
        let notFound = diags.filter { $0.code == "module-not-found" }.map { (main as NSString).substring(with: $0.range) }
        check("diag: only the missing relative module is reported", notFound == ["./nope"])
        check("diag: missing module in a TS file is an error", diags.first { $0.code == "module-not-found" }?.severity == 1)
        let unused = Set(diags.filter { $0.code == "unused-import" }.map { (main as NSString).substring(with: $0.range) })
        check("diag: unused imports are hints and used ones are not reported", unused.isSuperset(of: ["Profile", "missing", "Options", "data", "Comp"]) && !unused.contains("helper") && !unused.contains("Widget") && !unused.contains("User") && !unused.contains("V") && !unused.contains("Id"))
        let jsSrc = "import React from 'react'\nimport Card from './Card'\nimport { Small } from './Card'\nimport lonely from './Card'\n// lonely is mentioned in a comment\nexport const A = () => <Card/>\n"
        put(root, "src/a.jsx", jsSrc)
        let jd = NativeJSDiag.analyze(url: root.appendingPathComponent("src/a.jsx"), text: jsSrc as NSString)
        let junused = Set(jd.filter { $0.code == "unused-import" }.map { (jsSrc as NSString).substring(with: $0.range) })
        check("diag: React in a JSX file, comment mentions and used bindings are never flagged; truly unused is", junused == ["Small"])
        let jsMissing = "import x from './gone'\nx\n"
        check("diag: missing module in a JS file is a warning", NativeJSDiag.analyze(url: root.appendingPathComponent("src/b.js"), text: jsMissing as NSString).first?.severity == 2)
        put(root, "src/svelte/tsconfig.json", "{\"compilerOptions\":{\"rootDirs\":[\".\",\"./.types\"]}}")
        let virt = "import type { T } from './$types'\nlet a: T\n"
        check("diag: rootDirs projects (virtual directories) are not judged", NativeJSDiag.analyze(url: root.appendingPathComponent("src/svelte/p.ts"), text: virt as NSString).filter { $0.code == "module-not-found" }.isEmpty)
        check("diag: query suffix and non-relative specifiers are skipped", NativeJSDiag.analyze(url: root.appendingPathComponent("src/c.ts"), text: "import i from './x.svg?react'\nimport k from 'nonexistent-pkg'\ni; k\n" as NSString).isEmpty)

        // completion: specifiers
        let spec = "import a from './models/"
        let t1 = complete(root.appendingPathComponent("src/x.ts"), spec, caretAfter: "./models/")
        check("complete: relative directory listing (extension-less files)", Set(t1.map(\.label)).isSuperset(of: ["user", "index"]) && !t1.contains { $0.label.hasSuffix(".ts") })
        let t2 = complete(root.appendingPathComponent("src/x.ts"), "import a from '@/", caretAfter: "'@/")
        check("complete: tsconfig paths alias lists the mapped directory", Set(t2.map(\.label)).isSuperset(of: ["util", "models/", "cjs"]))
        let t3 = complete(root.appendingPathComponent("src/x.ts"), "const p = require('p", caretAfter: "require('p")
        check("complete: package names from node_modules (and the replace range is the typed segment)", t3.contains { $0.label == "pkg" } && t3.first?.replaceRange?.length == 1)
        // names in braces
        let named = "import { h, } from '@/util'\n"
        let n1 = complete(root.appendingPathComponent("src/x.ts"), named, caretAfter: "{ h")
        let nl = Set(n1.map(\.label))
        check("complete: exports of the module inside import braces", nl.isSuperset(of: ["helper", "VALUE", "LIMIT", "Base", "Owner", "Id", "Color"]) && !nl.contains("name"))
        let n2 = complete(root.appendingPathComponent("src/x.ts"), "import { } from 'chunky'\n", caretAfter: "{ ")
        check("complete: `export =` namespace members are the module's exports", Set(n2.map(\.label)).isSuperset(of: ["chunk", "Options", "Thing"]))
        let n3 = complete(root.appendingPathComponent("src/x.ts"), "import { } from './models'\n", caretAfter: "{ ")
        check("complete: export * and re-exports are followed", Set(n3.map(\.label)).isSuperset(of: ["User", "Profile", "Widget", "help"]))
        // members
        let head = "import Widget from '@/util'\nconst w = new Widget()\n"
        func src(_ tail: String) -> (URL, String) { let t = head + tail + "\n"; put(root, "src/m.ts", t); return (root.appendingPathComponent("src/m.ts"), t) }
        let (mu, s1) = src("w.")
        let inst = Set(complete(mu, s1, caretAfter: "\nw.").map(\.label))
        check("complete: instance members incl. inherited, no statics", inst.isSuperset(of: ["name", "owner", "run", "title", "baseMethod", "base2"]) && !inst.contains("make"))
        let (_, s2) = src("Widget.")
        let stat = Set(complete(mu, s2, caretAfter: "\nWidget.").map(\.label))
        check("complete: static members only", stat.contains("make") && !stat.contains("name"))
        let (_, s3) = src("class K extends Widget { go() { this. } }")
        let thisM = Set(complete(mu, s3, caretAfter: "this.").map(\.label))
        check("complete: this. inside a subclass", thisM.isSuperset(of: ["name", "run", "baseMethod"]) && !thisM.contains("make"))
        check("complete: unknown receiver contributes nothing", complete(mu, "function f(x) { x. }\n", caretAfter: "x.").isEmpty)
        check("complete: not inside strings elsewhere", complete(mu, "const s = 'hello w", caretAfter: "hello w").isEmpty)
    }
}
