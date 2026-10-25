import AppKit

/// Headless checks for the native CSS / HTML / Tailwind service (NativeWeb*.swift, NativeCSS*.swift, NativeHTML*.swift, NativeTailwind*.swift).
/// Snippets mark the caret / pointer with `§` (removed before the request).
enum SelfTestNativeWeb {
    static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("web: " + name, ok()) }

    static func put(_ root: URL, _ rel: String, _ text: String) { SelfTestNativePHP.put(root, rel, text) }

    static let v3Config = """
    const colors = require('tailwindcss/colors')
    const defaultTheme = require('tailwindcss/defaultTheme')

    /** @type {import('tailwindcss').Config} */
    module.exports = {
      content: ['./resources/**/*.blade.php'],
      darkMode: 'class',
      theme: {
        screens: { sm: '600px', md: '900px', lg: '1200px' },
        extend: {
          colors: {
            primary: { DEFAULT: '#3366ff', dark: '#1a3399', 500: '#3366ff' },
            brand: colors.emerald,
            ink: 'rgb(var(--ink) / <alpha-value>)',
          },
          spacing: { '18': '4.5rem', gutter: '1.25rem' },
          fontFamily: { display: ['Poppins', ...defaultTheme.fontFamily.sans] },
          borderRadius: { xl2: '1.25rem' },
        },
      },
      plugins: [require('@tailwindcss/typography')],
    }
    """

    static func buildV3(_ root: URL) {
        put(root, "package.json", #"{"devDependencies":{"tailwindcss":"^3.4.0"}}"#)
        put(root, "tailwind.config.js", v3Config)
        put(root, "resources/css/app.css", """
        @tailwind base;
        @tailwind components;
        @tailwind utilities;
        :root { --brand-color: #ff0000; --gap: 12px; }
        /* .commented { } */
        .btn { @apply px-4 py-2 rounded; }
        .btn-primary { color: var(--brand-color); background: url("x.png"); }
        #main-nav { display: flex; }
        @media (min-width: 640px) { .container-x, .other:hover { margin: 0 auto } }
        .card > .card-title::after { content: ".fake {"; }
        """)
        put(root, "resources/css/extra.scss", """
        $gap: 4px;
        // .line-comment { }
        .block { color: red;
          &-title { font-weight: bold; }
          &:hover { opacity: .5 }
          .nested-item { margin: $gap }
        }
        """)
        put(root, "resources/views/welcome.blade.php", """
        <div class="btn btn-primary p-4 {{ $active ? 'bg-primary' : 'text-lg' }}" id="main-nav">
          <a href="/css/site.css">style</a>
          <label for="main-nav">Nav</label>
          <span class="card-title">x</span>
        </div>
        """)
        put(root, "public/css/site.css", "body { margin: 0 }\n")
        put(root, "resources/js/App.jsx", "export default () => <div className=\"flex items-center\">x</div>\n")
    }

    static let v4Css = """
    @import "tailwindcss";
    @theme {
      --color-brand: #123456;
      --color-brand-light: #6688aa;
      --breakpoint-3xl: 120rem;
      --font-display: "Poppins", sans-serif;
      --radius-pill: 9999px;
    }
    @utility tab-4 { tab-size: 4; }
    @custom-variant theme-dark (&:where([data-theme=dark], [data-theme=dark] *));
    """

    static func buildV4(_ root: URL) {
        put(root, "package.json", #"{"devDependencies":{"tailwindcss":"^4.0.0","@tailwindcss/vite":"^4.0.0"}}"#)
        put(root, "src/app.css", v4Css)
        put(root, "src/index.html", "<div class=\"p-4\">x</div>\n")
    }

    // MARK: helpers

    static func ctx(_ url: URL, _ snippet: String, manual: Bool = true) -> CompletionContext {
        let off = (snippet as NSString).range(of: "§").location
        let text = snippet.replacingOccurrences(of: "§", with: "")
        let ns = text as NSString
        var s = off
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        return CompletionContext(text: text, caret: off, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil, isManual: manual, prefixRange: NSRange(location: s, length: off - s))
    }

    /// CSS text without the server-style `/*4px*/` / `/*#22c55e*/` annotations.
    static func strip(_ s: String?) -> String { (s ?? "").replacingOccurrences(of: "/\\*[^*]*\\*/", with: "", options: .regularExpression) }

    static func labels(_ url: URL, _ snippet: String) -> [String] { NativeWeb.items(for: ctx(url, snippet)).map(\.label) }

    static func hit(_ url: URL, _ snippet: String, usages: Bool = true) -> NPHit? {
        let off = (snippet as NSString).range(of: "§").location
        return NativeWeb.lookup(url: url, text: snippet.replacingOccurrences(of: "§", with: "") as NSString, offset: off, usages: usages)
    }

    /// Dev aid: `CE_WEB_LOCATE=<file>:<line>:<col>` (1-based line, 0-based column in UTF-16) prints how the HTML scanner classifies a position.
    static func locateDebug(_ spec: String) {
        let p = spec.split(separator: ":").map(String.init)
        guard p.count == 3, let t = FastProject.readRaw(p[0]), let line = Int(p[1]), let col = Int(p[2]) else { return }
        let starts = NPLineStarts(t).starts
        let off = starts[line - 1] + col
        let b = NWBuf(t)
        let loc = NWHtml.locate(b, at: off, wantStack: true)
        let site = NWService.htmlClassSite(b, loc: loc, offset: off)
        fputs("LOCATE kind=\(loc.kind) tag=\(loc.tag) attr=\(loc.attrName) value=\(String(describing: loc.valueRange)) tagStart=\(loc.tagStart) classSite=\(String(describing: site)) scriptSite=\(String(describing: NWService.scriptClassSite(b, off))) around=\(b.str(max(0, off - 40), off + 10).replacingOccurrences(of: "\n", with: "\\n"))\n", stderr)
    }

    static func run() {
        if let spec = AppEnv.value("CE_WEB_LOCATE") { locateDebug(spec); exit(0) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-selftest-web-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        buildV3(root)
        defer { try? fm.removeItem(at: root) }
        let css = root.appendingPathComponent("resources/css/app.css")
        let scss = root.appendingPathComponent("resources/css/extra.scss")
        let blade = root.appendingPathComponent("resources/views/welcome.blade.php")
        let html = root.appendingPathComponent("resources/views/page.html")
        let jsx = root.appendingPathComponent("resources/js/App.jsx")

        scanChecks(css: css, scss: scss)
        cssChecks(root, css)
        htmlChecks(root, blade, html)
        tailwindChecks(root, blade, css, jsx)
        configChecks()
        v4Checks(fm)
        gatingChecks(root, css, html)
    }

    // MARK: scanners

    private static func scanChecks(css: URL, scss: URL) {
        let idx = NWCss.index(NWBuf(FastProject.readRaw(css.path)!), lang: .css)
        let names = idx.sels.map(\.name)
        check("css index: classes found", ["btn", "btn-primary", "container-x", "other", "card", "card-title"].allSatisfy(names.contains))
        check("css index: id found", idx.sels.contains { $0.name == "main-nav" && $0.isId })
        check("css index: comment and string classes ignored", !names.contains("commented") && !names.contains("fake"))
        check("css index: custom properties", Set(idx.props.map(\.name)) == ["--brand-color", "--gap"])
        let sidx = NWCss.index(NWBuf(FastProject.readRaw(scss.path)!), lang: .scss)
        let sn = sidx.sels.map(\.name)
        if AppEnv.value("CE_WEB_ONLY") != nil { fputs("DBG css names=\(names) scss=\(sn)\n", stderr) }
        check("scss index: &-suffix expands to block-title", sn.contains("block-title"))
        check("scss index: nested class and // comment", sn.contains("nested-item") && !sn.contains("line-comment"))
        check("scss index: variable declared", sidx.props.contains { $0.name == "$gap" })
        // positions
        func pos(_ s: String, lang: NWCssLang = .css) -> NWCss.Pos {
            let off = (s as NSString).range(of: "§").location
            return NWCss.position(NWBuf(s.replacingOccurrences(of: "§", with: "") as NSString), from: 0, caret: off, lang: lang)
        }
        check("pos: property name", pos("a { col§").kind == .property)
        check("pos: value", { let p = pos("a { display: fl§"); return p.kind == .value && p.prop == "display" }())
        check("pos: top-level selector", pos("a.§").kind == .selector)
        check("pos: at-rule name", pos("@me§").kind == .atName)
        check("pos: inside var()", { let p = pos("a { color: var(--§"); return p.kind == .paren && p.prop == "var" }())
        check("pos: comment", pos("a { /* col§").kind == .comment)
        check("pos: @apply params", { let p = pos("a { @apply p-4 ho§"); return p.kind == .atParams && p.atName == "apply" }())
        check("pos: nested scss selector &:", pos("a { &:ho§", lang: .scss).kind == .selector)
        check("pos: inside @media is selector territory", pos("@media (min-width: 1px) { .a§").kind == .selector)
        check("pos: declaration inside @media inside rule", pos("a { @media print { col§").kind == .property)
        // diagnostics
        func diag(_ s: String) -> [String] { NWCssDiag.analyze(NWBuf(s as NSString)).map(\.message) }
        check("diag: clean stylesheet has no issues", diag("a { color: red } @media print { b { margin: 0 } } /* } */ c::after { content: \"}\" } d { background: url(data:image/svg+xml;utf8,<svg>{}</svg>) }").isEmpty)
        check("diag: unclosed block", diag("a { color: red;\nb { margin: 0 }").first?.contains("Unclosed block") == true)
        check("diag: stray closing brace", diag("a { } }").first?.contains("Unexpected") == true)
        check("diag: unterminated comment", diag("a { } /* open").first?.contains("Unterminated comment") == true)
        check("diag: unterminated string", diag("a { content: \"x\n}").first?.contains("Unterminated string") == true)
        check("diag: only .css files are checked", NWCssDiag.handles(URL(fileURLWithPath: "/x/a.css")) && !NWCssDiag.handles(URL(fileURLWithPath: "/x/a.scss")) && !NWCssDiag.handles(URL(fileURLWithPath: "/x/a.less")))
        // html tokenizer
        let h = "<!-- c --><div class=\"a {{ $x ? \"b\" : 'c' }} d\" id=x>t<?php echo \"<b>\"; ?><br/><style>p{}</style><script>var a = '<i>'</script></div>"
        var tags: [String] = []
        NWHtml.tokenize(NWBuf(h as NSString)) { t in
            if case .open(_, let name, _, _, _, _) = t { tags.append(NWBuf(h as NSString).str(name.location, NSMaxRange(name))) }
            return true
        }
        check("html tokenizer: tags, server code and raw text skipped", tags == ["div", "br", "style", "script"])
        let hb = NWBuf(h as NSString)
        var classes: [String] = []
        NWHtml.eachAttribute(hb) { _, name, _, value, _ in if name == "class" { classes = NWHtml.classTokens(hb, in: value).map(\.name) } }
        check("html class tokens skip {{ }}", classes == ["a", "d"])
    }

    // MARK: CSS service

    private static func cssChecks(_ root: URL, _ css: URL) {
        let scratch = root.appendingPathComponent("resources/css/scratch.css")      // a buffer that is not one of the project's files
        let props = labels(css, ".x { col§ }")
        check("css: property names", props.contains("color") && props.contains("column-gap") && !props.contains("display"))
        check("css: values for display", { let l = labels(css, ".x { display: §"); return l.contains("flex") && l.contains("grid") && l.contains("inherit") }())
        check("css: named colors for color", { let l = labels(scratch, ".x { color: §"); return l.contains("rebeccapurple") && l.contains("var(--brand-color)") }())
        check("css: units after a number", labels(css, ".x { width: 10§").contains("10px"))
        check("css: at-rules", labels(css, "@me§").contains("media"))
        check("css: tailwind at-rules in a tailwind project", labels(css, "@ap§").contains("apply"))
        check("css: pseudo classes", labels(css, "a:ho§").contains("hover"))
        check("css: pseudo elements", labels(css, "a::bef§").contains("before") && !labels(css, "a::bef§").contains("hover"))
        check("css: project class names", labels(scratch, ".x { } .bt§").contains("btn-primary"))
        check("css: ids", labels(scratch, "#ma§").contains("main-nav"))
        check("css: var() custom properties from the project", { let l = labels(scratch, ".x { color: var(--§"); return l.contains("--brand-color") && l.contains("--gap") }())
        check("css: var() sees this buffer's own declarations", labels(css, ":root { --own-token: 1px } .x { margin: var(--§").contains("--own-token"))
        check("css: @apply completes Tailwind classes", { let l = labels(scratch, ".x { @apply bg-pri§"); return l.contains("bg-primary") && l.contains("bg-primary-dark") }())
        check("css: @apply lists project classes too", labels(css, ".x { @apply btn-pri§").contains("btn-primary"))
        check("css: no completion inside comments", labels(css, "/* col§").isEmpty)
        check("css: media features", labels(css, "@media (min§").contains("min-width"))
        let scssURL = root.appendingPathComponent("resources/css/extra.scss")
        check("scss: nested property completion", labels(scssURL, ".a { .b { marg§").contains("margin"))
        // hover
        let hp = hit(css, ".x { dis§play: flex }")
        check("css hover: property doc", hp?.markdown.contains("**display**") == true && hp?.markdown.contains("box") == true)
        check("css hover: hex color", hit(css, ".x { color: #ff0§000 }")?.markdown.contains("rgb 255, 0, 0") == true)
        check("css hover: named color", hit(css, ".x { color: rebecca§purple }")?.markdown.contains("#663399") == true)
        check("css hover: custom property value", hit(scratch, ".x { color: var(--brand-§color) }")?.markdown.contains("#ff0000") == true)
        check("css hover: pseudo class", hit(css, "a:ho§ver { }")?.markdown.contains("hover") == true)
        check("css hover: at-rule", hit(css, "@me§dia print { }")?.markdown.contains("media") == true)
        check("css hover: @apply shows the generated rule", hit(scratch, ".x { @apply hover:bg-pri§mary }")?.markdown.contains(":hover") == true)
        check("css hover: tag", hit(css, "bu§tton { }")?.markdown.contains("button element represents a button") == true)
        // definition
        let dv = hit(scratch, ".x { color: var(--gap§) }")
        check("css def: var() -> declaration", dv?.targets.first?.path == css.path && dv?.targets.first?.line == 4)
        check("css def: @import path", {
            let other = root.appendingPathComponent("resources/css/_part.scss")
            try? "a{}".write(to: other, atomically: true, encoding: .utf8)
            let h = hit(scssURL, "@import \"par§t\";")
            return h?.targets.first?.path == other.path
        }())
        let usage = hit(css, ".btn-pri§mary { }")
        check("css def: class -> markup usage", usage?.targets.contains { $0.path.hasSuffix("welcome.blade.php") } == true)
        check("css hover mode does not scan markup", hit(css, ".btn-pri§mary { }", usages: false)?.targets.isEmpty ?? true)
        check("css def: @apply custom class -> its rule", hit(scratch, ".y { @apply btn-pri§mary }")?.targets.first?.path == css.path)
    }

    // MARK: HTML service

    private static func htmlChecks(_ root: URL, _ blade: URL, _ html: URL) {
        check("html: tag names", labels(html, "<di§").contains("div"))
        check("html: bare < offers tags", labels(html, "<§").contains("section"))
        check("html: closing tag from the open stack", labels(html, "<ul><li>x</li><div>text</§").first == "div")
        check("html: attribute names for input", { let l = labels(html, "<input ty§"); return l.contains("type") && l.contains("placeholder") && l.contains("class") }())
        check("html: already present attributes are not offered", !labels(html, "<input type=\"text\" ty§").contains("type"))
        check("html: attribute values (input type)", labels(html, "<input type=\"§").contains("checkbox"))
        check("html: target values", labels(html, "<a href=\"x\" target=\"§").contains("_blank"))
        check("html: aria attributes", labels(html, "<div aria-la§").contains("aria-label"))
        check("html: for -> ids in the document", labels(html, "<input id=\"email\"><label for=\"§").contains("email"))
        check("html: href anchors", labels(html, "<h1 id=\"top\"></h1><a href=\"#§").contains("#top"))
        check("html: href files under public/", labels(blade, "<link href=\"/css/§").contains("site.css"))
        check("html: <style> content uses css completion", labels(html, "<style>\n.a { col§ }\n</style>").contains("color"))
        check("html: inline style attribute", labels(html, "<div style=\"col§\">").contains("color"))
        if AppEnv.value("CE_WEB_ONLY") != nil { fputs("DBG text=\(labels(html, "<p>hello wor§</p>").prefix(5)) comment=\(labels(html, "<!-- <di§ -->").prefix(5))\n", stderr) }
        check("html: no completion in text or comments", labels(html, "<p>hello wor§</p>").isEmpty && labels(html, "<!-- <di§ -->").isEmpty)
        check("html: no tag completion inside <?php", labels(blade, "<?php $a = '<di§'; ?>").isEmpty)
        check("html: class attribute offers project classes", labels(blade, "<div class=\"btn-pri§\">").contains("btn-primary"))
        check("html: class attribute offers tailwind classes", { let l = labels(blade, "<div class=\"flex p-§\">"); return l.contains("p-4") && labels(blade, "<div class=\"flex §\">").contains("hover:") }())
        check("html: class inside {{ }} string literal", labels(blade, "<div class=\"a {{ $x ? 'bg-pri§' : '' }}\">").contains("bg-primary"))
        check("html: :class binding string", labels(root.appendingPathComponent("a.vue"), "<template><div :class=\"{ 'bg-pri§': ok }\"></div></template>").contains("bg-primary"))
        // hover
        check("html hover: tag", hit(html, "<bu§tton>x</button>")?.markdown.contains("button element represents a button") == true)
        check("html hover: attribute", hit(html, "<a hr§ef=\"x\">")?.markdown.contains("URL") == true)
        check("html hover: data attribute", hit(html, "<a data-fo§o-bar=\"x\">")?.markdown.contains("dataset.fooBar") == true)
        check("html hover: tailwind class shows generated css", strip(hit(blade, "<div class=\"p§-4\">")?.markdown).contains("padding: 1rem;"))
        check("html hover: project class shows its rule", hit(blade, "<div class=\"btn-pri§mary\">")?.markdown.contains("color: var(--brand-color)") == true)
        // definition
        let dc = hit(blade, "<div class=\"btn btn-pri§mary\">")
        check("html def: class -> css rule", dc?.targets.contains { $0.path.hasSuffix("app.css") } == true)
        check("html def: class declared in <style> of the same file", hit(html, "<style>.local { color: red }</style><i class=\"loc§al\">")?.targets.first?.path == html.path)
        check("html def: href -> file under public/", hit(blade, "<a href=\"/css/si§te.css\">")?.targets.first?.path.hasSuffix("public/css/site.css") == true)
        check("html: class in a template literal inside <script>", labels(html, "<script>\nconst t = `<td class=\"bg-pri§\">`\n</script>").contains("bg-primary"))
        check("html: <script> text that is not a class list stays quiet", labels(html, "<script>\nconst t = `plain bg-pri§`\n</script>").isEmpty)
        check("html def: label for -> element id", hit(html, "<input id=\"em\"><label for=\"e§m\">")?.targets.first?.path == html.path)
        check("html def: href=#id -> element", hit(html, "<h1 id=\"top\"></h1><a href=\"#to§p\">")?.targets.count == 1)
        check("html def: id -> css #id rule", hit(blade, "<div id=\"main-§nav\">")?.targets.first?.path.hasSuffix("app.css") == true)
    }

    // MARK: Tailwind

    private static func tailwindChecks(_ root: URL, _ blade: URL, _ css: URL, _ jsx: URL) {
        let p = NWProject.shared(root: root.path)
        guard let tw = p.queue.sync(execute: { p.tailwind(near: root.path) }) else { check("tailwind: project detected", false); return }
        if AppEnv.value("CE_WEB_ONLY") != nil { fputs("DBG tw v\(tw.version) dm=\(tw.darkMode) inputs=\(tw.inputs) primary=\(tw.colors["primary"] ?? "nil") emerald=\(tw.colors["brand-500"] ?? "nil") screens=\(tw.maps["screens"] ?? [:]) unresolved=\(tw.unresolved)\n", stderr) }
        check("tailwind: v3 detected from config", tw.version == 3 && tw.darkMode == "class")
        func css(_ t: String) -> String { strip(tw.css(for: t) ?? "<nil>") }
        check("tailwind: pixel and hex annotations like the Tailwind server", (tw.css(for: "p-4") ?? "").contains("padding: 1rem/*16px*/;") && (tw.css(for: "bg-red-500") ?? "").contains("/*#ef4444*/"))
        check("tailwind: p-4", css("p-4") == ".p-4 {\n  padding: 1rem;\n}")
        check("tailwind: negative margin", css("-mt-2").contains("margin-top: -0.5rem;") && css("-mt-2").hasPrefix(".-mt-2 {"))
        check("tailwind: fraction width", css("w-1/2").contains("width: 50%;") && css("w-1/2").hasPrefix(".w-1\\/2 {"))
        check("tailwind: arbitrary value", css("w-[13px]").contains("width: 13px;") && css("w-[13px]").hasPrefix(".w-\\[13px\\] {"))
        check("tailwind: arbitrary value with underscores", css("grid-cols-[1fr_2fr]").contains("grid-template-columns: 1fr 2fr;"))
        check("tailwind: arbitrary property", css("[mask-type:luminance]").contains("mask-type: luminance;"))
        check("tailwind: theme color (rgb + opacity var)", css("bg-red-500").contains("--tw-bg-opacity: 1;") && css("bg-red-500").contains("rgb(239 68 68 / var(--tw-bg-opacity, 1))"))
        check("tailwind: opacity modifier", css("bg-red-500/50").contains("rgb(239 68 68 / 0.5)"))
        check("tailwind: custom color from config", css("bg-primary").contains("rgb(51 102 255 / var(--tw-bg-opacity, 1))") && css("text-primary-dark").contains("rgb(26 51 153"))
        check("tailwind: colors.emerald spread from tailwind/colors", css("bg-brand-500").contains("rgb(16 185 129"))
        check("tailwind: <alpha-value> placeholder resolved", css("text-ink/50").contains("rgb(var(--ink) / 0.5)") && css("text-ink").contains("rgb(var(--ink) / var(--tw-text-opacity, 1))"))
        check("tailwind: custom spacing", css("mt-18").contains("margin-top: 4.5rem;") && css("p-gutter").contains("padding: 1.25rem;"))
        check("tailwind: screens replaced by the config", css("md:flex").contains("@media (min-width: 900px)") && tw.css(for: "2xl:flex") == nil)
        check("tailwind: variants stack", css("md:hover:p-4").hasPrefix("@media (min-width: 900px) {\n  .md\\:hover\\:p-4:hover {"))
        check("tailwind: dark class mode", css("dark:bg-black").contains(":is(.dark .dark\\:bg-black)"))
        check("tailwind: group-hover", css("group-hover:underline").contains(".group:hover .group-hover\\:underline"))
        check("tailwind: peer-checked", css("peer-checked:block").contains(".peer:checked ~ .peer-checked\\:block"))
        check("tailwind: important", css("!p-4").contains("padding: 1rem !important;"))
        check("tailwind: font size + line height", css("text-lg").contains("font-size: 1.125rem;") && css("text-lg").contains("line-height: 1.75rem;"))
        check("tailwind: text color vs size disambiguation", css("text-red-500").contains("color:") && !css("text-red-500").contains("font-size"))
        check("tailwind: text arbitrary color and size", css("text-[#333]").contains("color: #333") || css("text-[#333]").contains("rgb(51 51 51"))
        check("tailwind: text arbitrary length", css("text-[14px]").contains("font-size: 14px;"))
        check("tailwind: border width vs color", css("border-2").contains("border-width: 2px;") && css("border-gray-200").contains("border-color:"))
        check("tailwind: rounded + custom radius", css("rounded-lg").contains("border-radius: 0.5rem;") && css("rounded-xl2").contains("border-radius: 1.25rem;"))
        check("tailwind: shadow", css("shadow-md").contains("--tw-shadow: 0 4px 6px -1px"))
        check("tailwind: grid cols", css("grid-cols-3").contains("repeat(3, minmax(0, 1fr))"))
        check("tailwind: space-x", css("space-x-4").contains(" > :not([hidden]) ~ :not([hidden])") && css("space-x-4").contains("calc(1rem * var(--tw-space-x-reverse))"))
        check("tailwind: static utilities", css("flex") == ".flex {\n  display: flex;\n}" && css("sr-only").contains("clip: rect(0, 0, 0, 0)"))
        check("tailwind: container uses the config screens", css("container").contains("@media (min-width: 600px)") && css("container").contains("max-width: 1200px"))
        check("tailwind: animate keyframes", css("animate-spin").contains("@keyframes spin"))
        check("tailwind: before: adds content", css("before:block").contains("content: var(--tw-content);"))
        check("tailwind: arbitrary variant", css("[&>*]:p-4").contains(".\\[\\&\\>\\*\\]\\:p-4>*") || css("[&>*]:p-4").contains("> *"))
        check("tailwind: data-[...] variant", css("data-[state=open]:block").contains("[data-state=\"open\"]"))
        check("tailwind: unknown classes are not guessed", tw.css(for: "btn") == nil && tw.css(for: "p-4x") == nil && tw.css(for: "hovr:p-4") == nil && tw.css(for: "text-nope-500") == nil)
        check("tailwind: v4-only names are not offered or resolved in v3", tw.css(for: "bg-linear-to-r") == nil && !labels(blade, "<div class=\"bg-linear§\">").contains("bg-linear-to-r") && css("bg-gradient-to-r").contains("linear-gradient(to right"))
        check("tailwind: v3 opacity utilities", css("bg-opacity-50").contains("--tw-bg-opacity: 0.5;") && labels(blade, "<div class=\"text-opac§\">").contains("text-opacity-50"))
        check("tailwind: plugin names known (typography)", tw.extraNames.contains("prose"))
        // completion
        let p4 = labels(blade, "<div class=\"p-§\">")
        check("tailwind completion: spacing scale incl. custom", p4.contains("p-4") && p4.contains("p-18") && p4.contains("p-gutter"))
        let bg = labels(blade, "<div class=\"bg-pri§\">")
        check("tailwind completion: custom colors", bg.contains("bg-primary") && bg.contains("bg-primary-dark"))
        check("tailwind completion: after variants", labels(blade, "<div class=\"md:hover:bg-pri§\">").contains("md:hover:bg-primary"))
        check("tailwind completion: variants offered", labels(blade, "<div class=\"hov§\">").contains("hover:"))
        check("tailwind completion: config screens as variants", labels(blade, "<div class=\"lg§\">").contains("lg:") && !labels(blade, "<div class=\"2xl§\">").contains("2xl:"))
        check("tailwind completion: opacity steps after slash", labels(blade, "<div class=\"bg-red-500/§\">").contains("bg-red-500/75"))
        check("tailwind completion: negative values", labels(blade, "<div class=\"-mt-§\">").contains("-mt-4"))
        check("tailwind completion: JSX className", labels(jsx, "const a = <div className=\"flex it§\">").contains("items-center"))
        check("tailwind completion: cn() call in a script", labels(jsx, "const a = cn(\"p-4\", cond && \"bg-pri§\")").contains("bg-primary"))
        check("tailwind completion: a plain string is not a class list", labels(jsx, "const a = \"bg-pri§\"").isEmpty)
        check("tailwind completion: items carry generated css lazily", {
            let it = NativeWeb.items(for: ctx(blade, "<div class=\"p-§\">")).first { $0.label == "p-4" }
            var doc = ""
            it?.resolve?({ doc = $0.documentation })
            return strip(doc).contains("padding: 1rem;")
        }())
        check("tailwind: JSX hover", hit(jsx, "const a = <div className=\"fl§ex items-center\">")?.markdown.contains("display: flex;") == true)
        check("tailwind: hover inside {{ }} literal", strip(hit(blade, "<div class=\"a {{ $x ? 'text-l§g' : '' }}\">")?.markdown).contains("font-size: 1.125rem;"))
        // memory: the whole resolved setup is small
        check("tailwind: resolved theme is small (< 400 KB)", tw.approxBytes < 400_000)
    }

    // MARK: JS config parser

    private static func configChecks() {
        func theme(_ js: String) -> NWTailwind {
            let tw = NWTailwind.makeDefault(version: 3)
            NWTailwindLoader.applyConfig(tw, text: js as NSString)
            return tw
        }
        let fn = theme("""
        import colors from 'tailwindcss/colors'
        export default {
          prefix: 'tw-',
          theme: ({ theme }) => ({
            colors: { gray: colors.slate, accent: theme('colors.blue.600') },
            extend: { spacing: { 15: '3.75rem' } },
          }),
        }
        """)
        // functional `theme` values are parsed through the arrow body; extend nested inside is not applied (documented limitation)
        check("config: prefix", fn.prefix == "tw-")
        check("config: replaced colors from a ref", fn.colors["gray-500"] == "#64748b" && fn.colors["red-500"] == nil)
        check("config: theme('colors.blue.600') call", fn.colors["accent"] == "#2563eb")
        let ts = theme("""
        import type { Config } from 'tailwindcss'
        const config: Config = {
          darkMode: ['class', '[data-mode="dark"]'],
          theme: { extend: { screens: { tablet: '640px', wide: { min: '1400px' }, print: { raw: 'print' } }, fontSize: { tiny: ['0.6rem', { lineHeight: '1rem' }] } } },
        } satisfies Config
        export default config
        """)
        check("config: TS with satisfies + array darkMode", ts.darkMode == "class" && ts.darkSelector == "[data-mode=\"dark\"]")
        check("config: extended screens and font size tuples", ts.maps["screens"]?["tablet"] == "640px" && ts.maps["screens"]?["wide"] == "1400px" && ts.maps["fontSize"]?["tiny"] == "0.6rem|1rem")
        check("config: defaults survive extend", ts.maps["screens"]?["md"] == "768px" && ts.colors["blue-500"] == "#3b82f6")
        let weird = theme("module.exports = { theme: { extend: { colors: { a: someFunction(), b: cond ? '#111' : '#222', c: '#333' } } }, plugins: [function() {}] }")
        check("config: unsupported expressions do not break the rest", weird.colors["c"] == "#333")
    }

    // MARK: Tailwind v4

    private static func v4Checks(_ fm: FileManager) {
        let root = fm.temporaryDirectory.appendingPathComponent("ce-selftest-web4-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        buildV4(root)
        defer { try? fm.removeItem(at: root) }
        let p = NWProject.shared(root: root.path)
        guard let tw = p.queue.sync(execute: { p.tailwind(near: root.appendingPathComponent("src").path) }) else { check("v4: project detected", false); return }
        func css(_ t: String) -> String { strip(tw.css(for: t) ?? "<nil>") }
        check("v4: detected from @import \"tailwindcss\"", tw.version == 4)
        check("v4: @theme color", css("bg-brand") == ".bg-brand {\n  background-color: var(--color-brand);\n}")
        check("v4: color opacity uses color-mix", css("bg-brand/50").contains("color-mix(in oklab, var(--color-brand) 50%, transparent)"))
        check("v4: any spacing multiple", css("p-13").contains("padding: calc(var(--spacing) * 13);"))
        check("v4: default palette present", css("text-red-500").contains("var(--color-red-500)"))
        check("v4: breakpoint from @theme + default", css("3xl:flex").contains("@media (width >= 120rem)") && css("md:flex").contains("@media (width >= 48rem)"))
        check("v4: radius from @theme", css("rounded-pill").contains("var(--radius-pill)"))
        check("v4: @utility", css("tab-4").contains("tab-size: 4;"))
        check("v4: @custom-variant", css("theme-dark:flex").contains("[data-theme=dark]"))
        let vars = labels(root.appendingPathComponent("src/app.css"), ".x { color: var(--§")
        check("v4: var() offers theme variables", vars.contains("--color-brand") && vars.contains("--color-red-500"))
        check("v4: @theme at-rules offered", labels(root.appendingPathComponent("src/app.css"), "@the§").contains("theme"))
        check("v4: class completion includes @theme colors", labels(root.appendingPathComponent("src/index.html"), "<div class=\"bg-bra§\">").contains("bg-brand-light"))
    }

    // MARK: gating

    private static func gatingChecks(_ root: URL, _ cssURL: URL, _ html: URL) {
        let fm = FileManager.default
        let plain = fm.temporaryDirectory.appendingPathComponent("ce-selftest-webplain-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: plain)
        put(plain, "package.json", #"{"name":"plain"}"#)
        put(plain, "index.html", "<div class=\"x\"></div>\n")
        put(plain, "style.css", ".x { color: red }\n")
        defer { try? fm.removeItem(at: plain) }
        let idx = plain.appendingPathComponent("index.html")
        check("gating: plain project has no Tailwind", NWProject.shared(root: plain.path).queue.sync { NWProject.shared(root: plain.path).tailwind(near: plain.path) } == nil)
        check("gating: plain project still gets project classes", labels(idx, "<div class=\"§\">").contains("x"))
        check("gating: plain project gets no tailwind utilities", !labels(idx, "<div class=\"p-§\">").contains("p-4"))

        let saved = NativeWeb.enabled
        NativeWeb.enabled = false
        check("gating: disabled switch -> handles() false and no items", !NativeWeb.handles(cssURL) && NativeWeb.items(for: ctx(cssURL, ".x { col§ }")).isEmpty)
        NativeWeb.enabled = saved
        check("gating: unsupported extensions are ignored", !NativeWeb.handles(root.appendingPathComponent("a.php")) && NativeWeb.handles(root.appendingPathComponent("a.blade.php")))
        // nativeOnly stops the external servers
        let savedOnly = NativeWeb.nativeOnly
        NativeWeb.nativeOnly = true
        check("gating: native-only disables html/css/tailwind servers", ["html", "css", "tailwind"].allSatisfy { !LanguageServerPrefs.isEnabled($0) } && LanguageServerPrefs.isEnabled("typescript") == (UserDefaults.standard.object(forKey: "lsp.typescript.enabled") as? Bool ?? true))
        NativeWeb.nativeOnly = savedOnly
        check("gating: native-only off keeps the servers", ["html", "css"].allSatisfy { LanguageServerPrefs.isEnabled($0) == (UserDefaults.standard.object(forKey: "lsp.\($0).enabled") as? Bool ?? true) })
        NativeWeb.trimMemory()
        check("gating: trimMemory drops caches and still answers", NWProject.shared(root: root.path).queue.sync { NWProject.shared(root: root.path).cachedIndexCount } == 0 && labels(cssURL, ".x { col§ }").contains("color"))
    }
}
