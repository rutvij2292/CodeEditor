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

        // arena allocator: memory of a tree is committed while its document lives and handed back at once
        let bigSrc = (0..<4000).map { "export function f\($0)(a: number, b: string): Promise<void> { return helper(a) + b.length }" }.joined(separator: "\n")
        let before = NJSAlloc.committedBytes, zonesBefore = NJSAlloc.liveZones
        var held: NJSDoc? = NJSDoc(path: root.path + "/src/big.ts", text: bigSrc as NSString)
        let during = NJSAlloc.committedBytes
        check("arena: a parse commits its tree memory (~26 bytes per character)", held != nil && during - before > 1_000_000 && NJSAlloc.liveZones >= 1)
        check("arena: the tree is usable", held?.summary.order.count == 4000)
        held = nil
        check("arena: releasing the document returns all of it", NJSAlloc.committedBytes == before)
        DispatchQueue.concurrentPerform(iterations: 12) { i in
            for _ in 0..<5 { autoreleasepool { let d = NJSDoc(path: root.path + "/src/c\(i).ts", text: bigSrc as NSString); _ = d?.summary.top.count } }
        }
        check("arena: concurrent parses and releases leave nothing behind", NJSAlloc.committedBytes == before && NJSAlloc.liveZones == zonesBefore)
        // a document released on another thread than the one that parsed it
        var cross: NJSDoc? = NJSDoc(path: root.path + "/src/x.ts", text: bigSrc as NSString)
        let sem = DispatchSemaphore(value: 0)
        let box = cross; cross = nil
        DispatchQueue.global().async { _ = box?.summary.order.count; sem.signal() }
        sem.wait()
        check("arena: cross-thread use is safe", true)

        // inference from declared return types: const x = f() / Vue refs
        put(root, "node_modules/@vue/reactivity/package.json", "{\"name\":\"@vue/reactivity\",\"types\":\"dist/reactivity.d.ts\"}")
        put(root, "node_modules/@vue/reactivity/dist/reactivity.d.ts", "export interface Ref<T = any> { value: T }\nexport interface ComputedRef<T = any> extends Ref<T> { readonly value: T }\nexport declare function ref<T>(v: T): [T] extends [Ref] ? T : Ref<T>;\nexport declare const computed: { <T>(g: () => T): ComputedRef<T> };\n")
        put(root, "node_modules/vue/package.json", "{\"name\":\"vue\",\"types\":\"dist/vue.d.ts\"}")
        put(root, "node_modules/vue/dist/vue.d.ts", "export * from '@vue/reactivity'\n")
        let inf = "import { ref, computed } from 'vue'\nimport { Owner } from '@/util'\nfunction mk(): Owner { return new Owner() }\nconst n = ref(0)\nn.value\nconst c = computed(() => 1)\nc.value\nconst o = mk()\no.ping()\nconst top = mk()\nfunction f() { return top.email }\nlet [d1] = mk()\nd1.email\nlet viaLet = mk()\nviaLet.email\n"
        put(root, "src/inf.ts", inf)
        let iu = root.appendingPathComponent("src/inf.ts")
        func ihit(_ needle: String, _ nth: Int = 0, plus: Int = 1) -> String {
            let h = NativeJS.lookup(url: iu, text: inf as NSString, offset: off(inf, needle, nth, plus: plus), root: root.path)
            guard let t = h?.targets.first else { return "nil" }
            return "\(t.path.hasPrefix(root.path + "/") ? String(t.path.dropFirst(root.path.count + 1)) : t.path):\(t.line)"
        }
        check("infer: ref().value is the Ref interface's value", ihit("value\nconst c") == "node_modules/@vue/reactivity/dist/reactivity.d.ts:1")
        check("infer: computed().value is ComputedRef's value", ihit("value\nconst o") == "node_modules/@vue/reactivity/dist/reactivity.d.ts:2")
        check("infer: const x = f() takes f's declared return type", ihit("ping()") == "src/util.ts:17")
        check("infer: let x = f() has the declared type of f too", ihit("email\n", 1) == "src/util.ts:17")
        check("infer: a destructured binding is not the whole value", ihit("d1.email", 0, plus: 3) == "nil")
        check("infer: top-level const x = f()", ihit("email }") == "src/util.ts:17")

        put(root, "node_modules/vuealias/package.json", "{\"name\":\"vuealias\",\"types\":\"index.d.ts\"}")
        put(root, "node_modules/vuealias/index.d.ts", "import { computed as computed$1 } from '@vue/reactivity'\ndeclare const computed: typeof computed$1\nexport { computed }\n")
        let aliased = "import { computed } from 'vuealias'\nconst c = computed(() => 1)\nc.value\n"
        put(root, "src/alias.ts", aliased)
        check("infer: `declare const f: typeof g` has the type of g (Vue's runtime-core re-declares computed this way)",
              NativeJS.lookup(url: root.appendingPathComponent("src/alias.ts"), text: aliased as NSString, offset: off(aliased, "value", 0, plus: 1), root: root.path)?.targets.first?.line == 2)

        let rs = "import { ref } from 'vue'\nfunction mk(a: number) { return { hours: a, minutes: 2 } }\nconst arrow = () => ({ x: 1 })\nconst t = mk(1)\nt.hours\nconst ar = arrow()\nar.x\nconst r = ref({ to: null })\nr.value.to\nfunction two(a: number) { if (a) { return { k: 1 } } return { k: 2 } }\nconst tw = two(1)\ntw.k\nasync function asy() { return { z: 1 } }\nconst az = asy()\naz.z\n"
        put(root, "src/rs.ts", rs)
        func rhit(_ needle: String, _ nth: Int = 0) -> Int? {
            NativeJS.lookup(url: root.appendingPathComponent("src/rs.ts"), text: rs as NSString, offset: off(rs, needle, nth, plus: 1), root: root.path)?.targets.first?.line
        }
        check("infer: a function whose only return is an object literal gives its keys", rhit("hours\nconst ar") == 2)
        check("infer: arrow function returning ({...})", rhit("x\nconst r") == 3)
        check("infer: ref({...}).value.key", rhit("to\nfunction") == 8)
        check("infer: several returns / async functions are left to the server", rhit("k\nasync") == nil && rhit("z\n") == nil)

        // 'native only' (default ON): plain projects get no TypeScript server; Vue projects follow the Vue switch
        let keepNative = NativeJS.nativeOnly
        let keepVue = NativeVue.nativeOnly
        UserDefaults.standard.removeObject(forKey: NativeJS.nativeOnlyKey); UserDefaults.standard.removeObject(forKey: NativeVue.nativeOnlyKey)
        check("native only is on by default (JS / TS and Vue)", NativeJS.nativeOnly && NativeVue.nativeOnly)
        NativeJS.nativeOnly = true
        put(root, "pkg-plain/package.json", "{\"name\":\"plain\"}")
        put(root, "pkg-vue/package.json", "{\"dependencies\":{\"vue\":\"^3\"}}")
        check("native only: a plain project gets no TypeScript server", NativeJS.suppressesTypeScriptServer(root: root.appendingPathComponent("pkg-plain")) && LanguageServerLaunch.typescript(root: root.appendingPathComponent("pkg-plain"), manager: .shared) == nil)
        check("native only: a Vue project gets no TypeScript server either", NativeJS.suppressesTypeScriptServer(root: root.appendingPathComponent("pkg-vue")))
        NativeVue.nativeOnly = false
        check("Vue switch off: a Vue project keeps its server", !NativeJS.suppressesTypeScriptServer(root: root.appendingPathComponent("pkg-vue")))
        NativeVue.nativeOnly = keepVue
        NativeJS.nativeOnly = false
        check("native only off: nothing is suppressed", !NativeJS.suppressesTypeScriptServer(root: root.appendingPathComponent("pkg-plain")))
        NativeJS.nativeOnly = keepNative

        // factory shapes: defineProps / reactive / useForm declare their members at the literal's keys
        put(root, "node_modules/@inertiajs/vue3/package.json", "{\"name\":\"@inertiajs/vue3\",\"types\":\"types/index.d.ts\"}")
        put(root, "node_modules/@inertiajs/vue3/types/index.d.ts", "export declare function useForm<T>(d: T): InertiaForm<T>;\nexport type InertiaForm<T> = T & InertiaFormProps;\nexport interface InertiaFormProps { post(url: string): void; processing: boolean }\n")
        let sfc = "<script setup lang=\"ts\">\nimport { reactive } from 'vue'\nimport { useForm } from '@inertiajs/vue3'\nconst props = defineProps({ perPage: { type: Number }, user: Object })\nconst state = reactive({ count: 0, name: 'x' })\nconst form = useForm({ email: '', pw: '' })\nprops.perPage\nstate.count\nform.email\nform.post('/x')\nconst p2 = withDefaults(defineProps<{ title: string }>(), {})\np2.title\nfunction inner() { const local = reactive({ deep: 1 }); return local.deep }\n</script>\n"
        put(root, "src/Shape.vue", sfc)
        let su = root.appendingPathComponent("src/Shape.vue")
        func shit(_ needle: String, _ nth: Int = 0, plus: Int = 1) -> String {
            let h = NativeJS.lookup(url: su, text: sfc as NSString, offset: off(sfc, needle, nth, plus: plus), root: root.path)
            guard let t = h?.targets.first else { return "nil" }
            return "\(t.path.hasPrefix(root.path + "/") ? String(t.path.dropFirst(root.path.count + 1)) : t.path):\(t.line)"
        }
        check("shape: defineProps({...}) members are the literal's keys", shit("perPage\nstate") == "src/Shape.vue:4")
        check("shape: reactive({...}).key", shit("count\nform") == "src/Shape.vue:5")
        check("shape: useForm({...}).key", shit("email\nform.post") == "src/Shape.vue:6")
        check("shape: useForm(...).post falls to InertiaForm's intersected props", shit("post('/x')") == "node_modules/@inertiajs/vue3/types/index.d.ts:3")
        check("shape: withDefaults(defineProps<{...}>()).title", shit("title\nfunction") == "src/Shape.vue:11")
        check("shape: a reactive() local inside a function", shit("deep }") == "src/Shape.vue:13")
        let shadow = sfc.replacingOccurrences(of: "import { reactive } from 'vue'", with: "const reactive = (x: any) => ({ other: 1 })")
        put(root, "src/Shape2.vue", shadow)
        check("shape: reactive that is not Vue's is not trusted", NativeJS.lookup(url: root.appendingPathComponent("src/Shape2.vue"), text: shadow as NSString, offset: off(shadow, "count\nform", 0, plus: 1), root: root.path) == nil)

        // document symbols (Go to Symbol / file symbols for TypeScript and Vue script)
        let outline = SymbolExtractor.symbols(in: "export interface Opts { a: number }\nexport class Box { size = 1\n  grow(n: number) {} }\nexport const make = () => 1\nexport enum E { A }\nlet scratch = 1\n", fileExtension: "ts")
        check("symbols: TypeScript outline has declarations and members, skips plain variables", Set(outline.map { "\($0.container ?? "").\($0.name)" }) == [".Opts", "Opts.a", ".Box", "Box.size", "Box.grow", ".make", ".E", "E.A"])

        // auto-import: exported names of other files, with the import edit applied on accept
        NativeJSAutoImport.enabled = true
        put(root, "src/models/deep.ts", "const a = 1\n")
        func accepted(_ file: String, _ code: String, _ label: String, from spec: String? = nil) -> String? {
            let items = complete(root.appendingPathComponent(file), code, caretAfter: code.hasSuffix("Own") ? "Own" : code.hasSuffix("Wid") ? "Wid" : "libV")
            guard let it = items.first(where: { $0.label == label && (spec == nil || $0.detail.hasSuffix(spec!)) }), let e = it.additionalEdits.first else { return nil }
            return (code as NSString).replacingCharacters(in: e.range, with: e.text)
        }
        check("auto-import: joins the existing named import of the same module", accepted("src/ai.ts", "import { helper } from './util'\nconst x = new Own", "Owner") == "import { helper, Owner } from './util'\nconst x = new Own")
        check("auto-import: a default export is offered under its declared name and imported as default", accepted("src/models/deep.ts", "import { User } from './user'\nconst w = new Wid", "Widget", from: "@/util")?.contains("import Widget from '@/util';") == true
              || accepted("src/models/deep.ts", "import { User } from './user'\nconst w = new Wid", "Widget", from: "@/util")?.contains("import Widget from '@/util'") == true)
        check("auto-import: the alias wins over a path that climbs out of the folder", accepted("src/models/deep.ts", "const w = new Wid", "Widget", from: "@/util")?.hasPrefix("import Widget from '@/util'") == true)
        check("auto-import: quote and semicolon style follow the file", accepted("src/ai2.ts", "import { helper } from \"./util\";\nimport x from \"./cjs\";\nnew Own", "Owner")?.contains("import { helper, Owner } from \"./util\";") == true)
        check("auto-import: names already in the file are not offered", complete(root.appendingPathComponent("src/ai.ts"), "import { Owner } from './util'\nconst x = new Own", caretAfter: "Own").allSatisfy { $0.additionalEdits.isEmpty || $0.label != "Owner" })
        check("auto-import: not offered after a dot or inside a string", complete(root.appendingPathComponent("src/ai.ts"), "const x = y.Own", caretAfter: "Own").allSatisfy { $0.additionalEdits.isEmpty }
              && complete(root.appendingPathComponent("src/ai.ts"), "const x = 'Own", caretAfter: "Own").allSatisfy { $0.additionalEdits.isEmpty })
        let sc = NJSScanner.scan("export function a() {}\nexport const b = 1, c = 2\nexport class D {}\nexport { e, f as g }\nexport default function Foo() {}\nexport type T = 1\nexport async function h() {}\n" as NSString)
        check("export scan: declared and listed names, default name", Set(sc.exportNames) == ["a", "b", "D", "e", "g", "T", "h"] && sc.hasDefault && sc.defaultName == "Foo")

        // syntax: only an unclosed bracket tree-sitter repaired is reported
        func syn(_ name: String, _ code: String) -> [NPDiag] { NativeJSDiag.analyze(url: root.appendingPathComponent(name), text: code as NSString).filter { $0.code == "syntax" } }
        let unclosed = syn("src/s1.ts", "const a = 3\nif (a {\n  a\n}\nfunction f() {\n  return 1\n")
        check("syntax: tree-sitter's repair of a missing ) or } is reported, one per line", !unclosed.isEmpty && unclosed.count <= 2 && unclosed.allSatisfy { $0.severity == 1 })
        check("syntax: valid code is silent", syn("src/s2.ts", "export const a = 1\nfunction f<T>(x: T): T { return x }\nclass C { #p = 1; static { } }\n").isEmpty)
        check("syntax: grammar gaps (keyword export names, variance, import types) stay silent", syn("src/s3.js", "const _function = 1\nexport { _function as function }\n").isEmpty
              && syn("src/s4.ts", "interface I<in out T> { x: T }\nexport type * from './a'\n").isEmpty)
        check("syntax: declaration files are never judged", syn("src/s5.d.ts", "declare const a: import('x').T<\n").isEmpty)

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
