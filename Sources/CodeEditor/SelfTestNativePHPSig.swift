import AppKit

/// Headless checks for phase 2a of the native PHP service: signature help, docblock/auth/container/facade type inference,
/// go to implementation and type declaration. Snippets mark the caret / pointer with `§`.
enum SelfTestNativePHPSig {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("nativesig: " + name, ok()) }

    private static let ctl = "app/Http/Controllers/PostController.php"

    private static func put(_ root: URL, _ rel: String, _ text: String) { SelfTestNativePHP.put(root, rel, text) }

    static func buildFixture(_ root: URL) {
        SelfTestNativePHP.buildFixture(root)
        let il = "vendor/laravel/framework/src/Illuminate/"
        put(root, "config/auth.php", """
        <?php
        use App\\Models\\User;
        return [
            'defaults' => [
                'guard' => env('AUTH_GUARD', 'web'),
                'passwords' => 'users',
            ],
            'guards' => [
                'web' => ['driver' => 'session', 'provider' => 'users'],
                'admin' => ['driver' => 'session', 'provider' => 'admins'],
            ],
            'providers' => [
                'users' => ['driver' => 'eloquent', 'model' => env('AUTH_MODEL', User::class)],
                'admins' => ['driver' => 'eloquent', 'model' => App\\Models\\Admin::class],
            ],
        ];
        """)
        put(root, "app/Models/Admin.php", "<?php\nnamespace App\\Models;\nuse Illuminate\\Database\\Eloquent\\Model;\nclass Admin extends Model {\n    public function promote(): void {}\n}\n")
        put(root, il + "Contracts/Auth/Guard.php", "<?php\nnamespace Illuminate\\Contracts\\Auth;\ninterface Guard {\n    public function user();\n    public function check(): bool;\n}\n")
        put(root, il + "Auth/AuthManager.php", """
        <?php
        namespace Illuminate\\Auth;
        class AuthManager {
            /**
             * Attempt to get the guard from the local cache.
             *
             * @param  string|null  $name
             * @return \\Illuminate\\Contracts\\Auth\\Guard
             */
            public function guard($name = null) {}
        }
        """)
        put(root, il + "Support/Facades/Auth.php", "<?php\nnamespace Illuminate\\Support\\Facades;\nclass Auth extends Facade {\n    protected static function getFacadeAccessor() { return 'auth'; }\n}\n")
        put(root, il + "Support/Facades/Cache.php", """
        <?php
        namespace Illuminate\\Support\\Facades;
        /**
         * @method static mixed get(string $key, mixed $default = null)
         */
        class Cache extends Facade {
            protected static function getFacadeAccessor() { return 'cache'; }
        }
        """)
        put(root, il + "Cache/CacheManager.php", """
        <?php
        namespace Illuminate\\Cache;
        class CacheManager {
            /**
             * Get a cache store instance by name.
             *
             * @param  string|null  $name
             * @return \\Illuminate\\Cache\\Repository
             */
            public function store($name = null) {}
            public function get($key, $default = null) {}
        }
        """)
        put(root, il + "Cache/Repository.php", "<?php\nnamespace Illuminate\\Cache;\nclass Repository {\n    public function remember($key, $ttl, \\Closure $callback) {}\n    public function pull($key, $default = null) {}\n}\n")
        put(root, il + "Http/Request.php", "<?php\nnamespace Illuminate\\Http;\nclass Request {\n    public function input($key = null, $default = null) {}\n    public function user($guard = null) {}\n}\n")
        put(root, il + "Foundation/Application.php", """
        <?php
        namespace Illuminate\\Foundation;
        class Application {
            /**
             * Resolve the given type from the container.
             *
             * @template TClass of object
             *
             * @param  string|class-string<TClass>  $abstract
             * @param  array  $parameters
             * @return ($abstract is class-string<TClass> ? TClass : mixed)
             */
            public function make($abstract, array $parameters = []) {}
            public function environment() {}
        }
        """)
        put(root, "app/helpers.php", "<?php\n\nconst APP_EDITION = 'pro';\n\n/**\n * Format cents as a currency string.\n *\n * @param int $cents Amount in cents\n * @return string\n */\nfunction format_money(int $cents): string { return ''; }\n\nfunction tag(string $name, string ...$classes): string { return ''; }\n")
        put(root, "app/Services/Catalog.php", """
        <?php
        namespace App\\Services;

        use App\\Models\\Post;
        use Illuminate\\Support\\Collection;

        class Catalog {
            /** @var Post[] */
            protected array $featured = [];
            /** @var Collection<int, Post> */
            public $recent;
            public Post $pinned;

            /**
             * All posts in the catalog.
             *
             * @return Collection<int, Post>
             */
            public function posts(): Collection { return new Collection; }
            /** @return Post|null */
            public function latest() { return null; }
            /** @return static */
            public function fresh() { return $this; }
            /** @return $this */
            public function chain() { return $this; }
            /**
             * @template T of object
             * @param class-string<T> $class
             * @return T
             */
            public function make(string $class) {}
            /** @param Post[] $posts */
            public function show(array $posts) {}
            /** @return array<int, Post> */
            public function list(): array { return []; }
        }
        """)
        put(root, "app/Contracts/Notifier.php", "<?php\nnamespace App\\Contracts;\ninterface Notifier {\n    public function send(string $to, string $body): bool;\n}\n")
        put(root, "app/Services/BaseNotifier.php", "<?php\nnamespace App\\Services;\nuse App\\Contracts\\Notifier;\nabstract class BaseNotifier implements Notifier {\n    protected function prefix(): string { return ''; }\n}\n")
        put(root, "app/Services/EmailNotifier.php", "<?php\nnamespace App\\Services;\nclass EmailNotifier extends BaseNotifier {\n    public function send(string $to, string $body): bool { return true; }\n}\n")
        put(root, "app/Services/PushNotifier.php", "<?php\nnamespace App\\Services;\n\nclass PushNotifier extends EmailNotifier\n{\n    public function send(string $to, string $body): bool { return false; }\n}\n")
        put(root, "app/Services/SmsNotifier.php", "<?php\nnamespace App\\Services;\nuse App\\Contracts\\Notifier;\nfinal class SmsNotifier implements Notifier\n{\n    public function send(string $to, string $body, array $opts = []): bool { return true; }\n}\n")
        put(root, "app/Services/Unrelated.php", "<?php\nnamespace App\\Services;\nclass Unrelated extends Other {\n    public function send() {}\n}\n")
    }

    private static func src(_ code: String, params: String = "Post $post") -> String {
        "<?php\nnamespace App\\Http\\Controllers;\n\nuse App\\Models\\Post;\nuse App\\Models\\User;\nuse App\\Contracts\\Notifier;\nuse App\\Services\\Catalog;\nuse App\\Services\\PostService;\nuse Illuminate\\Http\\Request;\nuse Illuminate\\Support\\Facades\\Auth;\nuse Illuminate\\Support\\Facades\\Cache;\n\nclass PostController {\n    public function __construct(private PostService $service, private Catalog $catalog) {}\n    public function show(\(params)) {\n        \(code)\n    }\n}\n"
    }

    private static func prep(_ root: URL, _ rel: String, _ s: String) -> (URL, NSString, Int)? {
        let off = (s as NSString).range(of: "§").location
        guard off != NSNotFound else { return nil }
        let clean = s.replacingOccurrences(of: "§", with: "")
        put(root, rel, clean)
        return (root.appendingPathComponent(rel), clean as NSString, off)
    }

    private static func sig(_ root: URL, _ code: String, params: String = "Post $post", rel: String = ctl) -> NPSigHelp? {
        guard let (u, t, off) = prep(root, rel, src(code, params: params)) else { return nil }
        if case .help(let h) = NativePHP.signatureHelp(url: u, text: t, caret: off, root: root.path) { return h }
        return nil
    }

    private static func outcome(_ root: URL, _ code: String, params: String = "Post $post") -> String {
        guard let (u, t, off) = prep(root, ctl, src(code, params: params)) else { return "badtest" }
        switch NativePHP.signatureHelp(url: u, text: t, caret: off, root: root.path) {
        case .help: return "help"
        case .notInCall: return "notInCall"
        case .unknown: return "unknown"
        }
    }

    private static func active(_ h: NPSigHelp?) -> String? {
        guard let h, h.active >= 0, h.active < h.ranges.count else { return nil }
        return (h.label as NSString).substring(with: h.ranges[h.active])
    }

    private static func typeDef(_ root: URL, _ code: String, params: String = "Post $post", rel: String = ctl) -> NPHit? {
        guard let (u, t, off) = prep(root, rel, src(code, params: params)) else { return nil }
        return NativePHP.typeDefinition(url: u, text: t, offset: off, root: root.path)
    }

    private static func hover(_ root: URL, _ code: String, params: String = "Post $post") -> String {
        guard let (u, t, off) = prep(root, ctl, src(code, params: params)) else { return "" }
        return NativePHP.lookup(url: u, text: t, offset: off, root: root.path)?.markdown ?? ""
    }

    private static func defPath(_ root: URL, _ code: String, params: String = "Post $post") -> String {
        guard let (u, t, off) = prep(root, ctl, src(code, params: params)) else { return "" }
        return NativePHP.lookup(url: u, text: t, offset: off, root: root.path)?.targets.first?.path ?? ""
    }

    private static func impl(_ root: URL, _ rel: String, _ s: String) -> NPHit? {
        guard let (u, t, off) = prep(root, rel, s) else { return nil }
        return NativePHP.implementations(url: u, text: t, offset: off, root: root.path)
    }

    private static func names(_ h: NPHit?) -> [String] { (h?.targets ?? []).map { ($0.path as NSString).lastPathComponent }.sorted() }

    private static func isPost(_ h: NPHit?) -> Bool { h?.targets.first?.path.hasSuffix("app/Models/Post.php") == true }

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-nativesig-\(getpid())")
        try? fm.removeItem(at: root)
        buildFixture(root)
        defer { try? fm.removeItem(at: root) }
        NPFiles.clear()

        // MARK: signature help: methods, statics, constructors
        var h = sig(root, "$post->save(§)")
        check("method: label and first param", h?.label == "save(array $options = []): bool" && active(h) == "array $options = []")
        h = sig(root, "Post::create(§)")
        check("static method", h?.label.hasPrefix("create(array $attributes = [])") == true)
        h = sig(root, "$post->shortTitle(§)")
        check("method with docblock summary", h?.label.hasPrefix("shortTitle(int $max = 20)") == true && (h?.summary.contains("Short title") ?? false))
        h = sig(root, "$x = new PostService(§)")
        check("constructor (promoted param)", h?.label.contains("Post $post") == true && h?.label.hasPrefix("PostService(") == true)
        h = sig(root, "$x = new Post(§)")
        check("constructor without own __construct: empty list", h?.label.hasPrefix("Post(") == true)
        h = sig(root, "$this->service->current(§)")
        check("typed property chain", h?.label == "current(): Post")
        h = sig(root, "Post::where('a', §)")
        check("Eloquent forwarding to builder: second param", active(h) == "$operator = null")
        h = sig(root, "User::active(§)")
        check("scope drops $query", h?.label.hasPrefix("active()") == true)

        // MARK: active parameter tracking
        h = sig(root, "Post::where('a', route('x', §))")
        check("nested call: inner function active 1", h?.label.hasPrefix("route($name, $parameters = [], $absolute = true)") == true && active(h) == "$parameters = []")
        h = sig(root, "Post::where('a', route('x', 1), §)")
        check("after nested call closes: outer index 2", active(h) == "$value = null")
        h = sig(root, "Post::where('a,(b', §)")
        check("commas and parens inside strings ignored", active(h) == "$operator = null")
        h = sig(root, "Post::where(/* a, b, c */ 'x', §)")
        check("commas inside comments ignored", active(h) == "$operator = null")
        h = sig(root, "Post::where(['a' => 1, 'b' => [1, 2, 3]], §)")
        check("commas inside array literals ignored", active(h) == "$operator = null")
        h = sig(root, "Post::where(function ($q) { $q->where('a', 1); }, §)")
        check("closure argument with its own calls", active(h) == "$operator = null")
        h = sig(root, "Post::where(column: 'x', value: §)")
        check("named arguments", active(h) == "$value = null")
        h = sig(root, "Post::where('a', 'b', 'c', §)")
        check("extra arguments: no active parameter", h != nil && active(h) == nil)
        h = sig(root, "tag('a', 'b', 'c', §)")
        check("variadic absorbs extra arguments", active(h) == "string ...$classes")
        h = sig(root, "Post::where('a',§")
        check("unclosed call while typing", active(h) == "$operator = null")
        h = sig(root, "Post::where(§")
        check("just after (", active(h) == "$column")
        h = sig(root, "$post->save(§);\n        $y = 1;")
        check("caret between () with following code", h?.label.hasPrefix("save(") == true)
        h = sig(root, "$post->save(\n            [\n                'a' => 1,\n            ],\n            §\n        );")
        check("multi-line call", h?.label.hasPrefix("save(") == true && h?.active == 1)

        // MARK: not in a call / unresolved
        check("outside any call", outcome(root, "$x = 1;§") == "notInCall")
        check("after the closing paren", outcome(root, "$post->save()§;") == "notInCall")
        check("inside closure body of a call", outcome(root, "Post::where(function ($q) { §") == "notInCall")
        check("inside parenthesised grouping", outcome(root, "$x = (1 + §2);") == "notInCall")
        check("function declaration params", outcome(root, "function inner(§) {}") == "notInCall")
        check("unresolvable callee falls back (unknown)", outcome(root, "$mystery->foo(§)") == "unknown")
        check("if/while parens are not calls", outcome(root, "if (§$x) {}") == "notInCall")
        check("unknown function is unknown", outcome(root, "nothing_here(§)") == "unknown")

        // MARK: functions
        h = sig(root, "route(§)")
        check("vendor helper function", h?.label.hasPrefix("route($name, $parameters = [], $absolute = true)") == true && active(h) == "$name")
        check("vendor helper param docs array matches params", h?.paramDocs.count == 3)
        h = sig(root, "format_money(§)")
        check("user helper with return type and @param doc", h?.label == "format_money(int $cents): string" && h?.paramDocs.first == "Amount in cents")
        h = sig(root, "strlen(§)")
        check("built-in function", h?.label == "strlen(string $string): int")
        h = sig(root, "str_replace('a', 'b', $s, §)")
        check("built-in with by-ref param", active(h) == "&$count = null")
        h = sig(root, "$fmt = function (int $a, string $b) { return 1; };\n        $fmt(1, §)")
        check("closure assigned to variable", active(h) == "string $b")
        h = sig(root, "$fmt = fn (int $a, $b = [1, 2]) => 1;\n        $fmt(§)")
        check("arrow fn variable (default with comma)", h?.ranges.count == 2 && active(h) == "int $a")
        h = sig(root, "Cache::get('k', §)")
        check("facade method (via @see / @method)", active(h)?.contains("default") == true)
        h = sig(root, "Cache::store('x')->remember('k', §)")
        check("facade root chain: Cache::store()->remember", h?.label.hasPrefix("remember($key, $ttl, \\Closure $callback)") == true && active(h) == "$ttl")

        // MARK: type inference: docblock returns / props / params
        var d = typeDef(root, "$p = $this->catalog->latest(); $p§")
        check("@return Post|null", isPost(d))
        d = typeDef(root, "$c = $this->catalog->fresh(); $c§")
        check("@return static", d?.targets.first?.path.hasSuffix("app/Services/Catalog.php") == true)
        d = typeDef(root, "$c = $this->catalog->chain(); $c§")
        check("@return $this", d?.targets.first?.path.hasSuffix("app/Services/Catalog.php") == true)
        d = typeDef(root, "foreach ($this->catalog->posts() as $p) { $p§ }")
        check("Collection<int, Post> element via foreach", isPost(d))
        d = typeDef(root, "$p = $this->catalog->posts()->first(); $p§")
        check("Collection<int, Post>->first()", isPost(d))
        d = typeDef(root, "foreach ($this->catalog->list() as $p) { $p§ }")
        check("array<int, Post> return", isPost(d))
        d = typeDef(root, "$x = $this->catalog->recent->first(); $x§")
        check("property @var Collection<int, Post>", isPost(d))
        d = typeDef(root, "$x = $this->catalog->pinned; $x§")
        check("typed property", isPost(d))
        d = typeDef(root, "$x = $this->catalog->make(Post::class); $x§")
        check("@template T via class-string<T> param", isPost(d))
        d = typeDef(root, "$x = $this->catalog->make(User::class); $x§")
        check("@template T with another class", d?.targets.first?.path.hasSuffix("app/Models/User.php") == true)
        d = typeDef(root, "foreach ($posts as $p) { $p§ }", params: "array $posts")
        check("array param without doc: no type", d == nil || d?.targets.isEmpty == true)
        let showDoc = "<?php\nnamespace App\\Http\\Controllers;\nuse App\\Models\\Post;\nclass K {\n    /** @param Post[] $posts */\n    public function a(array $posts) { foreach ($posts as $p) { $p§ } }\n}\n"
        if let (u, t, off) = prep(root, "app/Http/Controllers/K.php", showDoc) {
            check("@param Post[] on array param", isPost(NativePHP.typeDefinition(url: u, text: t, offset: off, root: root.path)))
        }
        let varDoc = "<?php\nnamespace App\\Http\\Controllers;\nuse App\\Models\\Post;\nuse Illuminate\\Support\\Collection;\nclass K {\n    public function a() {\n        /** @var Collection<int, Post> $items */\n        $items = $this->load();\n        $n = $items->first();\n        $n§\n    }\n}\n"
        if let (u, t, off) = prep(root, "app/Http/Controllers/K.php", varDoc) {
            check("inline @var with generics", isPost(NativePHP.typeDefinition(url: u, text: t, offset: off, root: root.path)))
        }

        // MARK: auth / request / container / facades
        d = typeDef(root, "$u = auth()->user(); $u§")
        check("auth()->user()", d?.targets.first?.path.hasSuffix("app/Models/User.php") == true)
        d = typeDef(root, "$u = Auth::user(); $u§")
        check("Auth::user()", d?.targets.first?.path.hasSuffix("app/Models/User.php") == true)
        d = typeDef(root, "$u = request()->user(); $u§")
        check("request()->user()", d?.targets.first?.path.hasSuffix("app/Models/User.php") == true)
        d = typeDef(root, "$u = $request->user(); $u§", params: "Request $request")
        check("$request->user()", d?.targets.first?.path.hasSuffix("app/Models/User.php") == true)
        d = typeDef(root, "$u = auth('admin')->user(); $u§")
        check("auth('admin')->user() uses the guard's provider model", d?.targets.first?.path.hasSuffix("app/Models/Admin.php") == true)
        d = typeDef(root, "$u = Auth::guard('admin')->user(); $u§")
        check("Auth::guard('admin')->user()", d?.targets.first?.path.hasSuffix("app/Models/Admin.php") == true)
        d = typeDef(root, "$u = $request->user('admin'); $u§", params: "Request $request")
        check("$request->user('admin')", d?.targets.first?.path.hasSuffix("app/Models/Admin.php") == true)
        check("member on auth()->user()", defPath(root, "auth()->user()->po§sts()").hasSuffix("app/Models/User.php"))
        check("hover member on Auth::user()", hover(root, "Auth::user()->sl§ugify('x')").contains("slugify"))
        h = sig(root, "auth()->user()->slugify(§)")
        check("signature help on auth()->user()->method", h?.label.hasPrefix("slugify(string $value): string") == true)
        d = typeDef(root, "$x = app(Post::class); $x§")
        check("app(Foo::class)", isPost(d))
        d = typeDef(root, "$x = resolve(Post::class); $x§")
        check("resolve(Foo::class)", isPost(d))
        d = typeDef(root, "$x = app()->make(Post::class); $x§")
        check("app()->make(Foo::class) via conditional @return", isPost(d))
        d = typeDef(root, "$x = app('cache'); $x§")
        check("app('cache') alias", d?.targets.first?.path.hasSuffix("Cache/CacheManager.php") == true)
        check("def through app('cache')->get", defPath(root, "app('cache')->g§et('k')").hasSuffix("Cache/CacheManager.php"))
        check("def through facade root Cache::store()->remember", defPath(root, "Cache::store('x')->rem§ember('k', 1, fn () => 1)").hasSuffix("Cache/Repository.php"))
        d = typeDef(root, "$x = Cache::store(); $x§")
        check("facade method return type via root", d?.targets.first?.path.hasSuffix("Cache/Repository.php") == true)

        // MARK: type definition on members and chains
        d = typeDef(root, "$this->serv§ice->current();")
        check("type of property", d?.targets.first?.path.hasSuffix("app/Services/PostService.php") == true)
        d = typeDef(root, "$this->service->curr§ent();")
        check("type of method call result", isPost(d))
        d = typeDef(root, "$po§st->save();")
        check("type of variable", isPost(d))
        d = typeDef(root, "$thi§s->service;")
        check("type of $this", d?.targets.first?.path.hasSuffix("app/Http/Controllers/PostController.php") == true)
        d = typeDef(root, "$cs = $post->comments; $c§s")
        check("collection relation: collection and element classes", (d?.targets.count ?? 0) >= 2 && d?.targets.contains(where: { $0.path.hasSuffix("app/Models/Comment.php") }) == true)
        d = typeDef(root, "$sum§ = 1;")
        check("variable of unknown type: no target", d == nil || d!.targets.isEmpty)

        // MARK: go to implementation
        var ih = impl(root, "app/Contracts/Notifier.php", "<?php\nnamespace App\\Contracts;\ninterface Notifier {\n    public function se§nd(string $to, string $body): bool;\n}\n")
        check("interface method -> all implementers and overriders", names(ih) == ["EmailNotifier.php", "PushNotifier.php", "SmsNotifier.php"])
        check("landing on the method names", ih?.targets.allSatisfy { t in
            guard let s = try? String(contentsOfFile: t.path, encoding: .utf8) else { return false }
            return (s as NSString).substring(with: NSRange(location: t.offset, length: 4)) == "send" } == true)
        ih = impl(root, "app/Contracts/Notifier.php", "<?php\nnamespace App\\Contracts;\ninterface Noti§fier {\n    public function send(string $to, string $body): bool;\n}\n")
        check("interface -> transitive implementers (abstract, concrete, sub-subclass)", names(ih) == ["BaseNotifier.php", "EmailNotifier.php", "PushNotifier.php", "SmsNotifier.php"])
        ih = impl(root, ctl, src("$n->se§nd('a', 'b');", params: "Notifier $n"))
        check("call on interface-typed variable", names(ih) == ["EmailNotifier.php", "PushNotifier.php", "SmsNotifier.php"])
        ih = impl(root, ctl, src("$n = 1;", params: "\\App\\Services\\EmailNo§tifier $n"))
        check("class reference -> subclasses", names(ih) == ["PushNotifier.php"])
        ih = impl(root, ctl, src("$n->be§gin();", params: "Notifier $n"))
        check("member with no implementers: nil", ih == nil)
        ih = impl(root, ctl, src("$po§st;"))
        check("variable typed by a class without subclasses: nil", ih == nil)
        ih = impl(root, ctl, src("$§n->send('a','b');", params: "Notifier $n"))
        check("variable of interface type -> implementers", names(ih) == ["BaseNotifier.php", "EmailNotifier.php", "PushNotifier.php", "SmsNotifier.php"])
        ih = impl(root, "app/Services/EmailNotifier.php", "<?php\nnamespace App\\Services;\nclass EmailNotifier extends BaseNotifier {\n    public function se§nd(string $to, string $body): bool { return true; }\n}\n")
        check("concrete method -> overriders", names(ih) == ["PushNotifier.php"])
        ih = impl(root, "app/Services/Unrelated.php", "<?php\nnamespace App\\Services;\nclass Unrelated extends Other {\n    public function se§nd() {}\n}\n")
        check("unrelated same-named method is not an implementer", ih == nil)
        check("file cache stays bounded", NPFiles.cachedCount <= 6)

        // MARK: blade
        if let (u, t, off) = prep(root, "resources/views/posts/show.blade.php", "<div>{{ format_money(§) }}</div>") {
            if case .help(let bh) = NativePHP.signatureHelp(url: u, text: t, caret: off, root: root.path) { check("blade {{ }} signature help", bh.label.hasPrefix("format_money(")) } else { check("blade {{ }} signature help", false) }
        }
        if let (u, t, off) = prep(root, "resources/views/posts/show.blade.php", "<p>format_money(§)</p>") {
            if case .notInCall = NativePHP.signatureHelp(url: u, text: t, caret: off, root: root.path) { check("blade plain HTML: no help", true) } else { check("blade plain HTML: no help", false) }
        }

        // MARK: LSP payload
        h = sig(root, "$post->save(§)")
        let attributed = h.flatMap { LSPUIParse.signature($0.lspPayload) }
        check("payload renders in the existing popup", attributed?.string.hasPrefix("save(array $options = [])") == true)
        check("popup highlights the active parameter", {
            guard let a = attributed else { return false }
            var found = false
            a.enumerateAttribute(.font, in: NSRange(location: 0, length: min(a.length, 40))) { v, r, _ in
                if let f = v as? NSFont, f.fontDescriptor.symbolicTraits.contains(.bold), r.length > 0 { found = true }
            }
            return found
        }())
    }
}
