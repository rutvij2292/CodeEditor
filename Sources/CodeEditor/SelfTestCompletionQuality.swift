import AppKit

/// Headless checks for the completion pipeline quality work: ranking (CompletionRank), frecency (CompletionHistory), popularity,
/// call snippets with parameter placeholders, Laravel validation rules / casts / named arguments / modules (FastTierRules).
enum SelfTestCompletionQuality {
    private static func put(_ root: URL, _ rel: String, _ text: String) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    private static func item(_ label: String, _ kind: CompletionKind = .method, sort: String? = nil, priority: Int = -1, detail: String = "") -> CompletionItem {
        var it = CI.make(label, kind, detail: detail, sort: sort)
        it.priority = priority
        return it
    }

    /// Ranks `items` for the text before the `|` caret marker.
    private static func rank(_ items: [CompletionItem], _ text: String, context: CompletionRanker.Context = .empty) -> [String] {
        let caret = (text as NSString).range(of: "|").location
        let clean = text.replacingOccurrences(of: "|", with: "")
        let o = CompletionRanker.rank(results: [(items, false)], text: clean as NSString, caret: caret, anchor: caret, context: context)
        return o.ranked.map { $0.item.label }
    }

    private static func fast(_ root: URL, _ rel: String, _ text: String, manual: Bool = false) -> [CompletionItem] {
        let caret = (text as NSString).range(of: "§").location
        let clean = text.replacingOccurrences(of: "§", with: "")
        let ns = clean as NSString
        var s = caret
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        let url = root.appendingPathComponent(rel)
        CompletionLex.resetCache()
        let ctx = CompletionContext(text: clean, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil,
                                    isManual: manual, prefixRange: NSRange(location: s, length: caret - s))
        return FastTier.items(for: ctx)
    }

    static func run(w: ProjectWindow) {
        rankingChecks()
        snippetChecks(w: w)
        laravelChecks()
    }

    // MARK: Ranking

    private static func rankingChecks() {
        let c = SelfTest.check
        // match classes
        let order = rank([item("createFromFormat"), item("create"), item("Create"), item("recreate"), item("c_r_e_a")], "$x->cre|")
        c("rank: case-sensitive prefix, then case-insensitive prefix, then hump, then fuzzy", order == ["create", "createFromFormat", "Create", "c_r_e_a", "recreate"])
        c("rank: camel hump `cff` finds createFromFormat ahead of plain fuzzy", rank([item("cxfxfx"), item("createFromFormat")], "cff|").first == "createFromFormat")
        c("rank: hump matches a word start (`format` -> createFromFormat) above a scattered subsequence", rank([item("fxoxrxmxaxt"), item("createFromFormat")], "format|").first == "createFromFormat")
        c("rank: tailwind-style `bgr` -> bg-red-500", rank([item("border-gray-300"), item("bg-red-500")], "bgr|").first == "bg-red-500")
        // words of the file
        var word = item("subject", .text, sort: "~subject")
        word.priority = -1
        let withWord = rank([word, item("subDays"), item("sub")], "$d->sub|")
        c("rank: a word of the file never beats a real symbol with the same case-sensitive prefix", withWord.first != "subject" && withWord.contains("subject"))
        c("rank: a word identical to the typed text is not offered when a real symbol matches", !rank([item("sub", .text, sort: "~sub"), item("subDays")], "x sub|").contains("sub"))
        c("rank: a word with the same name as a real symbol is dropped (no duplicate)", rank([item("subject", .text, sort: "~subject"), item("subject", .property)], "$a->sub|").filter { $0 == "subject" }.count == 1)
        // familiarity
        var ctx = CompletionRanker.Context()
        ctx.docCounts = ["xzebra": 5, "xapple": 1]
        let fam2 = rank([item("xalpha"), item("xapple"), item("xzebra")], "x|", context: ctx)
        c("rank: more uses first, then one use, then unused", fam2 == ["xzebra", "xapple", "xalpha"])
        ctx.docCounts = [:]
        ctx.history = { $0 == "xalpha" ? 2 : 0 }
        c("rank: accepted-before (frecency) lifts a name", rank([item("xalpha"), item("xapple"), item("xzebra")], "x|", context: ctx).first == "xalpha")
        // provider tiers
        let tiered = rank([item("zoo", sort: "1zoo", priority: 12), item("zed", priority: 0), item("zap", priority: 4)], "z|")
        c("rank: provider priority orders equal matches (own before inherited before magic)", tiered == ["zed", "zap", "zoo"])
        c("rank: sortText leading digit is a tier when no priority is set", rank([item("zb", sort: "2zb"), item("za", sort: "1za"), item("zc", sort: "~zc")], "z|") == ["za", "zb", "zc"])
        // popularity
        ctx = CompletionRanker.Context()
        ctx.popularity = CompletionPopularity.table(ext: "php", blade: false)
        let pop = rank([item("str_word_count", .function), item("str_replace", .function), item("strcmp", .function)], "st|", context: ctx)
        c("rank: popularity prior puts str_replace first for `st`", pop.first == "str_replace")
        c("rank: popularity table is tiny and per file type", CompletionPopularity.table(ext: "php", blade: false).count < 800 && CompletionPopularity.table(ext: "xyz", blade: false).isEmpty
          && CompletionPopularity.table(ext: "php", blade: true)["endforeach"] != nil)
        // determinism / dedupe across providers
        let a = [item("foo"), item("fob"), item("fox")]
        c("rank: deterministic for the same input", rank(a, "f|") == rank(a, "f|") && rank(a, "f|") == rank(a.reversed(), "f|"))
        let dup = CompletionRanker.rank(results: [([item("same", .method, priority: 9)], false), ([item("same", .method, priority: 1)], false)], text: "sa" as NSString, caret: 2, anchor: 0)
        c("rank: the same symbol from two providers appears once, with the better tier", dup.ranked.count == 1 && dup.ranked[0].item.priority == 1)
        // doc stats
        let docText = "use App\\Models\\Invoice;\n$a = new Invoice();\n$b = new Invoice(); Inv" as NSString
        let counts = CompletionRanker.docCounts(docText, caret: docText.length)
        c("rank: docCounts counts identifiers and skips the token under the caret", counts["Invoice"] == 3 && counts["Inv"] == nil && counts["Models"] == 1)
        // refilter latency
        var big: [CompletionItem] = []
        for i in 0..<3000 { big.append(item("symbol\(i)Name\(i % 17)", .text, sort: "~")) }
        for i in 0..<1500 { big.append(item("getSomething\(i)", .method)) }
        let t0 = DispatchTime.now()
        for _ in 0..<5 { _ = CompletionRanker.rank(results: [(big, false)], text: "$x->ge" as NSString, caret: 6, anchor: 4, context: ctx) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 5e6
        c("rank: refilter of 4500 candidates under 25 ms in this (debug) build", ms < 25)
        // history
        let h = CompletionHistory.shared
        h.record("zzUniqueName", project: "/tmp/selftest-proj")
        c("history: one accept = level 1, three = level 2, other project = 0",
          h.level("zzUniqueName", project: "/tmp/selftest-proj") == 1 && h.level("zzUniqueName", project: "/tmp/other") == 0)
        h.record("zzUniqueName", project: "/tmp/selftest-proj"); h.record("zzUniqueName", project: "/tmp/selftest-proj")
        c("history: repeated accepts raise the level", h.level("zzUniqueName", project: "/tmp/selftest-proj") == 2)
        for i in 0..<400 { h.record("name\(i)", project: "/tmp/selftest-proj") }
        var kept = 0
        for i in 0..<400 where h.level("name\(i)", project: "/tmp/selftest-proj") > 0 { kept += 1 }
        c("history: bounded per project (<= 150 names)", kept <= 150)
        for i in 0..<10 { h.record("n", project: "/tmp/selftest-p\(i)") }
        c("history: bounded number of projects", h.level("n", project: "/tmp/selftest-p0") == 0 && h.level("n", project: "/tmp/selftest-p9") >= 1)
    }

    // MARK: Snippets

    private static func snippetChecks(w: ProjectWindow) {
        let c = SelfTest.check
        let s1 = CI.callInsert("str_replace", params: "array|string $search, array|string $replace, string|array $subject, &$count = null")
        let p1 = SnippetParser.parse(s1)
        c("snippet: required PHP parameters become named placeholders", p1.text == "str_replace($search, $replace, $subject)" && p1.stops.count == 4)
        c("snippet: first placeholder selects the first parameter name", (p1.text as NSString).substring(with: p1.stops[0].range) == "$search")
        c("snippet: no required parameter leaves the caret inside the parentheses", SnippetParser.parse(CI.callInsert("count", params: "$x = 1, ...$rest")).text == "count()")
        c("snippet: JS parameters", SnippetParser.parse(CI.callInsert("setTimeout", params: "handler, timeout")).text == "setTimeout(handler, timeout)")
        c("snippet: TS typed parameter keeps the name only", SnippetParser.parse(CI.callInsert("f", params: "name: string, n?: number")).text == "f(name)")
        let m = CI.member("array_map(callback, array, ...arrays)|array")
        c("snippet: builtin entry inserts callback, array placeholders", SnippetParser.parse(m.insertText).text == "array_map(callback, array)")
        // accepted in a real tab, and when the user already typed the parentheses
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-cq-\(getpid())")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.php")
        try? "<?php\nstr_re\n".write(to: file, atomically: true, encoding: .utf8)
        w.open(file)
        guard let tab = w.current, tab.url.standardizedFileURL == file.standardizedFileURL, let cc = CompletionSystem.controller(for: tab) else {
            c("snippet: editor and controller available", false); return
        }
        let tv = tab.textView
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).range(of: "str_re").upperBound, length: 0))
        var it = CI.make("str_replace", .function, insert: CI.callInsert("str_replace", params: "array|string $search, array|string $replace, string|array $subject"), snippet: true)
        it.replaceRange = NSRange(location: 6, length: 6)
        cc.insert(it)
        c("snippet: accepting a call inserts the placeholders", tv.string == "<?php\nstr_replace($search, $replace, $subject)\n")
        c("snippet: first parameter is selected", (tv.string as NSString).substring(with: tv.selectedRange()) == "$search")
        cc.endSession()
        tv.string = "<?php\nstr_re($a)\n"
        tv.setSelectedRange(NSRange(location: 12, length: 0))
        var it2 = it; it2.replaceRange = NSRange(location: 6, length: 6)
        cc.insert(it2)
        c("snippet: typed parentheses are kept, no second pair", tv.string == "<?php\nstr_replace($a)\n")
        tv.string = ""
    }

    // MARK: Laravel

    private static func laravelChecks() {
        let c = SelfTest.check
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-cq-laravel-\(getpid())")
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        put(root, "artisan", "#!/usr/bin/env php\n")
        put(root, "composer.json", #"{"require":{"laravel/framework":"^11"},"autoload":{"psr-4":{"App\\":"app/"}}}"#)
        put(root, "database/migrations/2024_01_01_000000_create_posts_table.php", """
        <?php
        return new class extends Migration {
            public function up(): void {
                Schema::create('posts', function (Blueprint $table) {
                    $table->id();
                    $table->string('title')->nullable();
                    $table->timestamps();
                });
                Schema::create('users', function (Blueprint $table) {
                    $table->id();
                    $table->string('email');
                    $table->timestamps();
                });
            }
        };
        """)
        put(root, "vendor/composer/autoload_psr4.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'App\\\\' => array($baseDir . '/app'),\n);\n")
        put(root, "routes/web.php", "<?php\nRoute::get('/', fn () => 1)->name('home');\n")
        put(root, "Modules/Blog/routes/web.php", "<?php\nRoute::get('/blog', fn () => 1)->name('blog.index');\nRoute::post('/blog', fn () => 1)->name('blog.store');\n")
        put(root, "Modules/Blog/resources/views/post/show.blade.php", "x")
        put(root, "Modules/Blog/config/config.php", "<?php\nreturn ['per_page' => 15, 'cache' => ['ttl' => 60]];\n")
        put(root, "resources/views/welcome.blade.php", "x")
        put(root, "app/Mailer.php", "<?php\nnamespace App;\nclass Mailer {\n    public function send(string $to, string $subject, array $headers = []) {}\n}\n")
        FastProject.shared(root: root).markDirty()
        let ctrl = "app/Http/Requests/PostRequest.php"
        let head = "<?php\nnamespace App\\Http\\Requests;\nclass PostRequest {\n    public function rules(): array\n    {\n        return [\n"

        // validation rules
        func labels(_ items: [CompletionItem]) -> [String] { items.map(\.label) }
        let r1 = fast(root, ctrl, head + "            'title' => 'required|st§")
        c("rules: offered after `=> '`", labels(r1).contains("string") && labels(r1).contains("required"))
        let r1b = fast(root, ctrl, head + "            'title' => 'required|ma§")
        c("rules: replace range covers only the token after the last pipe", r1b.first?.replaceRange.map { $0.length == 2 } ?? false)
        c("rules: most used rules first", labels(r1).prefix(3) == ["required", "nullable", "string"])
        let r2 = fast(root, ctrl, head + "            'email' => ['required', 'em§")
        c("rules: array form `['required', 'em`", labels(r2).contains("email"))
        c("rules: not offered for the array KEY", fast(root, ctrl, head + "            're§' => 'required',\n").filter { $0.kind == .keyword }.isEmpty)
        let r3 = fast(root, ctrl, head + "            'user_id' => 'exists:§")
        c("rules: exists: lists the schema tables", Set(labels(r3)) == ["posts", "users"])
        let r4 = fast(root, ctrl, head + "            'user_id' => 'required|exists:users,§")
        c("rules: exists:table, lists that table's columns", labels(r4).contains("email") && !labels(r4).contains("title"))
        let r5 = fast(root, ctrl, head + "            'email' => 'unique:users,em§")
        c("rules: unique:table,col completes columns", labels(r5).contains("email"))
        let casts = fast(root, "app/Models/Post.php", "<?php\nnamespace App\\Models;\nclass Post {\n    protected $casts = [\n        'at' => 'date§")
        c("casts: cast types after `$casts = ['x' => '`", labels(casts).contains("datetime") && labels(casts).contains("boolean"))
        let casts2 = fast(root, "app/Models/Post.php", "<?php\nnamespace App\\Models;\nclass Post {\n    protected function casts(): array\n    {\n        return [\n            'at' => 'da§")
        c("casts: casts() method form", labels(casts2).contains("datetime"))
        let notRules = fast(root, "app/Services/S.php", "<?php\nclass S {\n    function go() {\n        $x = ['a' => 'req§")
        c("rules: not offered in unrelated array literals", notRules.filter { $0.kind == .keyword }.isEmpty)
        let validateCall = fast(root, "app/Http/Controllers/C.php", "<?php\nclass C {\n    function store($request) {\n        $request->validate(['name' => 'req§")
        c("rules: inside ->validate([...])", labels(validateCall).contains("required"))

        // named arguments
        let namedHead = "<?php\nnamespace App\\Http;\nuse App\\Mailer;\nfunction notify(string $message, int $code = 0, ?string $channel = null): void {}\n"
        let n1 = fast(root, "app/a.php", namedHead + "notify(me§")
        c("named args: `notify(me` offers `message:`", labels(n1).first == "message:")
        c("named args: insert text carries the colon and a space", n1.first?.insertText == "message: ")
        let n2 = fast(root, "app/a.php", namedHead + "notify('x', §", manual: true)
        c("named args: positional first argument already supplied", !labels(n2).contains("message:") && labels(n2).contains("code:") && labels(n2).contains("channel:"))
        let n3 = fast(root, "app/a.php", namedHead + "notify(message: 'x', co§")
        c("named args: after a named argument", labels(n3).first == "code:" && !labels(n3).contains("message:"))
        let n4 = fast(root, "app/a.php", namedHead + "notify(['a', me§")
        c("named args: not inside an array literal argument", !labels(n4).contains("message:"))
        let n5 = fast(root, "app/a.php", namedHead + "class T { function go(Mailer $m) { $m->send(su§")
        c("named args: method of a typed parameter", labels(n5).contains("subject:"))
        let n6 = fast(root, "app/a.php", namedHead + "class T { function go() { $m = new Mailer(); $m->send(he§")
        c("named args: instance method via variable", labels(n6).contains("headers:"))
        c("named args: no match when not at an argument start", !labels(fast(root, "app/a.php", namedHead + "notify($x . me§")).contains("message:"))

        // laravel modules
        let route = fast(root, ctrl, head.replacingOccurrences(of: "return [\n", with: "") + "        return route('bl§")
        c("modules: route names from Modules/*/routes", labels(route).contains("blog.index") && labels(route).contains("blog.store"))
        let view = fast(root, ctrl, head + "        return view('po§")
        c("modules: views from Modules/*/resources/views (namespaced and plain)", labels(view).contains("blog::post.show") && labels(view).contains("post.show"))
        let cfg = fast(root, ctrl, head + "        return config('bl§")
        c("modules: config keys under the lower-case module name", labels(cfg).contains("blog.per_page") && labels(cfg).contains("blog.cache.ttl"))

        // column fallback
        let col = fast(root, "app/Services/Q.php", "<?php\nclass Q {\n    function go($q) {\n        return $q->where('em§")
        c("columns: unknown receiver offers every schema column", labels(col).contains("email") && labels(col).contains("title"))
        let colId = fast(root, "app/Services/Q.php", "<?php\nclass Q {\n    function go($q) {\n        return $q->where('§")
        c("columns: most widespread columns first (id before title)", labels(colId).first.map { ["id", "created_at", "updated_at"].contains($0) } ?? false)
    }
}
