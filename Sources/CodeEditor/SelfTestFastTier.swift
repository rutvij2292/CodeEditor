import AppKit

/// Headless checks for the native fast completion tier (FastTier*.swift) against a temp Laravel-like fixture.
/// `CE_FASTTIER_BENCH=/path/to/laravel/app` additionally prints counts / latency / memory for a real project (read-only).
extension SelfTest {
    private static func put(_ root: URL, _ rel: String, _ text: String) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    /// `text` contains `|` at the caret; returns the fast-tier items for it as if typed in `rel`.
    private static func fast(_ root: URL, _ rel: String, _ text: String, manual: Bool = false) -> [CompletionItem] {
        let caret = (text as NSString).range(of: "|").location
        let clean = text.replacingOccurrences(of: "|", with: "")
        let ns = clean as NSString
        var s = caret
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        let url = root.appendingPathComponent(rel)
        CompletionLex.resetCache()
        let ctx = CompletionContext(text: clean, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil,
                                    isManual: manual, prefixRange: NSRange(location: s, length: caret - s))
        return FastTier.items(for: ctx)
    }

    static func fastTierChecks() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-fasttier-\(getpid())")
        try? fm.removeItem(at: root)
        put(root, "artisan", "#!/usr/bin/env php\n")
        put(root, "composer.json", #"{"require":{"laravel/framework":"^11"},"autoload":{"psr-4":{"App\\":"app/"}}}"#)
        put(root, "vendor/composer/autoload_psr4.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'Illuminate\\\\' => array($vendorDir . '/laravel/framework/src/Illuminate'),\n    'App\\\\' => array($baseDir . '/app'),\n);\n")
        put(root, "vendor/laravel/framework/src/Illuminate/Database/Eloquent/Model.php", "<?php\nnamespace Illuminate\\Database\\Eloquent;\nabstract class Model {\n    public function save(array $options = []): bool { return true; }\n    public function fresh($with = []) { return $this; }\n    protected function internal() {}\n    public static function create(array $attributes = []): static { return new static; }\n}\n")
        put(root, "vendor/laravel/framework/src/Illuminate/Database/Eloquent/Builder.php", "<?php\nnamespace Illuminate\\Database\\Eloquent;\nclass Builder {\n    public function where($column, $operator = null, $value = null) { return $this; }\n    public function get($columns = ['*']) {}\n}\n")
        put(root, "routes/web.php", "<?php\nuse Illuminate\\Support\\Facades\\Route;\nRoute::get('/', fn () => view('welcome'))->name('home');\nRoute::resource('posts', PostController::class);\nRoute::name('admin.')->prefix('admin')->group(function () {\n    Route::get('/users', fn () => 1)->name('users');\n});\n")
        put(root, "app/Http/Controllers/Controller.php", "<?php\nnamespace App\\Http\\Controllers;\nabstract class Controller {}\n")
        put(root, "app/Http/Controllers/LoginController.php", "<?php\nnamespace App\\Http\\Controllers;\nclass LoginController extends Controller {\n    public function __construct() {}\n    public function create() {}\n    public function store() {}\n    protected function hidden() {}\n}\n")
        put(root, "resources/views/welcome.blade.php", "hi")
        put(root, "resources/views/posts/index.blade.php", "hi")
        put(root, "resources/views/components/forms/input.blade.php", "<input>")
        put(root, "app/View/Components/Alert.php", "<?php\nnamespace App\\View\\Components;\nclass Alert {}\n")
        put(root, "config/app.php", "<?php\nreturn [\n  'name' => env('APP_NAME', 'x'),\n  'nested' => ['a' => 1, 'b' => ['c' => 2]],\n];\n")
        put(root, "config/mail.php", "<?php\nreturn ['default' => 'smtp'];\n")
        put(root, ".env", "APP_NAME=Linnet\n# comment\nDB_HOST=127.0.0.1\n")
        put(root, ".env.example", "APP_NAME=\nMAIL_MAILER=log\n")
        put(root, "lang/en/messages.php", "<?php\nreturn ['welcome' => 'Hi', 'nested' => ['deep' => 'x']];\n")
        put(root, "lang/en.json", #"{"Hello world": "Hello"}"#)
        put(root, "database/migrations/2024_01_01_000000_create_posts_table.php", """
        <?php
        return new class extends Migration {
            public function up(): void {
                Schema::create('posts', function (Blueprint $table) {
                    $table->id();
                    $table->string('title')->nullable();
                    $table->text('body');
                    $table->foreignId('user_id')->constrained();
                    $table->timestamps();
                    $table->softDeletes();
                });
            }
            public function down(): void { Schema::dropIfExists('posts'); }
        };
        """)
        put(root, "database/migrations/2024_02_01_000000_add_slug_to_posts.php", """
        <?php
        return new class extends Migration {
            public function up(): void { Schema::table('posts', function (Blueprint $t) { $t->string('slug')->unique(); $t->dropColumn('body'); }); }
            public function down(): void { Schema::table('posts', function (Blueprint $t) { $t->dropColumn('slug'); $t->text('body'); }); }
        };
        """)
        put(root, "database/migrations/2024_03_01_000000_create_users_table.php", """
        <?php
        return new class extends Migration {
            public function up(): void { Schema::create('users', function (Blueprint $table) { $table->id(); $table->string('name'); $table->rememberToken(); $table->morphs('taggable'); }); }
        };
        """)
        put(root, "app/Models/HasSlug.php", "<?php\nnamespace App\\Models;\ntrait HasSlug { public function slugify(): string { return ''; } }\n")
        put(root, "app/Models/Post.php", """
        <?php
        namespace App\\Models;
        use Illuminate\\Database\\Eloquent\\Model;
        class Post extends Model {
            use HasSlug;
            protected $fillable = ['title', 'extra_attr'];
            protected $casts = ['published_at' => 'datetime'];
            public function user() { return $this->belongsTo(User::class); }
            public function comments() { return $this->hasMany(Comment::class); }
            public function scopePublished($q) { return $q->whereNotNull('published_at'); }
            public function getFullTitleAttribute() { return ''; }
        }
        """)
        put(root, "app/Models/User.php", "<?php\nnamespace App\\Models;\nuse Illuminate\\Database\\Eloquent\\Model;\nclass User extends Model {\n    public function posts() { return $this->hasMany(Post::class); }\n}\n")
        put(root, "app/Models/Comment.php", "<?php\nnamespace App\\Models;\nuse Illuminate\\Database\\Eloquent\\Model;\nclass Comment extends Model {}\n")
        put(root, "app/Services/Greeter.php", "<?php\nnamespace App\\Services;\nclass Greeter {\n    const VERSION = 1;\n    public static function make(): static { return new static; }\n    public function hello(string $who): string { return ''; }\n    private function secret() {}\n}\n")
        let ctl = "app/Http/Controllers/PostController.php"
        let head = "<?php\nnamespace App\\Http\\Controllers;\n\nuse App\\Models\\Post;\nuse App\\Models\\User;\n\nclass PostController {\n    public function __construct(private \\App\\Services\\Greeter $greeter) {}\n    private int $count = 0;\n    public function helper(): void {}\n"
        let rc = fast(root, "routes/web.php", "<?php\nuse App\\Http\\Controllers\\LoginController;\nRoute::get('t', [LoginController::class, '|']);\n")
        check("route: [Controller::class, '|'] offers its public methods", Set(rc.map(\.label)) == ["create", "store"])
        func labels(_ items: [CompletionItem]) -> Set<String> { Set(items.map(\.label)) }
        func inMethod(_ body: String) -> String { head + "    public function index(Post $post) {\n        " + body + "\n    }\n}\n" }

        var items = fast(root, "routes/web.php", "<?php\n$u = route('|")
        var l = labels(items)
        check("fast: route names incl. resource + nested prefix", l.isSuperset(of: ["home", "posts.index", "posts.show", "admin.users"]))
        check("fast: route replaceRange starts after the quote", items.first?.replaceRange == NSRange(location: 18, length: 0))
        items = fast(root, "routes/web.php", "<?php\n$u = redirect()->route('ho|")
        check("fast: redirect()->route", labels(items).contains("home"))
        items = fast(root, "app/a.php", "<?php\nreturn view('|")
        l = labels(items)
        check("fast: view names", l.isSuperset(of: ["welcome", "posts.index", "components.forms.input"]))
        check("fast: blade @include views", labels(fast(root, "resources/views/x.blade.php", "<div>@include('po|")).contains("posts.index"))
        check("fast: blade {{ route( }}", labels(fast(root, "resources/views/x.blade.php", "<a href=\"{{ route('|")).contains("admin.users"))
        check("fast: <x- components", labels(fast(root, "resources/views/x.blade.php", "<div><x-|")).isSuperset(of: ["x-forms.input", "x-alert"]))
        check("fast: config keys", labels(fast(root, "app/a.php", "<?php\nconfig('|")).isSuperset(of: ["app.name", "app.nested.a", "app.nested.b.c", "mail.default", "mail"]))
        l = labels(fast(root, "app/a.php", "<?php\nenv('|"))
        check("fast: env keys (.env + .env.example, deduped)", l.isSuperset(of: ["APP_NAME", "DB_HOST", "MAIL_MAILER"]) && !l.contains("# comment"))
        check("fast: lang keys + json", labels(fast(root, "app/a.php", "<?php\n__('|")).isSuperset(of: ["messages.welcome", "messages.nested.deep", "Hello world"]))
        check("fast: @lang in blade", labels(fast(root, "resources/views/x.blade.php", "@lang('|")).contains("messages.welcome"))
        check("fast: no string items outside Laravel calls", fast(root, "app/a.php", "<?php\n$x = foo('|").isEmpty)

        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::where('|"))
        check("fast: Model::where columns from migrations (+fillable/casts)", l.isSuperset(of: ["id", "title", "user_id", "created_at", "deleted_at", "slug", "extra_attr", "published_at"]))
        check("fast: dropColumn applied, down() ignored", !l.contains("body") && l.contains("slug"))
        check("fast: columns use table convention for User + morphs", labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\User;\nUser::orderBy('|")).isSuperset(of: ["name", "remember_token", "taggable_id", "taggable_type"]))
        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::query()->published()->where('|"))
        check("fast: chain Post::query()->published()->where(", l.contains("title"))
        l = labels(fast(root, "app/a.php", "<?php\nDB::table('users')->where('|"))
        check("fast: DB::table columns", l.isSuperset(of: ["id", "name"]) && !l.contains("title"))
        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::with('|"))
        check("fast: with( relations", l.isSuperset(of: ["user", "comments"]) && !l.contains("title"))
        check("fast: with('user. nested relation", labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::with('user.|")).contains("posts"))
        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::where(function ($q) { $q->where('|"))
        check("fast: closure param in where() -> builder of same model", l.contains("title"))

        items = fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\n$p = Post::find(1);\n$p->|")
        l = labels(items)
        check("fast: $var = Model::find()-> columns, relations, accessor, parent method, trait method",
              l.isSuperset(of: ["title", "user", "comments", "full_title", "save", "slugify", "created_at"]))
        check("fast: protected methods hidden outside the class", !l.contains("internal"))
        check("fast: relation also offered as property", items.contains { $0.label == "user" && $0.kind == .property })
        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::|"))
        check("fast: Model:: statics + scopes + class", l.isSuperset(of: ["create", "published", "where", "class"]))
        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::published()->|"))
        check("fast: scope returns builder", l.isSuperset(of: ["where", "get", "published"]))
        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\n$p = Post::first();\n$p->user->|"))
        check("fast: $p->user-> resolves related model", l.isSuperset(of: ["posts", "name"]))
        l = labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\User;\nforeach (User::all() as $u) { $u->| }"))
        check("fast: foreach over Model::all()", l.isSuperset(of: ["name", "posts"]))

        l = labels(fast(root, ctl, inMethod("$this->|")))
        check("fast: $this-> own methods, props, private ok", l.isSuperset(of: ["helper", "index", "count", "greeter"]))
        l = labels(fast(root, ctl, inMethod("$this->greeter->|")))
        check("fast: promoted ctor property type -> members (public only)", l.contains("hello") && !l.contains("secret"))
        l = labels(fast(root, ctl, inMethod("$g = new \\App\\Services\\Greeter(); $g->|")))
        check("fast: $x = new Foo; $x->", l.contains("hello"))
        l = labels(fast(root, ctl, inMethod("$post->|")))
        check("fast: typed parameter", l.isSuperset(of: ["title", "user"]))
        l = labels(fast(root, ctl, inMethod("\\App\\Services\\Greeter::|")))
        check("fast: Foo:: statics + const, not instance methods", l.isSuperset(of: ["make", "VERSION", "class"]) && !l.contains("hello"))
        l = labels(fast(root, ctl, inMethod("self::|")))
        check("fast: self::", l.contains("helper") && l.contains("class"))
        l = labels(fast(root, ctl, inMethod("/** @var \\App\\Services\\Greeter $z */ $z->|")))
        check("fast: @var docblock", l.contains("hello"))
        check("fast: unknown receiver gives nothing", fast(root, ctl, inMethod("$mystery->|")).isEmpty)

        items = fast(root, ctl, inMethod("Gree|"))
        let g = items.first { $0.detail == "App\\Services\\Greeter" }
        check("fast: class completion from project index", g != nil && g?.label == "Greeter")
        if let g {
            let text = inMethod("Gree")
            let after = (text as NSString).range(of: "use App\\Models\\User;\n")
            check("fast: auto use import appended after last use (sorted)", g.additionalEdits.count == 1
                  && g.additionalEdits[0].text == "use App\\Services\\Greeter;\n" && g.additionalEdits[0].range.location == NSMaxRange(after))
        }
        items = fast(root, ctl, inMethod("Com|"))
        let c = items.first { $0.detail == "App\\Models\\Comment" }
        let postUse = (inMethod("Com") as NSString).range(of: "use App\\Models\\Post;\n")
        check("fast: import inserted at sorted position", c != nil && c!.additionalEdits.first?.range.location == postUse.location)
        items = fast(root, ctl, inMethod("Pos|"))
        check("fast: already imported class gets no edit", items.first { $0.detail == "App\\Models\\Post" }.map { $0.additionalEdits.isEmpty } == true)
        items = fast(root, "app/b.php", "<?php\n\nuse App\\Se|")
        check("fast: use statement completion", items.contains { $0.label == "App\\Services\\Greeter" })
        items = fast(root, "app/c.php", "<?php\n\nnew Gre|")
        let g2 = items.first { $0.label == "Greeter" }
        check("fast: import in a file without namespace/uses lands after <?php", g2 != nil && g2!.additionalEdits.first?.text == "\nuse App\\Services\\Greeter;\n")

        // incremental update: new files are picked up after an invalidate (FSEvents hook) without restart
        put(root, "database/migrations/2024_04_01_000000_add_views_to_posts.php", "<?php\nreturn new class extends Migration {\n public function up(): void { Schema::table('posts', function (Blueprint $table) { $table->integer('views_count'); }); }\n};\n")
        put(root, "routes/api.php", "<?php\nRoute::get('/ping', fn () => 1)->name('api.ping');\n")
        FastTier.invalidate(root: root)
        check("fast: new migration column picked up", labels(fast(root, "app/a.php", "<?php\nuse App\\Models\\Post;\nPost::where('|")).contains("views_count"))
        check("fast: new routes file picked up", labels(fast(root, "app/a.php", "<?php\nroute('|")).contains("api.ping"))

        // typing more of a member name must keep the member (`$request->to` -> `$request->toA`)
        put(root, "vendor/laravel/framework/src/Illuminate/Http/Request.php", "<?php\nnamespace Illuminate\\Http;\nclass Request {\n    public function toArray() { return []; }\n    public function toJson() { return ''; }\n    public function touch() {}\n    public function validationData() {}\n    public function getPayload() {}\n}\n")
        FastTier.invalidate(root: root)
        for typed in ["to", "toA", "toAr", "toArray"] {
            let body = "<?php\nuse Illuminate\\Http\\Request;\nclass C {\n    public function f(Request $request) {\n        $request->\(typed)|\n    }\n}\n"
            let its = fast(root, "app/a.php", body)
            let clean = body.replacingOccurrences(of: "|", with: "")
            let out = CompletionRanker.rank(results: [(its, false)], text: clean as NSString, caret: (body as NSString).range(of: "|").location, anchor: 0)
            check("fast: `->\(typed)` lists toArray first among prefix matches", typed == "toArray" || out.ranked.first?.item.label == "toArray")
        }

        // robustness
        _ = fast(root, "app/a.php", "<?php\n$x = $a->b(->c((( $d->|")
        _ = fast(root, "app/a.php", "<?php\nRoute::get(|")
        check("fast: garbage input does not crash", true)
        try? fm.removeItem(at: root)
        memberPrefixProbe()
        fastTierBench()
    }

    private static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    /// CE_TOA_FILE=<php file with `Request $request`>: prints, per provider, what `$request->to` / `->toA` yields (diagnostic).
    private static func memberPrefixProbe() {
        guard let path = AppEnv.value("CE_TOA_FILE"), let src = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let ns0 = src as NSString
        let r = ns0.range(of: "Request $request")
        guard r.location != NSNotFound else { fputs("PROBE no Request $request\n", stderr); return }
        let brace = ns0.range(of: "{", range: NSRange(location: r.location, length: ns0.length - r.location))
        let url = URL(fileURLWithPath: path)
        for typed in ["to", "toA"] {
            let text = ns0.replacingCharacters(in: NSRange(location: brace.location + 1, length: 0), with: "\n        $request->\(typed)")
            let caret = brace.location + 1 + ("\n        $request->" + typed).utf16.count
            let ns = text as NSString
            let start = caret - typed.utf16.count
            let ctx = CompletionContext(text: text, caret: caret, fileURL: url, fileExtension: "php", triggerCharacter: nil, isManual: false,
                                        prefixRange: NSRange(location: start, length: typed.utf16.count))
            var results: [(items: [CompletionItem], incomplete: Bool)?] = []
            let providers = CompletionRegistry.providers(forExtension: "php")
            for p in providers {
                let sem = DispatchSemaphore(value: 0)
                var got: ([CompletionItem], Bool) = ([], false)
                p.complete(ctx) { got = ($0, $1); sem.signal() }
                while sem.wait(timeout: .now() + 0.01) == .timedOut { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                results.append(got)
                fputs("PROBE \(typed) \(type(of: p)): \(got.0.count) items, toArray=\(got.0.contains { $0.label == "toArray" }) incomplete=\(got.1)\n", stderr)
            }
            let out = CompletionRanker.rank(results: results, text: ns, caret: caret, anchor: start)
            fputs("PROBE \(typed) top: \(out.ranked.prefix(8).map { $0.item.label + "/" + String($0.cls) }.joined(separator: ", "))\n", stderr)
        }
    }

    /// CE_FASTTIER_BENCH=<laravel root>: read-only measurements on a real project, printed to stderr.
    private static func fastTierBench() {
        guard let path = AppEnv.value("CE_FASTTIER_BENCH"), !path.isEmpty else { return }
        let root = URL(fileURLWithPath: path)
        let fp = FastProject.shared(root: root)
        let before = residentMB()
        func ms(_ block: () -> Void) -> Double { let t = DispatchTime.now(); block(); return Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6 }
        var counts: [String: Int] = [:]
        let cold = ms { fp.queue.sync {
            fp.beginRequest()
            counts["routes"] = fp.routeNames().count
            counts["views"] = fp.viewNames().count
            counts["components"] = fp.componentNames().count
            counts["config keys"] = fp.configKeys().count
            counts["env"] = fp.envKeys().count
            counts["lang keys"] = fp.langKeys().count
            counts["inertia pages"] = fp.inertiaPages().count
            let schema = fp.schema()
            counts["tables"] = schema.count
            counts["columns"] = schema.values.reduce(0) { $0 + $1.count }
            counts["project classes"] = fp.projectClasses().count
        } }
        fputs("BENCH index build (cold, background queue): \(String(format: "%.0f", cold)) ms\n", stderr)
        for (k, v) in counts.sorted(by: { $0.key < $1.key }) { fputs("BENCH \(k): \(v)\n", stderr) }
        var models = 0
        var sample: (fqn: String, short: String)?
        fp.queue.sync {
            for c in fp.projectClasses() where c.fqn.contains("\\Models\\") {
                guard let ci = fp.classInfo(c.fqn), fp.isModel(ci) else { continue }
                models += 1
                if sample == nil, fp.columns(of: ci).count > 5, !ci.relations.isEmpty { sample = (c.fqn, c.short) }
            }
        }
        fputs("BENCH models: \(models)\n", stderr)
        func req(_ name: String, _ text: String) {
            let caret = (text as NSString).range(of: "|").location
            let clean = text.replacingOccurrences(of: "|", with: "")
            let ns = clean as NSString
            var s = caret
            while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
            var n = 0
            CompletionLex.resetCache()
            let ctx = CompletionContext(text: clean, caret: caret, fileURL: root.appendingPathComponent("app/Http/Controllers/BenchProbe.php"), fileExtension: "php",
                                        triggerCharacter: nil, isManual: false, prefixRange: NSRange(location: s, length: caret - s))
            let first = ms { n = FastTier.items(for: ctx).count }
            let warm = (0..<10).reduce(0.0) { acc, _ in acc + ms { CompletionLex.resetCache(); n = FastTier.items(for: ctx).count } } / 10
            fputs("BENCH \(name): \(n) items, first \(String(format: "%.1f", first)) ms, warm avg \(String(format: "%.1f", warm)) ms\n", stderr)
        }
        req("route('", "<?php\n$x = route('|")
        req("view('", "<?php\n$x = view('|")
        req("config('", "<?php\n$x = config('|")
        req("env('", "<?php\n$x = env('|")
        req("__('", "<?php\n$x = __('|")
        if let s = sample {
            let head = "<?php\nnamespace App\\Http\\Controllers;\nuse \(s.fqn);\nclass BenchProbe {\n    public function a() {\n        "
            req("\(s.short)::where('", head + "\(s.short)::where('|")
            req("$m = \(s.short)::first(); $m->", head + "$m = \(s.short)::first(); $m->|")
            req("\(s.short)::", head + "\(s.short)::|")
            req("\(s.short)::with('", head + "\(s.short)::with('|")
        }
        let head2 = "<?php\nnamespace App\\Http\\Controllers;\nclass BenchProbe {\n    public function a() {\n        "
        req("class name 'Use'", head2 + "Use|")
        req("class name 'Contr'", head2 + "Contr|")
        req("$this->", head2 + "$this->|")
        let after = residentMB()
        fputs("BENCH memory delta: \(String(format: "%.1f", after - before)) MB (resident \(String(format: "%.0f", before)) -> \(String(format: "%.0f", after)) MB)\n", stderr)
    }
}
