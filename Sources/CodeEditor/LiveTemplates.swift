import AppKit

/// One live template: type `abbrev`, press Tab, get `body` with `$VAR$` tab stops (see LiveTemplates.snippet).
struct LiveTemplate: Equatable {
    var abbrev: String
    var description: String
    /// php, blade, vue, vue-script, vue-template, js, ts, html, css, md; empty = everywhere.
    var scopes: [String]
    var body: String
    /// Default text of `$NAME$` variables.
    var vars: [String: String] = [:]
}

/// Live templates: built-in defaults plus the user's ~/Library/Application Support/CodeEditor/templates.json.
/// The user file is stat()ed (one cheap call) whenever templates are consulted and re-read only when it changed:
/// no watcher, no timer, nothing resident beyond the parsed list.
final class LiveTemplates: NSObject {
    static let shared = LiveTemplates()

    /// Overridable so tests never touch the real Application Support folder.
    static var fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CodeEditor/templates.json")

    private var user: [LiveTemplate] = []
    private var stamp: Date?
    private var loadedURL: URL?
    private(set) var lastError: String?

    // MARK: Lookup

    private func refresh() {
        let url = Self.fileURL
        let m = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if m == stamp, loadedURL == url { return }
        stamp = m; loadedURL = url
        user = []; lastError = nil
        guard m != nil, let data = try? Data(contentsOf: url) else { return }
        let r = Self.parse(data)
        user = r.templates; lastError = r.error
    }

    /// User templates first (they shadow defaults with the same abbreviation in an overlapping scope), then the defaults.
    func templates() -> [LiveTemplate] { refresh(); return user + Self.defaults }

    func lookup(_ abbrev: String, scopes: Set<String>) -> LiveTemplate? {
        refresh()
        for t in user + Self.defaults where t.abbrev == abbrev && Self.applies(t, scopes) { return t }
        return nil
    }

    func has(_ abbrev: String, scopes: Set<String>) -> Bool { lookup(abbrev, scopes: scopes) != nil }

    /// Cheap pre-check used by the Tab handler before it builds a completion context.
    func knows(abbrev: String) -> Bool {
        refresh()
        return user.contains { $0.abbrev == abbrev } || Self.defaultAbbrevs.contains(abbrev)
    }

    static func applies(_ t: LiveTemplate, _ scopes: Set<String>) -> Bool {
        t.scopes.isEmpty || t.scopes.contains("all") || !scopes.isDisjoint(with: t.scopes)
    }

    /// Scopes active at the caret of this file.
    static func scopes(for ctx: CompletionContext) -> Set<String> {
        let name = ctx.fileURL.lastPathComponent.lowercased()
        let ext = ctx.fileExtension.lowercased()
        func region() -> CompletionLex.Region { CompletionLex.info(ctx).region }
        switch ext {
        case "php", "phtml":
            let blade = name.hasSuffix(".blade.php")
            switch region() {
            case .php: return blade ? ["blade", "php"] : ["php"]
            case .bladeExpr: return ["blade"]
            case .html: return blade ? ["blade", "html"] : ["html"]
            case .js: return blade ? ["blade", "js"] : ["js"]
            case .css: return blade ? ["blade", "css"] : ["css"]
            }
        case "vue":
            switch region() {
            case .js: return ["vue", "vue-script", "js", "ts"]
            case .css: return ["vue", "css"]
            default: return ["vue", "vue-template", "html"]
            }
        case "js", "jsx", "mjs", "cjs": return ["js"]
        case "ts", "tsx", "mts", "cts": return ["ts", "js"]
        case "html", "htm":
            switch region() {
            case .js: return ["js"]
            case .css: return ["css"]
            default: return ["html"]
            }
        case "css", "scss", "less", "sass": return ["css"]
        case "md", "markdown": return ["md"]
        default: return []
        }
    }

    // MARK: User file

    static func parse(_ data: Data) -> (templates: [LiveTemplate], error: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return ([], "templates.json is not valid JSON") }
        let list: [[String: Any]]
        if let a = json as? [[String: Any]] { list = a }
        else if let o = json as? [String: Any], let a = o["templates"] as? [[String: Any]] { list = a }
        else { return ([], "templates.json: expected an array or {\"templates\": [...]}") }
        var out: [LiveTemplate] = []
        var skipped = 0
        for d in list {
            let abbrev = ((d["abbrev"] ?? d["abbreviation"]) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let body: String
            if let s = d["body"] as? String { body = s }
            else if let lines = d["body"] as? [String] { body = lines.joined(separator: "\n") }
            else { skipped += 1; continue }
            guard !abbrev.isEmpty, !abbrev.contains(where: { $0.isWhitespace }) else { skipped += 1; continue }
            var scopes: [String] = []
            if let s = d["scopes"] as? [String] { scopes = s } else if let s = d["scopes"] as? String { scopes = [s] }
            else if let s = d["scope"] as? String { scopes = [s] }
            scopes = scopes.map { $0.lowercased() }
            let vars = (d["vars"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
            out.append(LiveTemplate(abbrev: abbrev, description: (d["description"] as? String) ?? "", scopes: scopes, body: body, vars: vars))
        }
        return (out, skipped > 0 ? "templates.json: \(skipped) entr\(skipped == 1 ? "y" : "ies") skipped (need abbrev and body)" : nil)
    }

    private static let starterFile = """
    {
      "_help": "Live templates. abbrev + Tab expands body. $NAME$ is a tab stop (default text in vars), $END$ is the final caret, $CLASS$ / $FILE_NAME$ / $DATE$ / $YEAR$ are filled in. scopes: php, blade, vue, vue-script, vue-template, js, ts, html, css, md (empty = everywhere). Abbreviations are letters, digits and _. A user template shadows a built-in one with the same abbrev.",
      "templates": []
    }

    """

    /// Menu: Code > Edit Live Templates... Creates a starter file when none exists, then opens it in the editor.
    @objc func openTemplatesFile(_ sender: Any?) {
        let url = Self.fileURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Self.starterFile.write(to: url, atomically: true, encoding: .utf8)
        }
        (NSApp.delegate as? AppDelegate)?.active?.open(url)
    }

    // MARK: Expansion

    private static let variable = try! NSRegularExpression(pattern: "^\\$([A-Z][A-Z0-9_]*)\\$")

    private static func escape(_ s: String) -> String {
        var o = ""
        for ch in s { if ch == "\\" || ch == "$" || ch == "}" { o.append("\\") }; o.append(ch) }
        return o
    }

    /// LSP snippet text for the existing tab-stop machinery (SnippetParser / CompletionController.insert).
    /// `$NAME$` becomes `${n:default}` in order of first appearance (later occurrences repeat the default text);
    /// `$END$` is `$0`, `$SELECTION$` is empty, `$CLASS$`/`$FILE_NAME$`/`$DATE$`/`$YEAR$` are expanded now; any other `$` is literal.
    static func snippet(_ t: LiveTemplate, fileURL: URL?, now: Date = Date()) -> String {
        let ns = t.body as NSString
        var out = ""
        var index: [String: Int] = [:]
        var i = 0
        let base = fileURL.map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ".blade", with: "") } ?? ""
        func formatted(_ f: String) -> String {
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = f
            return df.string(from: now)
        }
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 36, let m = variable.firstMatch(in: t.body, range: NSRange(location: i, length: ns.length - i)) {
                let name = ns.substring(with: m.range(at: 1))
                i += m.range.length
                switch name {
                case "END": out += "$0"
                case "SELECTION": break
                case "CLASS", "FILE_NAME": out += escape(base)
                case "DATE": out += escape(formatted("yyyy-MM-dd"))
                case "YEAR": out += escape(formatted("yyyy"))
                default:
                    let def = escape(t.vars[name] ?? "")
                    if index[name] == nil {
                        index[name] = index.count + 1
                        out += "${\(index[name]!):\(def)}"
                    } else { out += def }
                }
                continue
            }
            let s = ns.substring(with: NSRange(location: i, length: 1))
            if c == 36 || c == 92 || c == 125 { out += "\\" }
            out += s
            i += 1
        }
        return out
    }

    /// Completion-popup item for a template.
    static func item(_ t: LiveTemplate, fileURL: URL?, range: NSRange?) -> CompletionItem {
        var it = CompletionItem(label: t.abbrev, insertText: snippet(t, fileURL: fileURL), kind: .template)
        it.detail = t.description.isEmpty ? "live template" : t.description
        it.documentation = "Live template `\(t.abbrev)` (Tab expands)\n\n```\n\(t.body)\n```"
        it.isSnippet = true
        it.sortText = "0" + t.abbrev.lowercased()
        it.replaceRange = range
        return it
    }
}

/// Offers live templates in the completion list (distinct icon); expansion on Tab lives in CompletionController.
enum LiveTemplateCompletion {
    static let extensions = ["php", "phtml", "js", "jsx", "ts", "tsx", "mjs", "cjs", "mts", "cts", "vue", "html", "htm", "css", "scss", "less", "sass", "md", "markdown"]

    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        guard !ctx.prefix.isEmpty else { return [] }
        let ext = ctx.fileExtension.lowercased()
        if ext != "md", ext != "markdown", CompletionLex.state(ctx) != .code { return [] }
        let ns = ctx.text as NSString
        let p = ctx.prefixRange.location
        if p > 0, !LiveTemplateCompletion.mayExpand(after: ns.character(at: p - 1)) { return [] }
        let scopes = LiveTemplates.scopes(for: ctx)
        let q = ctx.prefix.lowercased()
        let qb = Array(q.utf8)
        var seen = Set<String>()
        var out: [CompletionItem] = []
        for t in LiveTemplates.shared.templates() where LiveTemplates.applies(t, scopes) && seen.insert(t.abbrev).inserted {
            let l = t.abbrev.lowercased()
            guard l.hasPrefix(q) || CompletionLex.subsequence(qb, in: l) else { continue }
            out.append(LiveTemplates.item(t, fileURL: ctx.fileURL, range: nil))
        }
        return out
    }

    /// Characters that make the following word a member / tag / variable instead of a free-standing abbreviation.
    static func mayExpand(after c: unichar) -> Bool {
        !"$.>:</@-#\\".utf16.contains(c) && !CompletionLex.isIdent(c)
    }
}

// MARK: - Default templates

extension LiveTemplates {
    static let defaultAbbrevs: Set<String> = Set(defaults.map(\.abbrev))

    private static func t(_ abbrev: String, _ desc: String, _ scopes: [String], _ body: String, _ vars: [String: String] = [:]) -> LiveTemplate {
        LiveTemplate(abbrev: abbrev, description: desc, scopes: scopes, body: body, vars: vars)
    }

    static let defaults: [LiveTemplate] = [
        // PHP / Laravel
        t("rt", "Route::get(...)->name()", ["php"], "Route::$METHOD$('$URI$', [$CONTROLLER$::class, '$ACTION$'])->name('$NAME$');$END$",
          ["METHOD": "get", "URI": "/", "CONTROLLER": "Controller", "ACTION": "index", "NAME": "name"]),
        t("rtg", "Route group", ["php"], "Route::prefix('$PREFIX$')->middleware('$MIDDLEWARE$')->group(function () {\n\t$END$\n});",
          ["PREFIX": "prefix", "MIDDLEWARE": "auth"]),
        t("rtr", "Route::resource", ["php"], "Route::resource('$NAME$', $CONTROLLER$::class);$END$", ["NAME": "posts", "CONTROLLER": "PostController"]),
        t("fn", "arrow function", ["php"], "fn($$ARG$) => $END$", ["ARG": "x"]),
        t("fun", "function", ["php"], "function $NAME$($PARAMS$)\n{\n\t$END$\n}", ["NAME": "name"]),
        t("pubf", "public function", ["php"], "public function $NAME$($PARAMS$)\n{\n\t$END$\n}", ["NAME": "name"]),
        t("prof", "protected function", ["php"], "protected function $NAME$($PARAMS$)\n{\n\t$END$\n}", ["NAME": "name"]),
        t("prif", "private function", ["php"], "private function $NAME$($PARAMS$)\n{\n\t$END$\n}", ["NAME": "name"]),
        t("pubsf", "public static function", ["php"], "public static function $NAME$($PARAMS$)\n{\n\t$END$\n}", ["NAME": "name"]),
        t("construct", "constructor", ["php"], "public function __construct($PARAMS$)\n{\n\t$END$\n}"),
        t("foreach", "foreach loop", ["php"], "foreach ($$ITEMS$ as $$ITEM$) {\n\t$END$\n}", ["ITEMS": "items", "ITEM": "item"]),
        t("foreachk", "foreach with key", ["php"], "foreach ($$ITEMS$ as $$KEY$ => $$VALUE$) {\n\t$END$\n}", ["ITEMS": "items", "KEY": "key", "VALUE": "value"]),
        t("dd", "dd()", ["php"], "dd($$VAR$);$END$", ["VAR": "var"]),
        t("dump", "dump()", ["php"], "dump($$VAR$);$END$", ["VAR": "var"]),
        t("logi", "Log::info", ["php"], "Log::info('$MESSAGE$', [$END$]);", ["MESSAGE": "message"]),
        t("ctrl", "Laravel controller class", ["php"],
          "<?php\n\nnamespace App\\Http\\Controllers;\n\nuse Illuminate\\Http\\Request;\n\nclass $CLASS$ extends Controller\n{\n\tpublic function index()\n\t{\n\t\t$END$\n\t}\n}\n"),
        t("model", "Eloquent model class", ["php"],
          "<?php\n\nnamespace App\\Models;\n\nuse Illuminate\\Database\\Eloquent\\Model;\n\nclass $CLASS$ extends Model\n{\n\tprotected $$fillable = [$END$];\n}\n"),
        t("hasmany", "hasMany relation", ["php"], "public function $NAME$()\n{\n\treturn $$this->hasMany($MODEL$::class);\n}$END$", ["NAME": "items", "MODEL": "Item"]),
        t("belongsto", "belongsTo relation", ["php"], "public function $NAME$()\n{\n\treturn $$this->belongsTo($MODEL$::class);\n}$END$", ["NAME": "user", "MODEL": "User"]),
        t("scope", "Eloquent query scope", ["php"],
          "public function scope$NAME$($$query)\n{\n\treturn $$query->where('$COLUMN$', $VALUE$);\n}$END$", ["NAME": "Active", "COLUMN": "active", "VALUE": "true"]),
        t("mig", "Schema::create migration body", ["php"],
          "Schema::create('$TABLE$', function (Blueprint $$table) {\n\t$$table->id();\n\t$END$\n\t$$table->timestamps();\n});", ["TABLE": "table"]),
        t("val", "validate request", ["php"], "$$request->validate([\n\t'$FIELD$' => '$RULES$',\n]);$END$", ["FIELD": "name", "RULES": "required|string"]),
        t("resp", "JSON response", ["php"], "return response()->json($DATA$, $STATUS$);$END$", ["DATA": "[]", "STATUS": "200"]),
        t("pest", "Pest test", ["php"], "it('$DESCRIPTION$', function () {\n\t$END$\n});", ["DESCRIPTION": "does something"]),
        t("tm", "PHPUnit test method", ["php"], "public function test_$NAME$(): void\n{\n\t$END$\n}", ["NAME": "it_works"]),
        t("if", "if block", ["php"], "if ($CONDITION$) {\n\t$END$\n}", ["CONDITION": "$condition"]),
        t("ife", "if / else", ["php"], "if ($CONDITION$) {\n\t$END$\n} else {\n\t\n}", ["CONDITION": "$condition"]),
        t("elif", "elseif", ["php"], "elseif ($CONDITION$) {\n\t$END$\n}", ["CONDITION": "$condition"]),
        t("for", "for loop", ["php"], "for ($$I$ = 0; $$I$ < $COUNT$; $$I$++) {\n\t$END$\n}", ["I": "i", "COUNT": "$count"]),
        t("while", "while loop", ["php"], "while ($CONDITION$) {\n\t$END$\n}", ["CONDITION": "$condition"]),
        t("sw", "switch", ["php"], "switch ($SUBJECT$) {\n\tcase $VALUE$:\n\t\t$END$\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}", ["SUBJECT": "$value", "VALUE": "1"]),
        t("try", "try / catch", ["php"], "try {\n\t$END$\n} catch (\\$EXCEPTION$ $$e) {\n\t\n}", ["EXCEPTION": "Exception"]),
        t("cls", "class", ["php"], "class $CLASS$\n{\n\t$END$\n}"),
        t("iface", "interface", ["php"], "interface $NAME$\n{\n\t$END$\n}", ["NAME": "Name"]),
        t("trait", "trait", ["php"], "trait $NAME$\n{\n\t$END$\n}", ["NAME": "Name"]),
        t("enum", "backed enum", ["php"], "enum $NAME$: string\n{\n\tcase $CASE$ = '$VALUE$';\n}", ["NAME": "Status", "CASE": "Active", "VALUE": "active"]),
        t("pubp", "public property", ["php"], "public $TYPE$ $$NAME$;$END$", ["TYPE": "string", "NAME": "name"]),
        t("prop", "private property", ["php"], "private $TYPE$ $$NAME$;$END$", ["TYPE": "string", "NAME": "name"]),
        t("inv", "__invoke", ["php"], "public function __invoke($PARAMS$)\n{\n\t$END$\n}"),
        t("get", "getter", ["php"], "public function get$NAME$(): $TYPE$\n{\n\treturn $$this->$PROP$;\n}", ["NAME": "Name", "TYPE": "string", "PROP": "name"]),
        t("set", "fluent setter", ["php"], "public function set$NAME$($TYPE$ $$$PROP$): static\n{\n\t$$this->$PROP$ = $$$PROP$;\n\n\treturn $$this;\n}", ["NAME": "Name", "TYPE": "string", "PROP": "name"]),
        t("strict", "declare strict_types", ["php"], "declare(strict_types=1);$END$"),
        // Blade
        t("bfe", "@foreach", ["blade"], "@foreach ($$ITEMS$ as $$ITEM$)\n\t$END$\n@endforeach", ["ITEMS": "items", "ITEM": "item"]),
        t("bforelse", "@forelse", ["blade"], "@forelse ($$ITEMS$ as $$ITEM$)\n\t$END$\n@empty\n\t\n@endforelse", ["ITEMS": "items", "ITEM": "item"]),
        t("bif", "@if", ["blade"], "@if ($CONDITION$)\n\t$END$\n@endif", ["CONDITION": "$condition"]),
        t("bifelse", "@if / @else", ["blade"], "@if ($CONDITION$)\n\t$END$\n@else\n\t\n@endif", ["CONDITION": "$condition"]),
        t("bext", "@extends", ["blade"], "@extends('$LAYOUT$')\n\n@section('$SECTION$')\n\t$END$\n@endsection\n", ["LAYOUT": "layouts.app", "SECTION": "content"]),
        t("bsec", "@section", ["blade"], "@section('$NAME$')\n\t$END$\n@endsection", ["NAME": "content"]),
        t("binc", "@include", ["blade"], "@include('$VIEW$')$END$", ["VIEW": "partials.name"]),
        t("bcomp", "<x-component>", ["blade"], "<x-$NAME$ $ATTRS$>\n\t$END$\n</x-$NAME$>", ["NAME": "component"]),
        t("bphp", "@php block", ["blade"], "@php\n\t$END$\n@endphp"),
        t("bauth", "@auth", ["blade"], "@auth\n\t$END$\n@endauth"),
        // Vue
        t("vsfc", "Vue SFC (script setup)", ["vue"], "<script setup>\n$END$\n</script>\n\n<template>\n\t<div>\n\t\t\n\t</div>\n</template>\n"),
        t("vsfcts", "Vue SFC (TypeScript)", ["vue"], "<script setup lang=\"ts\">\n$END$\n</script>\n\n<template>\n\t<div>\n\t\t\n\t</div>\n</template>\n"),
        t("ref", "ref()", ["vue-script"], "const $NAME$ = ref($VALUE$)$END$", ["NAME": "value", "VALUE": ""]),
        t("computed", "computed()", ["vue-script"], "const $NAME$ = computed(() => {\n\treturn $END$\n})", ["NAME": "value"]),
        t("watch", "watch()", ["vue-script"], "watch($SOURCE$, ($NEW$, $OLD$) => {\n\t$END$\n})", ["SOURCE": "source", "NEW": "value", "OLD": "oldValue"]),
        t("onm", "onMounted()", ["vue-script"], "onMounted(() => {\n\t$END$\n})"),
        t("props", "defineProps()", ["vue-script"], "const props = defineProps({\n\t$END$\n})"),
        t("emit", "defineEmits()", ["vue-script"], "const emit = defineEmits(['$EVENT$'])$END$", ["EVENT": "change"]),
        t("vfor", "v-for element", ["vue-template"], "<$TAG$ v-for=\"$ITEM$ in $ITEMS$\" :key=\"$ITEM$.id\">\n\t$END$\n</$TAG$>", ["TAG": "li", "ITEM": "item", "ITEMS": "items"]),
        t("vif", "v-if element", ["vue-template"], "<$TAG$ v-if=\"$CONDITION$\">\n\t$END$\n</$TAG$>", ["TAG": "div", "CONDITION": "condition"]),
        // JS / TS
        t("clg", "console.log", ["js", "ts"], "console.log($END$)"),
        t("af", "arrow function const", ["js", "ts"], "const $NAME$ = ($PARAMS$) => {\n\t$END$\n}", ["NAME": "name"]),
        t("afn", "async function", ["js", "ts"], "async function $NAME$($PARAMS$) {\n\t$END$\n}", ["NAME": "name"]),
        t("imp", "import", ["js", "ts"], "import $NAME$ from '$MODULE$'$END$", ["NAME": "name", "MODULE": "module"]),
        t("impn", "import { }", ["js", "ts"], "import { $NAME$ } from '$MODULE$'$END$", ["MODULE": "module"]),
        t("forof", "for...of", ["js", "ts"], "for (const $ITEM$ of $ITEMS$) {\n\t$END$\n}", ["ITEM": "item", "ITEMS": "items"]),
        t("tcatch", "try / catch", ["js", "ts"], "try {\n\t$END$\n} catch ($ERR$) {\n\t\n}", ["ERR": "error"]),
        // HTML / CSS / Markdown
        t("lnk", "stylesheet link", ["html", "blade"], "<link rel=\"stylesheet\" href=\"$HREF$\">$END$", ["HREF": "style.css"]),
        t("scr", "script tag", ["html", "blade"], "<script src=\"$SRC$\"></script>$END$", ["SRC": "app.js"]),
        t("mq", "media query", ["css"], "@media (min-width: $WIDTH$) {\n\t$END$\n}", ["WIDTH": "768px"]),
        t("flexc", "flex centre", ["css"], "display: flex;\nalign-items: center;\njustify-content: center;$END$"),
        t("code", "fenced code block", ["md"], "```$LANG$\n$END$\n```", ["LANG": ""]),
        t("link", "link", ["md"], "[$TEXT$]($URL$)$END$", ["TEXT": "text", "URL": "https://"]),
        t("todo", "task item", ["md"], "- [ ] $END$"),
    ]
}
