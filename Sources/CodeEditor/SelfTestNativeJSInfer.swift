import Foundation

/// Phase 3: the type evaluator (inferred hover, definition on inferred receivers, member completion).
/// Test snippets mark the token under test with a leading `§`.
extension SelfTestNativeJS {
    static func runInfer() {
        guard let bundled = NJSLib.bundledDirectory() else { SelfTest.check("infer: bundled TsLib/ directory found", false); return }
        NJSLib.directoryOverride = bundled
        defer { NJSLib.directoryOverride = nil; NJSLib.trim() }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njsinfer-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        put(root, "package.json", "{}")
        func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }
        let show = AppEnv.value("CE_NJS_SHOW") != nil
        var n = 0
        var lastFile = ""
        func hit(_ marked: String) -> NPHit? {
            n += 1
            lastFile = "t\(n).ts"
            let at = (marked as NSString).range(of: "§").location
            let code = marked.replacingOccurrences(of: "§", with: "")
            return NativeJS.lookup(url: root.appendingPathComponent(lastFile), text: code as NSString, offset: at + 1, root: root.path)
        }
        func hover(_ code: String) -> String {
            let md = hit(code)?.markdown ?? ""
            if show { fputs("HOVER \(code.replacingOccurrences(of: "\n", with: "|")) -> \(md.replacingOccurrences(of: "\n", with: "|"))\n", stderr) }
            let lines = md.components(separatedBy: "\n")
            guard lines.count > 1, let close = lines.dropFirst().firstIndex(of: "```") else { return "" }
            return lines[1..<close].joined(separator: "\n")
        }
        func target(_ code: String) -> [String] {
            let r = (hit(code)?.targets ?? []).map { (($0.path as NSString).lastPathComponent) + ":\($0.line)" }
            if show { fputs("TARGET \(code.replacingOccurrences(of: "\n", with: "|")) -> \(r)\n", stderr) }
            return r
        }
        func lib(_ code: String) -> Bool { target(code).first?.hasPrefix("lib.") == true }

        // hover shows the inferred type
        check("infer: const literal", hover("const §a = 1") == "const a: 1")
        check("infer: let widens", hover("let §a = 1") == "let a: number")
        check("infer: string array", hover("const §xs = ['a', 'b']") == "const xs: string[]")
        check("infer: object literal prints one member per line like the server", hover("const §o = { a: 1, b: 'x' }") == "const o: {\n    a: number;\n    b: string;\n}")
        check("infer: function return", hover("function f(x: number) { return x + 1 }\nconst §r = f(2)") == "const r: number")
        check("infer: await", hover("async function g() { return 'x' }\nasync function h() { const §v = await g() }") == "const v: string")
        check("infer: generic identity keeps the literal", hover("function id<T>(x: T): T { return x }\nconst §r = id(5)") == "const r: 5")
        check("infer: generic container widens", hover("function box<T>(x: T): T[] { return [x] }\nconst §r = box(5)") == "const r: number[]")
        check("infer: array map callback", hover("const §r = [1, 2].map(x => String(x))") == "const r: string[]")
        check("infer: new Map", hover("const §m = new Map<string, number>()") == "const m: Map<string, number>")
        check("infer: class instance", hover("class A { n = 1 }\nconst §a = new A()") == "const a: A")
        check("infer: destructuring", hover("const { a, b } = { a: 1, b: 'x' }\n§b") == "const b: string")
        check("infer: array destructuring", hover("const [§p, q] = [1, 2]") == "const p: number")
        check("infer: for-of element", hover("for (const §s of ['a']) { s }") == "const s: string")
        check("infer: parameter typed by the callback context", hover("['a'].forEach(§s => s)") == "(parameter) s: string")
        check("infer: ternary union", hover("const c = Math.random() > 0.5\nconst §t = c ? 1 : 'x'") == "const t: 1 | \"x\"")
        check("infer: unresolved stays silent (declared text only)", !hover("const §q = mystery()").contains("unknown"))

        put(root, "node_modules/@vue/reactivity/package.json", "{\"name\":\"@vue/reactivity\",\"types\":\"dist/reactivity.d.ts\"}")
        put(root, "node_modules/@vue/reactivity/dist/reactivity.d.ts", """
        export type IfAny<T, Y, N> = 0 extends (1 & T) ? Y : N;
        export interface Ref<T = any, S = T> { get value(): T; set value(_: S) }
        export interface ComputedRef<T = any> extends Ref<T> { readonly value: T }
        export type UnwrapRef<T> = T extends ShallowRef<infer V, unknown> ? V : T extends Ref<infer V, unknown> ? UnwrapRefSimple<V> : UnwrapRefSimple<T>;
        export type UnwrapRefSimple<T> = T;
        export interface ShallowRef<T = any, S = T> extends Ref<T, S> {}
        export declare function ref<T>(value: T): [T] extends [Ref] ? IfAny<T, Ref<T>, T> : Ref<UnwrapRef<T>, UnwrapRef<T> | T>;
        export declare function ref<T = any>(): Ref<T | undefined>;
        export declare function computed<T>(getter: () => T): ComputedRef<T>;
        """)
        put(root, "node_modules/vue/package.json", "{\"name\":\"vue\",\"types\":\"dist/vue.d.ts\"}")
        put(root, "node_modules/vue/dist/vue.d.ts", "export * from '@vue/reactivity'\n")
        check("infer: ref(0)", hover("import { ref } from 'vue'\nconst §n = ref(0)") == "const n: Ref<number, number>")
        check("infer: ref().value", target("import { ref } from 'vue'\nconst n = ref(0)\nn.§value").first?.contains("reactivity.d.ts") == true)
        check("infer: ref of an array: .value members", lib("import { ref } from 'vue'\nconst xs = ref([1, 2])\nxs.value.§map(x => x)"))
        check("infer: computed().value", hover("import { computed } from 'vue'\nconst c = computed(() => 'a')\nconst §d = c.value") == "const d: string")
        check("infer: ref() without value", hover("import { ref } from 'vue'\nconst §e = ref()") == "const e: Ref<any, any>" || hover("import { ref } from 'vue'\nconst §e = ref()").hasPrefix("const e: Ref<"))

        // DOM and callbacks
        check("infer: getElementById result", lib("const el = document.getElementById('a')\nel?.§classList"))
        check("infer: querySelector with a selector string is an Element", hover("const §q = document.querySelector('.x')") == "const q: Element | null")
        check("infer: addEventListener callback event", lib("window.addEventListener('click', e => e.§preventDefault())"))
        check("infer: fetch().then", lib("fetch('x').then(r => r.§json())"))

        // definition through inferred receivers
        check("infer: array method", lib("const xs = [1, 2]\nxs.§map(x => x)"))
        check("infer: string method of a call result", lib("const s = 'a'.toUpperCase()\ns.§trim()"))
        check("infer: number method", lib("const v = 1.5\nv.§toFixed(1)"))
        let own = target("const o = { alpha: 1 }\no.§alpha")
        check("infer: object literal member", own == [lastFile + ":1"])
        let viaCall = target("class A { go() { return 1 } }\nfunction mk() { return new A() }\nmk().§go()")
        check("infer: member of a call result", viaCall == [lastFile + ":1"])
        check("infer: callback parameter members", lib("const names = ['a']\nnames.forEach(s => s.§charAt(0))"))
        check("infer: Promise then", lib("const p = Promise.resolve(1)\np.§then(v => v)"))
        check("infer: chained array methods", lib("[1, 2].map(x => x * 2).§filter(x => x > 1)"))
        check("infer: unknown receiver gives nothing", target("const u = mystery()\nu.§foo").isEmpty)
        check("infer: any receiver gives nothing", target("declare const a: any\na.§foo").isEmpty)
        check("infer: a type parameter never resolves to a same-named class", target("class T { zed = 1 }\nfunction id<T>(x: T) { return x.§zed }").isEmpty)
        check("infer: destructured binding is not the whole value", target("class Owner { email = 1 }\nfunction mk(): Owner { return new Owner() }\nlet [d1] = mk()\nd1.§email").isEmpty)

        // completion lists
        func complete(_ code: String) -> Set<String> {
            n += 1
            let url = root.appendingPathComponent("c\(n).ts")
            let ns = code as NSString
            let proj = NJSProject.shared(root: root.path)
            return proj.queue.sync {
                proj.modules.beginRequest()
                let prefix = NSRange(location: ns.length, length: 0)
                return Set(NativeJSProviderSupport.memberItems(proj: proj, file: url.path, text: ns, prefix: prefix, receiverEnd: ns.length - 1).map { $0.label })
            }
        }
        let arr = complete("const xs = [1, 2]\nxs.")
        check("infer: completion on an array", arr.contains("map") && arr.contains("push") && arr.contains("length"))
        let str = complete("const s = 'abc'\ns.")
        check("infer: completion on a string", str.contains("toUpperCase") && str.contains("length"))
        let obj = complete("const o = { alpha: 1, beta: 'x' }\no.")
        check("infer: completion on an object literal", obj.contains("alpha") && obj.contains("beta"))
        let call = complete("function mk() { return { id: 1, name: 'n' } }\nmk().")
        check("infer: completion on a call result", call.contains("id") && call.contains("name"))
        let cls = complete("class A { go() {} v = 1 }\nconst a = new A()\na.")
        check("infer: completion on an instance", cls.contains("go") && cls.contains("v"))
        check("infer: nothing on unknown", complete("const u = mystery()\nu.").isEmpty)
    }

    static func runDiagTypes() {
        guard let bundled = NJSLib.bundledDirectory() else { SelfTest.check("diag types: bundled TsLib/ directory found", false); return }
        NJSLib.directoryOverride = bundled
        let was = NativeJSDiag.typesEnabled
        NativeJSDiag.typesEnabled = true
        defer { NativeJSDiag.typesEnabled = was; NJSLib.directoryOverride = nil; NJSLib.trim() }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-njsdt-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        put(root, "package.json", "{}")
        put(root, "other.ts", "export const x = 1\n")
        func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }
        var n = 0
        func codes(_ code: String, ext: String = "ts") -> [String] {
            n += 1
            let url = root.appendingPathComponent("d\(n).\(ext)")
            return NativeJSDiag.analyze(url: url, text: code as NSString).map { $0.code + ":" + $0.message }
        }
        check("diag types: an unknown name is TS2304", codes("const a = missingName + 1\n") == ["TS2304:Cannot find name 'missingName'."])
        check("diag types: locals, parameters, lib globals, imports are known", codes("import { x } from './other'\nfunction f(p: number) { const q = Math.max(p, 1); return [q, x, console, JSON, Promise, setTimeout, document] }\nclass C { m() { return f(1) } }\nexport default C\n").isEmpty)
        check("diag types: hoisted functions, enums, namespaces and class names are known", codes("g()\nfunction g() { return E.A }\nenum E { A }\nnamespace N { export const k = 1 }\nconsole.log(N.k, new K())\nclass K {}\n").isEmpty)
        check("diag types: type names, property keys and member names are not values", codes("interface I { foo: number }\nconst o = { bar: 1 }\nconst z: I = { foo: o.bar }\nz.foo\n").isEmpty)
        check("diag types: typeof of an undeclared name is allowed", codes("const t = typeof maybeGlobal === 'undefined'\n").isEmpty)
        check("diag types: JavaScript files are not checked", codes("const a = missingName + 1\n", ext: "js").isEmpty)
        check("diag types: a destructured / catch / for-of binding is known", codes("const { a, b: [c] } = { a: 1, b: [2] }\ntry { a } catch (err) { err }\nfor (const w of [c]) { w }\n").isEmpty)
        check("diag types: argument count of a function declaration", codes("function f(a: number, b: number) { return a + b }\nf(1)\n") == ["TS2554:Expected 2 arguments, but got 1."])
        check("diag types: too many arguments", codes("function f(a: number) { return a }\nf(1, 2)\n") == ["TS2554:Expected 1 argument, but got 2."])
        check("diag types: optional, default and rest parameters", codes("function f(a: number, b?: number, c = 1, ...d: number[]) { return a }\nf(1)\nf(1, 2, 3, 4, 5)\n").isEmpty)
        check("diag types: spread arguments and overloaded functions are not judged", codes("function f(a: number, b: number) { return a + b }\nf(...[1, 2])\nfunction h(a: string): void\nfunction h(a: number, b: number): void\nfunction h(a: any, b?: any) {}\nh('x')\n").isEmpty)
        check("diag types: off by default and by preference", { NativeJSDiag.typesEnabled = false; defer { NativeJSDiag.typesEnabled = true }; return codes("const a = missingName\n").isEmpty }())
        // a project with a script-style declaration file cannot be judged
        let r2 = fm.temporaryDirectory.appendingPathComponent("ce-njsdt2-\(getpid())").standardizedFileURL
        let r3 = fm.temporaryDirectory.appendingPathComponent("ce-njsdt3-\(getpid())").standardizedFileURL
        defer { try? fm.removeItem(at: r2); try? fm.removeItem(at: r3) }
        put(r2, "package.json", "{}")
        put(r2, "globals.d.ts", "declare const __APP_VERSION__: string\n")
        let u2 = r2.appendingPathComponent("a.ts")
        check("diag types: silent when the project has global declaration files", NativeJSDiag.analyze(url: u2, text: "const v = __APP_VERSION__ + notDeclared\n" as NSString).filter { $0.code == "TS2304" }.isEmpty)
        // a tsconfig that does not include the file
        put(r3, "package.json", "{}")
        put(r3, "tsconfig.json", "{\"include\": [\"src\"]}")
        let u3 = r3.appendingPathComponent("other/a.ts")
        check("diag types: silent for files outside the tsconfig include", NativeJSDiag.analyze(url: u3, text: "const v = notDeclared\n" as NSString).filter { $0.code == "TS2304" }.isEmpty)
        let u4 = r3.appendingPathComponent("src/a.ts")
        check("diag types: judged inside the include", NativeJSDiag.analyze(url: u4, text: "const v = notDeclared\n" as NSString).filter { $0.code == "TS2304" }.count == 1)
    }
}
