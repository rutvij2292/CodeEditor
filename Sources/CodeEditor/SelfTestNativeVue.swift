import AppKit

/// Headless checks for the native Vue template service (NativeVue*.swift). Snippets mark the pointer / caret with `§`.
enum SelfTestNativeVue {
    static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("vue: " + name, ok()) }
    static func put(_ root: URL, _ rel: String, _ text: String) { SelfTestNativePHP.put(root, rel, text) }

    static let myButton = #"""
    <template>
      <button class="btn" @click="$emit('click', $event)">
        <slot name="icon" :size="size" />
        <slot />
      </button>
    </template>

    <script setup lang="ts">
    import { computed } from 'vue'

    interface Props {
      /** Text on the button */
      label: string
      fooBar?: number
      size?: 'sm' | 'lg'
    }
    const props = defineProps<Props>()
    const emit = defineEmits<{
      (e: 'save', id: number): void
      (e: 'update:modelValue', v: string): void
    }>()
    const model = defineModel<string>()
    const size = computed(() => props.size ?? 'sm')
    </script>
    """#

    static let fooBar = #"""
    <template>
      <div>
        <span ref="input">{{ title }} {{ total }}</span>
        <button @click="reload">go</button>
        <MyButton label="x" />
      </div>
    </template>

    <script>
    import MyButton from './MyButton.vue'
    import { mapGetters } from 'vuex'

    export default {
      name: 'FooBar',
      components: { MyButton },
      props: {
        title: { type: String, required: true },
        rowCount: Number,
      },
      emits: ['done', 'update:title'],
      data() {
        return { loading: false, items: [] }
      },
      computed: {
        total() { return this.items.length },
        ...mapGetters(['user']),
      },
      methods: {
        reload() { this.$emit('done') },
      },
    }
    </script>
    """#

    static let home = #"""
    <template>
      <div class="home">
        <MyButton label="a" :foo-bar="3" v-model="name" @save="onSave" @update:modelValue="onModel" :size="'lg'">
          <template #icon="{ size }"><i :class="size" /></template>
          text
        </MyButton>
        <my-button label="b" />
        <FooBar title="t" :row-count="2" @done="onSave" />
        <GlobalThing />
        <lazy-card />
        <Barrel />
        <AutoOne />
        <Mystery />
        <router-link to="/about">About</router-link>
        <router-link :to="{ name: 'about' }">About</router-link>
        <img src="@/assets/logo.png" alt="">
        <ul>
          <li v-for="(row, i) in rows" :key="row.id" @click="select(row, i)">{{ row.name }} {{ count }} {{ formatDate(row.at) }}</li>
        </ul>
        <MyButton v-for="n in 3" :key="n" label="n" @click="(count) => count + n" ref="btn" />
        <input ref="field" />
        <p @click="$refs.field.focus()">{{ label }}</p>
      </div>
    </template>

    <script setup>
    import { ref, computed } from 'vue'
    import MyButton from '@/components/MyButton.vue'
    import FooBar from './../components/FooBar.vue'
    import { Barrel } from '@components'
    import { formatDate } from '@/helper/date.js'

    const props = defineProps({
      label: { type: String, default: '' },
    })
    const name = ref('')
    const rows = ref([])
    const count = computed(() => rows.value.length)
    const btn = ref(null)
    function onSave(id) {}
    const onModel = (v) => {}
    function select(row, i) {}
    </script>

    <style src="./home.css"></style>
    """#

    static func build(_ root: URL) {
        put(root, "package.json", #"{"dependencies":{"vue":"^3.5.0","libui":"1.0.0"}}"#)
        put(root, "vite.config.js", """
        import { defineConfig } from 'vite'
        import path from 'path'
        import Components from 'unplugin-vue-components/vite'
        export default defineConfig({
          plugins: [Components({ dirs: ['src/auto'] })],
          resolve: { alias: { '@': path.resolve(__dirname, 'src'), '@components': path.resolve(__dirname, 'src/components') } },
        })
        """)
        put(root, "src/main.js", """
        import { createApp } from 'vue'
        import App from './App.vue'
        import GlobalThing from './components/GlobalThing.vue'
        createApp(App)
          .component('GlobalThing', GlobalThing)
          .component("lazy-card", () => import('./components/LazyCard.vue'))
          .mount('#app')
        """)
        put(root, "src/App.vue", "<template><Home /></template>\n<script setup>\nimport Home from './pages/Home.vue'\n</script>\n")
        put(root, "src/components/MyButton.vue", myButton)
        put(root, "src/components/FooBar.vue", fooBar)
        put(root, "src/components/GlobalThing.vue", "<template>\n  <section>global</section>\n</template>\n")
        put(root, "src/components/LazyCard.vue", "<template>\n  <article>lazy</article>\n</template>\n")
        put(root, "src/components/Barrel.vue", "<template>\n  <aside>barrel</aside>\n</template>\n")
        put(root, "src/components/index.js", "export { default as Barrel } from './Barrel.vue'\n")
        put(root, "src/auto/AutoOne.vue", "<template>\n  <div>auto</div>\n</template>\n")
        put(root, "src/pages/Home.vue", home)
        put(root, "src/pages/home.css", "body { margin: 0 }\n")
        put(root, "src/pages/Other.vue", "<template>\n  <MyButton label=\"o\" />\n  <my-button label=\"p\" @save=\"x\" />\n</template>\n<script setup>\nimport MyButton from '../components/MyButton.vue'\n</script>\n")
        put(root, "src/assets/logo.png", "png")
        put(root, "src/helper/date.js", "export function formatDate(d) {\n  return String(d)\n}\n")
        put(root, "src/router/index.js", "export const routes = [\n  { path: '/about', name: 'about', component: () => import('../pages/Other.vue') },\n]\n")
        // a library component with a declaration file
        put(root, "node_modules/libui/package.json", #"{"name":"libui","version":"1.0.0","main":"./index.mjs","types":"./index.d.ts"}"#)
        put(root, "node_modules/libui/index.mjs", "export default {}\n")
        put(root, "node_modules/libui/index.d.ts", """
        export interface SelectProps {
            /** Label shown for each option. */
            optionLabel?: string;
            options?: any[];
        }
        export interface SelectEmitsOptions {
            /** Emitted when the value changes. */
            'update:modelValue'(value: any): void;
            change(event: Event): void;
        }
        declare const Select: DefineComponent<SelectProps, {}, SelectEmitsOptions>;
        export default Select;
        """)
    }

    static func ctx(_ url: URL, _ snippet: String) -> CompletionContext {
        let off = (snippet as NSString).range(of: "§").location
        let text = snippet.replacingOccurrences(of: "§", with: "")
        let ns = text as NSString
        var s = off
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        return CompletionContext(text: text, caret: off, fileURL: url, fileExtension: "vue", triggerCharacter: nil, isManual: true, prefixRange: NSRange(location: s, length: off - s))
    }

    /// Marks `needle` (first occurrence) with the pointer a few characters inside it: `at("<MyButton", 3)` points at `Bu`.
    static func hit(_ url: URL, _ text: String, _ needle: String, _ inside: Int = 1, nth: Int = 0, root: String) -> NPHit? {
        let ns = text as NSString
        var from = 0
        var r = NSRange(location: NSNotFound, length: 0)
        for _ in 0...nth {
            r = ns.range(of: needle, options: [], range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { return nil }
            from = NSMaxRange(r)
        }
        return NativeVue.lookup(url: url, text: ns, offset: r.location + inside, root: root)
    }

    static func line(of path: String, _ offset: Int) -> Int {
        guard let t = FastProject.readRaw(path) else { return -1 }
        return NPLineStarts(t).position(of: offset).line
    }

    static func lineText(_ path: String, _ n: Int) -> String {
        guard let t = FastProject.readRaw(path) else { return "" }
        let lines = (t as String).components(separatedBy: "\n")
        return n >= 1 && n <= lines.count ? lines[n - 1].trimmingCharacters(in: .whitespaces) : ""
    }

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-selftest-vue-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        build(root)
        defer { try? fm.removeItem(at: root) }
        let r = root.path
        let homeURL = root.appendingPathComponent("src/pages/Home.vue")
        let t = home
        func target(_ h: NPHit?) -> (file: String, text: String)? {
            guard let h, let tg = h.targets.first else { return nil }
            return ((tg.path as NSString).lastPathComponent, lineText(tg.path, tg.line))
        }

        // custom component tags
        var h = hit(homeURL, t, "<MyButton", 4, root: r)
        check("tag via script setup import (alias @/)", target(h)?.file == "MyButton.vue")
        check("tag jump lands on the component root element", target(h)?.text == "<button class=\"btn\" @click=\"$emit('click', $event)\">")
        check("tag hover lists props, emits and slots", (h?.markdown.contains("label") ?? false) && (h?.markdown.contains("save") ?? false) && (h?.markdown.contains("icon") ?? false))
        check("tag hit range is the tag name", h.map { (t as NSString).substring(with: $0.range) } == "MyButton")
        h = hit(homeURL, t, "<my-button", 4, root: r)
        check("kebab-case tag resolves to the PascalCase import", target(h)?.file == "MyButton.vue")
        h = hit(homeURL, t, "</MyButton", 5, root: r)
        check("closing tag resolves too", target(h)?.file == "MyButton.vue")
        h = hit(homeURL, t, "<FooBar", 3, root: r)
        check("tag via relative import (../)", target(h)?.file == "FooBar.vue")
        h = hit(root.appendingPathComponent("src/components/FooBar.vue"), fooBar, "<MyButton", 3, root: r)
        check("tag via components: {} option (plain <script>)", target(h)?.file == "MyButton.vue")
        h = hit(homeURL, t, "<GlobalThing", 3, root: r)
        check("global registration (.component('X', X))", target(h)?.file == "GlobalThing.vue")
        h = hit(homeURL, t, "<lazy-card", 3, root: r)
        check("global async registration (kebab key, import())", target(h)?.file == "LazyCard.vue")
        h = hit(homeURL, t, "<Barrel", 3, root: r)
        check("named import through an aliased barrel index.js", target(h)?.file == "Barrel.vue")
        h = hit(homeURL, t, "<AutoOne", 3, root: r)
        check("auto-imported directory (unplugin-vue-components dirs)", target(h)?.file == "AutoOne.vue")
        check("unknown tag stays silent", hit(homeURL, t, "<Mystery", 3, root: r) == nil)
        check("native element stays silent", hit(homeURL, t, "<div", 2, root: r) == nil)

        // props, events, slots
        h = hit(homeURL, t, ":foo-bar", 3, root: r)
        check("kebab attribute -> camelCase prop declaration (type literal interface)", target(h)?.file == "MyButton.vue" && target(h)?.text == "fooBar?: number")
        h = hit(homeURL, t, "label=\"a\"", 2, root: r)
        check("plain attribute -> prop with doc", target(h)?.text == "label: string" && (h?.markdown.contains("Text on the button") ?? false))
        h = hit(homeURL, t, "v-model=", 3, root: r)
        check("v-model -> defineModel prop", target(h)?.file == "MyButton.vue" && (target(h)?.text.contains("defineModel") ?? false))
        h = hit(homeURL, t, "@save", 2, root: r)
        check("@event -> defineEmits call signature", target(h)?.text.hasPrefix("(e: 'save'") ?? false)
        h = hit(homeURL, t, "@update:modelValue", 5, root: r)
        check("@update:modelValue -> emit declaration", (target(h)?.text.contains("update:modelValue") ?? false))
        h = hit(homeURL, t, "#icon", 2, root: r)
        check("#slot -> <slot name> in the component", target(h)?.text.hasPrefix("<slot name=\"icon\"") ?? false)
        h = hit(homeURL, t, "title=\"t\"", 2, root: r)
        check("options API props object", target(h)?.file == "FooBar.vue" && target(h)?.text.hasPrefix("title: {") ?? false)
        h = hit(homeURL, t, ":row-count", 3, root: r)
        check("options API prop camelised (row-count -> rowCount)", target(h)?.text == "rowCount: Number,")
        h = hit(homeURL, t, "@done", 2, root: r)
        check("options API emits array", target(h)?.text.contains("emits:") ?? false)

        // expressions
        h = hit(homeURL, t, "{{ row.name }}", 4, root: r)
        check("v-for alias in interpolation -> alias in the v-for attribute", h?.targets.first.map { (t as NSString).substring(with: NSRange(location: $0.offset, length: 3)) } == "row")
        h = hit(homeURL, t, "in rows", 5, root: r)
        check("v-for source -> script binding", target(h)?.text.hasPrefix("const rows = ref") ?? false)
        h = hit(homeURL, t, "{{ row.name }} {{ count }}", 18, root: r)
        check("computed binding in interpolation", target(h)?.text.hasPrefix("const count = computed") ?? false)
        h = hit(homeURL, t, "select(row, i)", 2, root: r)
        check("event handler -> function declaration", target(h)?.text.hasPrefix("function select") ?? false)
        h = hit(homeURL, t, "select(row, i)", 9, root: r)
        check("handler argument -> v-for alias", h?.targets.first.map { (t as NSString).substring(with: NSRange(location: $0.offset, length: 3)) } == "row")
        h = hit(homeURL, t, "formatDate(row.at)", 3, root: r)
        check("imported function -> its declaration in the other file", target(h)?.file == "date.js" && target(h)?.text == "export function formatDate(d) {")
        h = hit(homeURL, t, "{{ label }}", 5, root: r)
        check("prop used in the template -> defineProps entry", target(h)?.text.hasPrefix("label: {") ?? false)
        h = hit(homeURL, t, "(count) => count + n", 12, root: r)
        check("arrow function parameter is local (not the script binding)", h?.targets.first.map { $0.offset < (t as NSString).range(of: "(count) =>").location + 10 } == true)
        h = hit(homeURL, t, "$refs.field", 8, root: r)
        check("$refs.name -> the element with that ref", h?.targets.first.map { (t as NSString).substring(with: NSRange(location: $0.offset, length: 5)) } == "field")
        h = hit(homeURL, t, "ref=\"btn\"", 6, root: r)
        check("ref=\"x\" -> script binding", target(h)?.text.hasPrefix("const btn = ref") ?? false)
        check("member access on an unknown object stays silent", hit(homeURL, t, "row.name", 6, nth: 1, root: r) == nil)
        h = hit(root.appendingPathComponent("src/components/FooBar.vue"), fooBar, "{{ title }}", 5, root: r)
        check("options API prop in template", target(h)?.text.hasPrefix("title: {") ?? false)
        h = hit(root.appendingPathComponent("src/components/FooBar.vue"), fooBar, "{{ total }}", 5, root: r)
        check("options API computed in template", target(h)?.text.hasPrefix("total()") ?? false)
        h = hit(root.appendingPathComponent("src/components/FooBar.vue"), fooBar, "\"reload\"", 3, root: r)
        check("options API method in template", target(h)?.text.hasPrefix("reload()") ?? false)

        // assets, routes
        h = hit(homeURL, t, "@/assets/logo.png", 6, root: r)
        check("src with alias -> asset file", target(h)?.file == "logo.png")
        h = hit(homeURL, t, "./home.css", 4, root: r)
        check("<style src> -> stylesheet", target(h)?.file == "home.css")
        h = hit(homeURL, t, "to=\"/about\"", 6, root: r)
        check("router-link to=\"/path\" -> route record", target(h)?.file == "index.js" && (target(h)?.text.contains("path: '/about'") ?? false))
        h = hit(homeURL, t, "name: 'about'", 9, root: r)
        check("router-link :to name -> route record", target(h)?.file == "index.js")

        // library component declarations
        let libText = "<template>\n  <Select :option-label=\"'x'\" @change=\"go\" />\n</template>\n<script setup>\nimport Select from 'libui'\n</script>\n"
        let libURL = root.appendingPathComponent("src/Lib.vue")
        put(root, "src/Lib.vue", libText)
        h = hit(libURL, libText, "<Select", 3, root: r)
        check("library component -> its .d.ts declaration", target(h)?.file == "index.d.ts" && (target(h)?.text.contains("declare const Select") ?? false))
        h = hit(libURL, libText, ":option-label", 4, root: r)
        check("library prop -> interface member with docs", target(h)?.text.hasPrefix("optionLabel?") ?? false)
        h = hit(libURL, libText, "@change", 3, root: r)
        check("library event -> emits interface member", target(h)?.text.hasPrefix("change(event") ?? false)

        // nuxt style auto imports
        let nuxt = fm.temporaryDirectory.appendingPathComponent("ce-selftest-nuxt-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: nuxt)
        defer { try? fm.removeItem(at: nuxt) }
        put(nuxt, "package.json", #"{"dependencies":{"nuxt":"^3"}}"#)
        put(nuxt, "nuxt.config.ts", "export default defineNuxtConfig({})\n")
        put(nuxt, "components/base/Button.vue", "<template>\n  <button>b</button>\n</template>\n")
        put(nuxt, "components/Card.global.vue", "<template>\n  <div>c</div>\n</template>\n")
        put(nuxt, "components/Foo/index.vue", "<template>\n  <div>foo</div>\n</template>\n")
        let pageText = "<template>\n  <div><BaseButton /><Card /><LazyCard /><Foo /></div>\n</template>\n"
        put(nuxt, "pages/index.vue", pageText)
        let pageURL = nuxt.appendingPathComponent("pages/index.vue")
        h = hit(pageURL, pageText, "<BaseButton", 4, root: nuxt.path)
        check("nuxt: nested directory prefix (components/base/Button.vue -> BaseButton)", target(h)?.file == "Button.vue")
        h = hit(pageURL, pageText, "<Card", 3, root: nuxt.path)
        check("nuxt: .global.vue suffix", target(h)?.file == "Card.global.vue")
        h = hit(pageURL, pageText, "<LazyCard", 3, root: nuxt.path)
        check("nuxt: Lazy prefix", target(h)?.file == "Card.global.vue")
        h = hit(pageURL, pageText, "<Foo", 3, root: nuxt.path)
        check("nuxt: Dir/index.vue -> Dir", target(h)?.file == "index.vue" && h?.targets.first?.path.hasSuffix("components/Foo/index.vue") == true)

        usageChecks(root, r)
        completionChecks(root, r)
        resourceChecks(root, r, homeURL, t)
        off(homeURL, t, r)
    }

    static func usageChecks(_ root: URL, _ r: String) {
        let p = NVProject.shared(root: r)
        let home = root.appendingPathComponent("src/pages/Home.vue").path
        let docText = SelfTestNativeVue.home as NSString
        // identify from the tag
        let doc = NVDoc(p, file: home, text: docText, needsTemplate: false)
        let tagOff = docText.range(of: "<MyButton").location + 3
        let target = doc.flatMap { NVRefs.identify($0, offset: tagOff) }
        check("usages: component identified from a tag", target?.path.hasSuffix("src/components/MyButton.vue") == true)
        guard let target else { return }
        let hits = NVRefs.collect(p, target: target, liveTexts: [:], cancel: nil)
        let usages = hits.filter { $0.role == .usage }
        let files = Set(usages.map { ($0.path as NSString).lastPathComponent })
        // Home: <MyButton> x2 + <my-button> x1 = 3, FooBar 1, Other 2 (Pascal + kebab)
        check("usages: every template usage across the project (Pascal and kebab, 3 files)", usages.count == 6 && files == ["Home.vue", "FooBar.vue", "Other.vue"])
        check("usages: import statements are listed too", hits.contains { $0.role == .import })
        check("usages: hits point at the tag name", usages.allSatisfy { h in
            guard let t = FastProject.readRaw(h.path) else { return false }
            return ["MyButton", "my-button"].contains(t.substring(with: h.range))
        })
        // prop-specific
        var pt = target; pt.prop = "label"
        let propHits = NVRefs.collect(p, target: pt, liveTexts: [:], cancel: nil)
        check("usages: prop filter lists only that attribute", propHits.count == 6 && propHits.allSatisfy { h in FastProject.readRaw(h.path)?.substring(with: h.range) == "label" })
        var et = target; et.event = "save"
        let evHits = NVRefs.collect(p, target: et, liveTexts: [:], cancel: nil)
        check("usages: event filter", evHits.count == 2)
        // from the component file itself
        let comp = root.appendingPathComponent("src/components/MyButton.vue").path
        let ct = SelfTestNativeVue.myButton as NSString
        let cdoc = NVDoc(p, file: comp, text: ct, needsTemplate: false)
        let own = cdoc.flatMap { NVRefs.identify($0, offset: ct.range(of: "<script").location + 2) }
        check("usages: <script> / <template> block tag stands for the file's own component", own?.path == comp)
        // live (unsaved) text of another file overrides disk
        let live = ["\(root.path)/src/pages/Other.vue": "<template><div /></template>" as NSString]
        let hits2 = NVRefs.collect(p, target: target, liveTexts: live, cancel: nil).filter { $0.role == .usage }
        check("usages: unsaved buffers are searched instead of disk", hits2.count == 4)
    }

    static func completionChecks(_ root: URL, _ r: String) {
        let url = root.appendingPathComponent("src/pages/Home.vue")
        let p = NVProject.shared(root: r)
        func items(_ s: String) -> [CompletionItem] { NVComplete.items(p, ctx(url, s)) }
        let head = "<template>\n  <div>\n    "
        let tail = "\n  </div>\n</template>\n<script setup>\nimport { ref } from 'vue'\nimport MyButton from '@/components/MyButton.vue'\nconst rows = ref([])\nconst count = ref(0)\n</script>\n"
        var it = items(head + "<MyBu§" + tail)
        check("completion: imported component tag", it.contains { $0.label == "MyButton" })
        check("completion: unimported project component carries the import edit", { () -> Bool in
            let fb = items(head + "<FooB§" + tail).first { $0.label == "FooBar" }
            return fb?.additionalEdits.first?.text.contains("import FooBar from '../components/FooBar.vue'") == true
        }())
        it = items(head + "<§" + tail)
        check("completion: bare '<' lists globals and auto imports", it.contains { $0.label == "GlobalThing" } && it.contains { $0.label == "AutoOne" })
        it = items(head + "<MyButton §" + tail)
        check("completion: props after the tag, required first", it.first?.label == "label" && it.contains { $0.label == "foo-bar" })
        check("completion: events offered as @name", it.contains { $0.label == "@save" })
        it = items(head + "<MyButton @§" + tail)
        check("completion: '@' lists emits only", it.contains { $0.label == "@save" } && !it.contains { $0.label == "label" })
        it = items(head + "<MyButton :fo§" + tail)
        check("completion: ':' lists props", it.contains { $0.label == ":foo-bar" })
        it = items(head + "<MyButton label=\"x\" §" + tail)
        check("completion: attributes already present are not repeated", !it.contains { $0.label == "label" })
        it = items(head + "<MyButton #§" + tail)
        check("completion: '#' lists slots", it.contains { $0.label == "#icon" } && it.contains { $0.label == "#default" })
        it = items(head + "<p>{{ co§" + tail)
        check("completion: bindings inside {{ }}", it.contains { $0.label == "count" } && it.contains { $0.label == "rows" })
        it = items(head + "<li v-for=\"row in rows\" :key=\"ro§\" />" + tail)
        check("completion: v-for aliases inside attribute expressions", it.contains { $0.label == "row" })
        check("completion: nothing after a member access", items(head + "<p>{{ rows.§" + tail).isEmpty)
        check("completion: plain element attributes are left to the web provider", items(head + "<div §" + tail).isEmpty)
    }

    static func resourceChecks(_ root: URL, _ r: String, _ homeURL: URL, _ t: String) {
        let p = NVProject.shared(root: r)
        // many different lookups keep the caches within their caps
        for _ in 0..<3 { for needle in ["<MyButton", "<FooBar", ":foo-bar", "{{ count }}"] { _ = hit(homeURL, t, needle, 3, root: r) } }
        check("resources: summary cache stays within its caps", p.cachedSummaries <= NVProject.maxEntries && p.cachedCost <= NVProject.maxCost)
        // a plain tag completion must not walk the project when nothing needs the file list
        let fresh = NVProject.shared(root: root.path + "/nowhere")
        check("resources: a fresh project has not walked anything", !fresh.isListed)
        // trimming drops caches, answers stay correct
        NativeVue.trimMemory()
        let sem = DispatchSemaphore(value: 0)
        p.queue.async { sem.signal() }
        sem.wait()
        check("resources: trim empties the caches", p.cachedSummaries == 0)
        check("resources: lookups still work after a trim", hit(homeURL, t, "<MyButton", 4, root: r)?.targets.first?.path.hasSuffix("MyButton.vue") == true)
        // latency of a warm lookup
        let t0 = Date()
        for _ in 0..<20 { _ = hit(homeURL, t, "<FooBar", 3, root: r) }
        let ms = Date().timeIntervalSince(t0) * 1000 / 20
        check("resources: warm tag lookup under 25 ms (\(Int(ms)) ms)", ms < 25)
    }

    static func off(_ homeURL: URL, _ t: String, _ r: String) {
        NativeVue.enabled = false
        let none = hit(homeURL, t, "<MyButton", 4, root: r)
        NativeVue.enabled = true
        check("switch: off answers no opinion", none == nil)
        check("switch: on again", hit(homeURL, t, "<MyButton", 4, root: r) != nil)
    }
}
