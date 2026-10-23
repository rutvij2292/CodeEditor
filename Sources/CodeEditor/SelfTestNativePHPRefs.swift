import AppKit

/// Headless checks for native find usages + rename (NativePHPRefs*.swift / NativePHPRename.swift) on a multi-file Laravel fixture
/// that contains false-positive traps (same member names on unrelated classes, a second class called User, local variables with
/// the same name in other methods).
enum SelfTestNativePHPRefs {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("refs: " + name, ok()) }

    private static func put(_ root: URL, _ rel: String, _ text: String) { SelfTestNativePHP.put(root, rel, text) }
    private static func read(_ root: URL, _ rel: String) -> String { (try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)) ?? "" }

    static func buildFixture(_ root: URL) {
        SelfTestNativePHP.buildFixture(root)
        put(root, "app/Models/Page.php", #"""
        <?php
        namespace App\Models;

        use App\Contracts\Publishable;

        class Page implements Publishable {
            public const MAX_TITLE = 80;
            public function publish(): void {}
        }
        """#)
        put(root, "app/Legacy/Draft.php", #"""
        <?php
        namespace App\Legacy;

        class Draft {
            public const MAX_TITLE = 5;
            public function publish(): bool { return true; }
            public function shortTitle() {}
        }
        """#)
        put(root, "app/Legacy/User.php", "<?php\nnamespace App\\Legacy;\n\nclass User {\n    public function posts() {}\n}\n")
        put(root, "app/Legacy/Report.php", #"""
        <?php
        namespace App\Legacy;

        use App\Legacy\User;

        class Report {
            /** @param User $u */
            public function run(User $u) { $x = new User(); return $u->posts(); }
        }
        """#)
        put(root, "app/Cashier.php", "<?php\nnamespace App;\n\nclass Cashier {\n    public function format_money($x) { return $x; }\n}\n")
        put(root, "app/Models/Counter.php", #"""
        <?php
        namespace App\Models;

        class Counter {
            protected int $count = 0;
            public static int $instances = 0;
            public function inc(): int {
                $this->count++;
                self::$instances++;
                return $this->count;
            }
        }
        """#)
        put(root, "app/Models/SubCounter.php", "<?php\nnamespace App\\Models;\n\nclass SubCounter extends Counter {\n    public function dec(): int { $this->count--; return $this->count; }\n}\n")
        put(root, "app/Models/Tally.php", "<?php\nnamespace App\\Models;\n\nclass Tally {\n    public int $count = 0;\n}\n")
        put(root, "app/Http/Controllers/PostController.php", #"""
        <?php
        namespace App\Http\Controllers;

        use App\Contracts\Publishable;
        use App\Enums\Status;
        use App\Legacy\Draft;
        use App\Models\Counter;
        use App\Models\Page;
        use App\Models\Post;
        use App\Models\SubCounter;
        use App\Models\Tally;
        use App\Models\User;
        use App\Models\User as Account;
        use App\Cashier;

        class PostController {
            /**
             * @param User $owner
             * @param Post $post
             */
            public function store(Post $post, Page $page, Draft $draft, Publishable $any, $mystery, User $owner, Cashier $cashier) {
                $post->publish();
                $page->publish();
                $draft->publish();
                $any->publish();
                $mystery->publish();
                $title = Post::MAX_TITLE;
                $other = Draft::MAX_TITLE;
                $short = $post->shortTitle(5);
                $d = $draft->shortTitle();
                $u = new User();
                $a = Account::find(1);
                $c = User::class;
                $name = 'App\\Models\\User';
                $s = Status::Draft;
                $label = "Hello $title and {$title}";
                $m = format_money(100) . $cashier->format_money(1);
                $q = Post::published()->get();
                $counter = new Counter();
                $counter->inc();
                $sub = new SubCounter();
                $sub->dec();
                $t = new Tally();
                $t->count = 3;
                return [$post, $page, $title, 'user'];
            }

            public function other(Post $post) {
                $title = 'x';
                return $title . $post->title;
            }

            public function publish() { return $this->store(...); }
        }
        """#)
        put(root, "routes/web.php", #"""
        <?php
        use App\Http\Controllers\PostController;

        Route::get('/p', [PostController::class, 'publish']);
        Route::post('/p', [PostController::class, 'store']);
        """#)
        put(root, "config/auth.php", #"""
        <?php
        return ['providers' => ['users' => ['driver' => 'eloquent', 'model' => 'App\\Models\\User']]];
        """#)
        put(root, "resources/views/posts/pub.blade.php", "@php\n    /** @var \\App\\Models\\Post $post */\n@endphp\n<p>{{ $post->publish() }}</p>\n")
    }

    private static func sym(_ root: URL, _ rel: String, _ find: String, at inner: String) -> NPRefSymbol? {
        // caret placed inside the first occurrence of `find`, at the first occurrence of `inner` inside it
        let text = read(root, rel) as NSString
        let r = text.range(of: find)
        guard r.location != NSNotFound else { return nil }
        let i = (find as NSString).range(of: inner).location
        guard i != NSNotFound else { return nil }
        if case .symbol(let s) = NPRefs.identify(url: root.appendingPathComponent(rel), text: text, offset: r.location + i + 1, root: root.path) { return s }
        return nil
    }

    private static func id(_ root: URL, _ rel: String, _ find: String, at inner: String) -> NPRefIdentity {
        let text = read(root, rel) as NSString
        let r = text.range(of: find)
        guard r.location != NSNotFound else { return .none }
        let i = (find as NSString).range(of: inner).location
        return NPRefs.identify(url: root.appendingPathComponent(rel), text: text, offset: r.location + i + 1, root: root.path)
    }

    private static func refs(_ s: NPRefSymbol?, vendor: Bool = false, roots: Set<String>? = nil) -> NPRefsResult {
        guard let s else { return NPRefsResult() }
        var o = NPRefsOptions()
        o.includeVendor = vendor
        o.scan.roots = roots
        return NPRefs.collect(s, options: o)
    }

    private static func has(_ r: NPRefsResult, _ file: String, _ snippet: String, role: NPRefRole? = nil) -> Bool {
        r.hits.contains { $0.path.hasSuffix(file) && $0.snippet.contains(snippet) && (role == nil || $0.role == role) }
    }
    private static func count(_ r: NPRefsResult, _ file: String) -> Int { r.hits.filter { $0.path.hasSuffix(file) && $0.role != .unresolved }.count }
    private static func resolved(_ r: NPRefsResult) -> [NPRefHit] { r.hits.filter { $0.role != .unresolved } }

    static func run(w: ProjectWindow) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-nativerefs-\(getpid())")
        try? fm.removeItem(at: root)
        buildFixture(root)
        defer { try? fm.removeItem(at: root) }
        NPFiles.clear()
        let ctl = "app/Http/Controllers/PostController.php"

        // MARK: identify
        if case .symbol(let s) = id(root, "app/Models/Post.php", "function publish()", at: "publish") {
            check("identify method declaration", s.kind == .method && s.name == "publish" && s.fqn == "App\\Models\\Post")
        } else { check("identify method declaration", false) }
        if case .symbol(let s) = id(root, ctl, "$post->publish()", at: "publish") {
            check("identify method usage resolves to the declaring class", s.kind == .method && s.fqn == "App\\Models\\Post" && s.declPath.hasSuffix("app/Models/Post.php"))
        } else { check("identify method usage resolves to the declaring class", false) }
        if case .symbol(let s) = id(root, ctl, "$any->publish()", at: "publish") {
            check("identify via interface type hint", s.fqn == "App\\Contracts\\Publishable")
        } else { check("identify via interface type hint", false) }
        if case .unsupported = id(root, ctl, "$this->store(", at: "$this") { check("$this is not a symbol", true) } else { check("$this is not a symbol", false) }
        if case .unsupported = id(root, ctl, "$post->title;", at: "title") { check("database column: unsupported", true) } else { check("database column: unsupported", false) }
        if case .unsupported = id(root, ctl, "$mystery->publish()", at: "publish") { check("untyped receiver: unsupported or none", true) }
        else if case .none = id(root, ctl, "$mystery->publish()", at: "publish") { check("untyped receiver: unsupported or none", true) }
        else { check("untyped receiver: unsupported or none", false) }

        // MARK: find usages -- methods
        let publish = sym(root, "app/Models/Post.php", "function publish()", at: "publish")
        var r = refs(publish)
        check("method: declaration listed", has(r, "app/Models/Post.php", "function publish()", role: .declaration))
        check("method: typed usage", has(r, "PostController.php", "$post->publish()"))
        check("method: usage through the interface (ancestor)", has(r, "PostController.php", "$any->publish()"))
        check("method: interface declaration (ancestor)", has(r, "Contracts/Publishable.php", "function publish()", role: .declaration))
        check("method: blade usage via @var", has(r, "pub.blade.php", "$post->publish()"))
        check("method trap: unrelated sibling implementation not a usage", !has(r, "PostController.php", "$page->publish()") && !has(r, "Models/Page.php", "publish"))
        check("method trap: unrelated class with the same method", !has(r, "PostController.php", "$draft->publish()") && !has(r, "Legacy/Draft.php", "publish"))
        check("method trap: controller's own publish()", !r.hits.contains { $0.role != .unresolved && $0.snippet.contains("public function publish() { return $this->store") })
        check("method trap: route array callable of another class", !has(r, "routes/web.php", "'publish'"))
        check("method: untyped receiver reported as possible", has(r, "PostController.php", "$mystery->publish()", role: .unresolved))
        check("method: streams in file order", resolved(r).map(\.path) == resolved(r).map(\.path).sorted())

        // member families (rename): siblings under the interface are part of it
        let fp = FastProject.shared(root: root)
        let rel = NPRelations(fp: fp)
        check("hierarchy relations", rel.related("App\\Models\\Post", "App\\Contracts\\Publishable") && !rel.related("App\\Models\\Page", "App\\Models\\Post")
              && rel.related("App\\Models\\SubCounter", "App\\Models\\Counter"))
        r = refs(sym(root, "app/Contracts/Publishable.php", "function publish()", at: "publish"))
        check("interface method: implementations are related", has(r, "Models/Post.php", "function publish()", role: .declaration) && has(r, "Models/Page.php", "function publish()", role: .declaration))
        check("interface method: usages through implementations", has(r, "PostController.php", "$post->publish()") && has(r, "PostController.php", "$page->publish()") && has(r, "PostController.php", "$any->publish()"))
        check("interface method trap: Legacy Draft stays out", !has(r, "Legacy/Draft.php", "publish") && !has(r, "PostController.php", "$draft->publish()"))
        r = refs(sym(root, "app/Legacy/Draft.php", "function shortTitle()", at: "shortTitle"))
        check("same-named method on another class: only its own usages", has(r, "PostController.php", "$draft->shortTitle()") && !has(r, "PostController.php", "$post->shortTitle(5)"))
        r = refs(sym(root, "app/Models/Post.php", "function shortTitle(", at: "shortTitle"))
        check("shortTitle of Post: not Draft's", has(r, "PostController.php", "$post->shortTitle(5)") && !has(r, "PostController.php", "$draft->shortTitle()"))

        // scopes (virtual members)
        r = refs(sym(root, "app/Models/Post.php", "function scopePublished", at: "scopePublished"))
        check("scope: declaration + Post::published() usage", has(r, "Models/Post.php", "function scopePublished", role: .declaration) && has(r, "PostController.php", "Post::published()"))
        r = refs(sym(root, ctl, "Post::published()", at: "published"))
        check("scope usage identifies the scopeX declaration", has(r, "Models/Post.php", "function scopePublished"))

        // MARK: constants, enum cases, properties
        r = refs(sym(root, "app/Models/Post.php", "const MAX_TITLE", at: "MAX_TITLE"))
        check("const: declaration + usage", has(r, "Models/Post.php", "MAX_TITLE = 120", role: .declaration) && has(r, "PostController.php", "Post::MAX_TITLE"))
        check("const trap: same constant name on Draft/Page", !has(r, "PostController.php", "Draft::MAX_TITLE") && !has(r, "Models/Page.php", "MAX_TITLE") && !has(r, "Legacy/Draft.php", "MAX_TITLE"))
        r = refs(sym(root, "app/Enums/Status.php", "case Draft", at: "Draft"))
        check("enum case: declaration + usage", has(r, "Enums/Status.php", "case Draft", role: .declaration) && has(r, "PostController.php", "Status::Draft"))
        check("enum case trap: Draft class and 'draft' strings", !has(r, "PostController.php", "use App\\Legacy\\Draft") && !has(r, "Legacy/Draft.php", "class Draft"))
        r = refs(sym(root, "app/Models/Counter.php", "protected int $count", at: "$count"))
        check("property: declaration + this-> usages + subclass usages", has(r, "Models/Counter.php", "protected int $count", role: .declaration) && has(r, "Models/Counter.php", "$this->count++", role: .write)
              && has(r, "Models/Counter.php", "return $this->count", role: .read) && has(r, "SubCounter.php", "$this->count--"))
        check("property trap: Tally::$count", !has(r, "Models/Tally.php", "$count") && !has(r, "PostController.php", "$t->count"))
        r = refs(sym(root, "app/Models/Counter.php", "public static int $instances", at: "$instances"))
        check("static property: self::$instances", has(r, "Models/Counter.php", "self::$instances++") && has(r, "Models/Counter.php", "public static int $instances", role: .declaration))
        r = refs(sym(root, "app/Services/PostService.php", "private readonly Post $post", at: "$post"))
        check("promoted ctor property: usage via $this->post", has(r, "Services/PostService.php", "return $this->post") && has(r, "Services/PostService.php", "private readonly Post $post", role: .declaration))

        // MARK: functions
        r = refs(sym(root, "app/helpers.php", "function format_money", at: "format_money"))
        check("function: declaration + call", has(r, "app/helpers.php", "function format_money", role: .declaration) && has(r, "PostController.php", "format_money(100)"))
        check("function trap: method with the same name", !r.hits.contains { $0.snippet.contains("$cashier->format_money(1)") && $0.snippet.hasPrefix("public") } && !has(r, "Cashier.php", "format_money"))
        r = refs(sym(root, ctl, "format_money(100)", at: "format_money"))
        check("function usage identifies the helper declaration", has(r, "app/helpers.php", "function format_money", role: .declaration))
        r = refs(sym(root, "app/Cashier.php", "function format_money", at: "format_money"))
        check("method named like a helper: only the method's usages", has(r, "PostController.php", "$cashier->format_money(1)") && !has(r, "app/helpers.php", "format_money"))
        r = refs(sym(root, "app/helpers.php", "APP_EDITION", at: "APP_EDITION"))
        check("global const: declaration found", has(r, "app/helpers.php", "const APP_EDITION", role: .declaration))

        // MARK: classes
        let userSym = sym(root, "app/Models/User.php", "class User", at: "User")
        r = refs(userSym)
        check("class: declaration", has(r, "Models/User.php", "class User extends Model", role: .declaration))
        check("class: import line", has(r, "PostController.php", "use App\\Models\\User;", role: .import))
        check("class: import with alias", has(r, "PostController.php", "use App\\Models\\User as Account;"))
        check("class: alias usage (not editable)", r.hits.contains { $0.snippet.contains("Account::find(1)") && !$0.editable })
        check("class: new / ::class / type hint", has(r, "PostController.php", "new User()") && has(r, "PostController.php", "User::class") && has(r, "PostController.php", "User $owner, Cashier"))
        check("class: docblock @param", has(r, "PostController.php", "@param User $owner", role: .docblock))
        check("class: FQCN in strings (controller + config)", has(r, "PostController.php", "'App\\\\Models\\\\User'", role: .string) && has(r, "config/auth.php", "App\\\\Models\\\\User", role: .string))
        check("class: relation target in Post::user()", has(r, "Models/Post.php", "belongsTo(User::class)"))
        check("class trap: Legacy\\User in Report.php and Legacy/User.php", !r.hits.contains { $0.path.contains("/Legacy/") })
        check("class trap: plain 'user' string / variables", !has(r, "PostController.php", "'user'", role: .string))
        r = refs(sym(root, "app/Legacy/User.php", "class User", at: "User"))
        check("second class named User: only its own file group", r.hits.allSatisfy { $0.path.contains("/Legacy/") } && has(r, "Legacy/Report.php", "new User()"))
        r = refs(sym(root, ctl, "Account::find(1)", at: "Account"))
        check("usage through an alias identifies the class", has(r, "Models/User.php", "class User", role: .declaration))
        r = refs(sym(root, "app/Contracts/Publishable.php", "interface Publishable", at: "Publishable"))
        check("interface: implements + type hint + import", has(r, "Models/Post.php", "class Post extends Model implements Publishable") && has(r, "PostController.php", "Publishable $any") && has(r, "Models/Page.php", "use App\\Contracts\\Publishable;", role: .import))

        // MARK: local variables
        let titleSym = sym(root, ctl, "$title = Post::MAX_TITLE", at: "$title")
        check("variable: identified with its function scope", titleSym?.kind == .variable && (titleSym?.scopeFn ?? -1) > 0)
        r = refs(titleSym)
        check("variable: all uses in the method (write, interpolation, return)", resolved(r).count == 4 && has(r, ctl, "$title = Post::MAX_TITLE", role: .write) && has(r, ctl, "Hello $title and {$title}") && has(r, ctl, "return [$post, $page, $title"))
        check("variable trap: same name in another method untouched", !has(r, ctl, "$title = 'x'") && !has(r, ctl, "return $title . $post->title"))
        let postParam = sym(root, ctl, "Post $post, Page $page", at: "$post")
        r = refs(postParam)
        check("parameter: declaration + uses incl. docblock @param", has(r, ctl, "function store(Post $post", role: .declaration) && has(r, ctl, "$post->publish()") && has(r, ctl, "@param Post $post", role: .docblock))
        check("parameter trap: other method's $post parameter", !r.hits.contains { $0.snippet.contains("function other(Post $post)") || $0.snippet.contains("return $title . $post->title") })
        // closures / arrow functions
        put(root, "app/Closures.php", #"""
        <?php
        function demo(array $items) {
            $factor = 2;
            $a = array_map(function ($x) use ($factor) { return $x * $factor; }, $items);
            $b = array_map(fn($x) => $x * $factor, $items);
            $c = array_map(function ($factor) { return $factor + 1; }, $items);
            return $factor;
        }
        """#)
        let cl = read(root, "app/Closures.php") as NSString
        let off = cl.range(of: "$factor = 2").location + 2
        if case .symbol(let fs) = NPRefs.identify(url: root.appendingPathComponent("app/Closures.php"), text: cl, offset: off, root: root.path) {
            let cr = refs(fs)
            let lines = Set(cr.hits.map(\.line))
            check("closure: use() capture and arrow fn belong to the outer variable", lines.contains(3) && lines.contains(4) && lines.contains(5) && lines.contains(7))
            check("closure: shadowing parameter is a different variable", !lines.contains(6))
        } else { check("closure: use() capture and arrow fn belong to the outer variable", false) }

        // MARK: speed: 1500 usages in one big file
        var big = "<?php\nnamespace App\\Big;\nuse App\\Models\\Post;\nclass Big {\n"
        for n in 0..<1500 { big += "    public function m\(n)(Post $p): string { return $p->shortTitle(\(n)); }\n" }
        big += "}\n"
        put(root, "app/Big.php", big)
        let t0 = Date()
        r = refs(sym(root, "app/Models/Post.php", "function shortTitle(", at: "shortTitle"))
        let dt = Date().timeIntervalSince(t0)
        check("1500 usages in one file resolve (\(Int(dt * 1000)) ms)", count(r, "app/Big.php") == 1500 && dt < 8)
        try? fm.removeItem(at: root.appendingPathComponent("app/Big.php"))

        // MARK: caps and cancellation
        var opts = NPRefsOptions()
        opts.cap = 2
        let capped = NPRefs.collect(userSym!, options: opts)
        check("result cap truncates", capped.truncated && capped.resolvedCount == 2)
        let tok = CancelToken()
        tok.cancel()
        let cancelled = NPRefs.collect(userSym!, options: NPRefsOptions(), cancel: tok)
        check("cancelled search stops early", cancelled.cancelled && cancelled.hits.isEmpty)
        let cands = NPRefs.candidates(root: root.path, needles: ["max_title"], includeVendor: false, extra: [], cancel: nil).map { ($0 as NSString).lastPathComponent }
        check("prefilter is case-insensitive and bounded to PHP files", cands.contains("Post.php") && cands.contains("Draft.php") && !cands.contains("composer.json"))
        check("vendor is excluded by default", !NPRefs.candidates(root: root.path, needles: ["function save"], includeVendor: false, extra: [], cancel: nil).contains { $0.contains("/vendor/") }
              && NPRefs.candidates(root: root.path, needles: ["function save"], includeVendor: true, extra: [], cancel: nil).contains { $0.contains("/vendor/") })

        // MARK: UI list
        var shown: (String, [PickerItem])?
        NativePHPUI.presentHook = { shown = ($0, $1) }
        NativePHPUI.present(userSym!, result: refs(userSym), root: root.path, window: nil, vendorRerun: nil)
        NativePHPUI.presentHook = nil
        check("usages list: title counts + one row per hit", shown?.0.hasPrefix("Usages of App\\Models\\User (") == true && (shown?.1.count ?? 0) == refs(userSym).hits.count
              && shown?.1.contains { $0.detail.contains("app/Http/Controllers/PostController.php:") } == true)

        // MARK: rename -- validation + conflicts
        check("validate: bad identifier", NPRename.validate(userSym!, name: "1abc") != nil && NPRename.validate(userSym!, name: "a-b") != nil && NPRename.validate(userSym!, name: "") != nil)
        check("validate: reserved word / unchanged", NPRename.validate(userSym!, name: "class") != nil && NPRename.validate(userSym!, name: "User") != nil && NPRename.validate(userSym!, name: "Member") == nil)
        check("conflict: class already exists", NPRename.plan(userSym!, newName: "Comment").conflict?.contains("already exists") == true)
        check("conflict: import of another class with that name", NPRename.plan(userSym!, newName: "Post").conflict?.contains("already imports") == true)
        check("conflict: method name exists in the hierarchy", NPRename.plan(sym(root, "app/Models/Post.php", "function shortTitle(", at: "shortTitle")!, newName: "publish").conflict?.contains("already has a method") == true)
        check("conflict: property exists", NPRename.plan(sym(root, "app/Models/Counter.php", "protected int $count", at: "$count")!, newName: "instances").conflict?.contains("already has a property") == true)
        check("conflict: function exists", NPRename.plan(sym(root, "app/helpers.php", "function format_money", at: "format_money")!, newName: "route").conflict?.contains("already exists") == true)
        check("conflict: variable exists in scope", NPRename.plan(titleSym!, newName: "post").conflict?.contains("already exists") == true)
        check("conflict: const exists", NPRename.plan(sym(root, "app/Models/Post.php", "const MAX_TITLE", at: "MAX_TITLE")!, newName: "MAX_TITLE").conflict != nil)
        let scopeSym = sym(root, "app/Models/Post.php", "function scopePublished", at: "scopePublished")!
        check("scope: new name must start with scope", NPRename.validate(scopeSym, name: "live") != nil && NPRename.validate(scopeSym, name: "scopeLive") == nil)

        // vendor warning (plan only; nothing applied)
        let vendorSym = sym(root, "vendor/laravel/framework/src/Illuminate/Database/Eloquent/Model.php", "function fresh(", at: "fresh")
        check("vendor member identified as vendor", vendorSym?.inVendor == true)
        if let v = vendorSym {
            let vp = NPRename.plan(v, newName: "reload")
            check("vendor rename: warns and includes the vendor declaration", vp.warnings.contains { $0.contains("vendor/") } && vp.hits.contains { $0.role == .declaration && $0.path.contains("/vendor/") })
        }

        // MARK: rename -- apply
        // method family: Publishable::publish -> release
        var plan = NPRename.plan(sym(root, "app/Contracts/Publishable.php", "function publish()", at: "publish")!, newName: "release")
        check("method rename plan: no conflict, declarations + usages", plan.conflict == nil && plan.hits.filter { $0.role == .declaration }.count == 3 && plan.skipped.count >= 1)
        check("method rename plan: warns about untyped receiver", plan.warnings.contains { $0.contains("unknown receiver") })
        var res = NPRename.apply(plan, tabFor: { _ in nil })
        check("method rename applied", res.applied && res.files >= 4)
        check("method rename: Post, Page, interface, usages", read(root, "app/Models/Post.php").contains("function release(): void") && read(root, "app/Models/Page.php").contains("function release()")
              && read(root, "app/Contracts/Publishable.php").contains("function release(): void") && read(root, ctl).contains("$post->release();") && read(root, ctl).contains("$any->release();")
              && read(root, ctl).contains("$page->release();") && read(root, "resources/views/posts/pub.blade.php").contains("$post->release()"))
        check("method rename trap: Draft, controller publish(), untyped call, route untouched", read(root, "app/Legacy/Draft.php").contains("function publish()") && read(root, ctl).contains("$draft->publish();")
              && read(root, ctl).contains("public function publish()") && read(root, ctl).contains("$mystery->publish();") && read(root, "routes/web.php").contains("'publish'"))
        check("method rename: Post docs untouched elsewhere", read(root, "app/Models/Post.php").contains("scopePublished"))

        // route array callable + $this callable
        put(root, "app/Routes.php", "<?php\nnamespace App;\nuse App\\Http\\Controllers\\PostController;\nRoute::get('/a', [PostController::class, 'store']);\nclass K { function go() { return [$this, 'go']; } }\n")
        plan = NPRename.plan(sym(root, ctl, "function store(", at: "store")!, newName: "save")
        check("array callable strings are renamed", plan.conflict == nil && plan.hits.contains { $0.role == .string && $0.path.hasSuffix("routes/web.php") } && plan.hits.contains { $0.role == .string && $0.path.hasSuffix("app/Routes.php") })
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("array callable rename applied", res.applied && read(root, "routes/web.php").contains("[PostController::class, 'save']") && read(root, ctl).contains("function save(") && read(root, ctl).contains("$this->store(...)") == false)
        plan = NPRename.plan(sym(root, "app/Routes.php", "function go()", at: "go")!, newName: "run")
        check("[$this, 'go'] is renamed with the method", plan.conflict == nil && plan.hits.contains { $0.role == .string })

        // constants / enum case / property / promoted property
        plan = NPRename.plan(sym(root, "app/Models/Post.php", "const MAX_TITLE", at: "MAX_TITLE")!, newName: "TITLE_LIMIT")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("const rename: Post only", res.applied && read(root, "app/Models/Post.php").contains("TITLE_LIMIT = 120") && read(root, ctl).contains("Post::TITLE_LIMIT") && read(root, ctl).contains("Draft::MAX_TITLE")
              && read(root, "app/Models/Page.php").contains("MAX_TITLE = 80"))
        plan = NPRename.plan(sym(root, "app/Enums/Status.php", "case Draft", at: "Draft")!, newName: "Pending")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("enum case rename", res.applied && read(root, "app/Enums/Status.php").contains("case Pending") && read(root, "app/Enums/Status.php").contains("self::Pending") && read(root, ctl).contains("Status::Pending") && read(root, ctl).contains("use App\\Legacy\\Draft;"))
        plan = NPRename.plan(sym(root, "app/Models/Counter.php", "protected int $count", at: "$count")!, newName: "total")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("property rename: declaration, $this->, subclass; Tally untouched", res.applied && read(root, "app/Models/Counter.php").contains("protected int $total = 0") && read(root, "app/Models/Counter.php").contains("$this->total++")
              && read(root, "app/Models/SubCounter.php").contains("$this->total--") && read(root, "app/Models/Tally.php").contains("public int $count") && read(root, ctl).contains("$t->count = 3"))
        plan = NPRename.plan(sym(root, "app/Models/Counter.php", "public static int $instances", at: "$instances")!, newName: "created")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("static property rename keeps the $", res.applied && read(root, "app/Models/Counter.php").contains("public static int $created = 0") && read(root, "app/Models/Counter.php").contains("self::$created++"))
        plan = NPRename.plan(sym(root, "app/Services/PostService.php", "private readonly Post $post", at: "$post")!, newName: "article")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("promoted property rename (declaration + $this->)", res.applied && read(root, "app/Services/PostService.php").contains("private readonly Post $article") && read(root, "app/Services/PostService.php").contains("return $this->article"))

        // scope
        plan = NPRename.plan(sym(root, "app/Models/Post.php", "function scopePublished", at: "scopePublished")!, newName: "scopeLive")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("scope rename: declaration scopeLive + usage live()", res.applied && read(root, "app/Models/Post.php").contains("function scopeLive(") && read(root, ctl).contains("Post::live()"))

        // function
        plan = NPRename.plan(sym(root, "app/helpers.php", "function format_money", at: "format_money")!, newName: "money")
        check("function rename plan", plan.conflict == nil && plan.hits.contains { $0.role == .declaration })
        res = NPRename.apply(plan, tabFor: { _ in nil })
        check("function rename: helper + call; same-named method untouched", res.applied && read(root, "app/helpers.php").contains("function money(") && read(root, ctl).contains("money(100)") && read(root, ctl).contains("$cashier->format_money(1)")
              && read(root, "app/Cashier.php").contains("function format_money"))

        // local variable (only inside the method, interpolation + docblock)
        plan = NPRename.plan(sym(root, ctl, "$title = Post::TITLE_LIMIT", at: "$title")!, newName: "heading")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        let c1 = read(root, ctl)
        check("variable rename: this scope only", res.applied && c1.contains("$heading = Post::TITLE_LIMIT") && c1.contains("Hello $heading and {$heading}") && c1.contains("return [$post, $page, $heading") && c1.contains("$title = 'x'") && c1.contains("return $title . $post->title"))
        plan = NPRename.plan(sym(root, ctl, "Post $post, Page $page", at: "$post")!, newName: "entry")
        res = NPRename.apply(plan, tabFor: { _ in nil })
        let c2 = read(root, ctl)
        check("parameter rename: signature, body and @param", res.applied && c2.contains("function save(Post $entry,") && c2.contains("$entry->release();") && c2.contains("@param Post $entry") && c2.contains("function other(Post $post)"))

        // class rename: edits everywhere + PSR-4 file rename
        let uSym = sym(root, "app/Models/User.php", "class User", at: "User")!
        plan = NPRename.plan(uSym, newName: "Member")
        check("class rename plan: file rename + docblock + string hits", plan.conflict == nil && plan.fileRename?.to.hasSuffix("app/Models/Member.php") == true
              && plan.hits.contains { $0.role == .docblock } && plan.hits.contains { $0.role == .string } && plan.hits.contains { $0.role == .import } && !plan.hits.contains { $0.path.contains("/Legacy/") })
        check("class rename plan: alias usage is not edited", !plan.hits.contains { $0.snippet.contains("Account::find(1)") })
        res = NPRename.apply(plan, tabFor: { _ in nil })
        let c3 = read(root, ctl)
        check("class rename applied; file moved", res.applied && res.movedFile?.to.lastPathComponent == "Member.php" && fm.fileExists(atPath: root.appendingPathComponent("app/Models/Member.php").path)
              && !fm.fileExists(atPath: root.appendingPathComponent("app/Models/User.php").path))
        check("class rename: declaration", read(root, "app/Models/Member.php").contains("class Member extends Model"))
        check("class rename: use + alias import + new + ::class + type hint", c3.contains("use App\\Models\\Member;") && c3.contains("use App\\Models\\Member as Account;") && c3.contains("new Member()") && c3.contains("Member::class") && c3.contains("Member $owner"))
        check("class rename: alias usage keeps the alias", c3.contains("Account::find(1)"))
        check("class rename: docblock + strings", c3.contains("@param Member $owner") && c3.contains("'App\\\\Models\\\\Member'") && read(root, "config/auth.php").contains("App\\\\Models\\\\Member") && read(root, "app/Models/Post.php").contains("belongsTo(Member::class)"))
        check("class rename trap: Legacy User untouched", read(root, "app/Legacy/Report.php").contains("new User()") && read(root, "app/Legacy/User.php").contains("class User") && c3.contains("use App\\Legacy\\Draft;"))
        check("class rename: 'user' string and variable names untouched", c3.contains("'user'") && c3.contains("$u = new Member()"))
        NPFiles.clear()
        check("after rename the resolver finds the new class", FastProject.shared(root: root).queue.sync { FastProject.shared(root: root).beginRequest(); return FastProject.shared(root: root).classPath("App\\Models\\Member") } != nil)
        // conflicting import in a file
        put(root, "app/Imports.php", "<?php\nnamespace App;\nuse App\\Models\\Member;\nuse App\\Legacy\\Report as Foo;\nclass I { public function a(Member $m, Foo $f) {} }\n")
        let planConflict = NPRename.plan(sym(root, "app/Models/Member.php", "class Member", at: "Member")!, newName: "Foo")
        check("class rename: import collision in a file is refused", planConflict.conflict?.contains("already imports") == true)

        // open tab: edits go through the buffer (one undo group), nothing is written to disk
        let postPath = root.appendingPathComponent("app/Models/Page.php")
        w.open(postPath)
        if let tab = w.editors[postPath.standardizedFileURL.path] ?? w.editors[postPath.path] {
            let before = tab.textView.string
            var p2 = NPRename.plan(sym(root, "app/Models/Page.php", "const MAX_TITLE", at: "MAX_TITLE")!, newName: "PAGE_LIMIT")
            check("tab rename plan", p2.conflict == nil && p2.hits.count >= 1)
            let diskBefore = read(root, "app/Models/Page.php")
            res = NPRename.apply(p2, tabFor: { NPRefs.canon($0) == NPRefs.canon(postPath.path) ? tab : nil })
            check("tab rename: buffer changed, disk untouched", res.applied && tab.textView.string.contains("PAGE_LIMIT = 80") && read(root, "app/Models/Page.php") == diskBefore)
            tab.textView.undoManager?.undo()
            check("tab rename: one undo restores", tab.textView.string == before)
            p2.conflict = nil
            w.close(postPath.standardizedFileURL.path)
        } else { check("tab rename plan", false) }

        // wiring hooks (no window): rename flow prompt -> plan -> confirm -> apply
        var confirmed: NPRenamePlan?
        NativePHPUI.confirmHook = { p, done in confirmed = p; done(false) }
        NativePHPUI.promptHook = { _, done in done("Whatever") }
        var msgs: [String] = []
        NativePHPUI.messageHook = { msgs.append($0) }
        check("summary text", NativePHPUI.summary(plan).contains("occurrence"))
        NativePHPUI.confirmHook = nil; NativePHPUI.promptHook = nil; NativePHPUI.messageHook = nil
        _ = confirmed; _ = msgs

        check("file cache stays bounded after scans", NPFiles.cachedCount <= 6)
    }
}
