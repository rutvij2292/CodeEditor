import AppKit

/// Headless checks for the native PHP service (NativePHP*.swift): go to definition + hover on a realistic Laravel fixture.
/// Snippets mark the pointer with `§` (removed before lookup).
enum SelfTestNativePHP {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("native: " + name, ok()) }

    static func put(_ root: URL, _ rel: String, _ text: String) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    static func buildFixture(_ root: URL) {
        put(root, "artisan", "#!/usr/bin/env php\n")
        put(root, "composer.json", #"{"require":{"laravel/framework":"^11"},"autoload":{"psr-4":{"App\\":"app/"},"files":["app/helpers.php"]}}"#)
        put(root, "vendor/composer/autoload_psr4.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'Illuminate\\\\' => array($vendorDir . '/laravel/framework/src/Illuminate'),\n    'App\\\\' => array($baseDir . '/app'),\n);\n")
        put(root, "vendor/composer/autoload_files.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'a1' => $vendorDir . '/laravel/framework/src/Illuminate/Foundation/helpers.php',\n    'b2' => $baseDir . '/app/helpers.php',\n);\n")
        let il = "vendor/laravel/framework/src/Illuminate/"
        put(root, il + "Foundation/helpers.php", """
        <?php
        if (! function_exists('route')) {
            /**
             * Generate the URL to a named route.
             *
             * @param  array|string  $name
             * @param  mixed  $parameters
             * @param  bool  $absolute
             * @return string
             */
            function route($name, $parameters = [], $absolute = true)
            {
                return '';
            }
        }

        if (! function_exists('view')) {
            /**
             * Get the evaluated view contents for the given view.
             */
            function view($view = null, $data = [], $mergeData = []): string
            {
                return '';
            }
        }
        """)
        put(root, il + "Database/Eloquent/Model.php", """
        <?php
        namespace Illuminate\\Database\\Eloquent;
        /**
         * @mixin \\Illuminate\\Database\\Eloquent\\Builder
         */
        abstract class Model {
            /**
             * Save the model to the database.
             *
             * @param  array  $options
             * @return bool
             */
            public function save(array $options = []): bool { return true; }
            public function fresh($with = []) { return $this; }
            protected function internal() {}
            public static function create(array $attributes = []): static { return new static; }
            public function hasMany($related, $foreignKey = null) {}
            public function belongsTo($related, $foreignKey = null) {}
        }
        """)
        put(root, il + "Database/Eloquent/Builder.php", """
        <?php
        namespace Illuminate\\Database\\Eloquent;
        class Builder {
            /**
             * Add a basic where clause to the query.
             *
             * @param  string  $column
             * @param  mixed  $operator
             * @return $this
             */
            public function where($column, $operator = null, $value = null) { return $this; }
            public function get($columns = ['*']) {}
            public function first($columns = ['*']) {}
        }
        """)
        put(root, il + "Database/Query/Builder.php", "<?php\nnamespace Illuminate\\Database\\Query;\nclass Builder {\n    public function whereIn($column, $values) { return $this; }\n    public function orderBy($column, $direction = 'asc') { return $this; }\n}\n")
        put(root, il + "Support/Collection.php", "<?php\nnamespace Illuminate\\Support;\nclass Collection {\n    public function map(callable $callback) { return new static; }\n    public function first(callable $callback = null, $default = null) {}\n}\n")
        put(root, il + "Support/Facades/Facade.php", "<?php\nnamespace Illuminate\\Support\\Facades;\nabstract class Facade {\n    public static function __callStatic($method, $args) {}\n}\n")
        put(root, il + "Support/Facades/Cache.php", """
        <?php
        namespace Illuminate\\Support\\Facades;

        /**
         * @method static mixed get(string $key, mixed $default = null)
         * @method static bool forgetAll()
         *
         * @see \\Illuminate\\Cache\\CacheManager
         */
        class Cache extends Facade {}
        """)
        put(root, il + "Cache/CacheManager.php", """
        <?php
        namespace Illuminate\\Cache;
        class CacheManager {
            /**
             * Retrieve an item from the cache by key.
             *
             * @param  string  $key
             * @param  mixed  $default
             * @return mixed
             */
            public function get($key, $default = null) {}
        }
        """)
        put(root, il + "Http/Request.php", "<?php\nnamespace Illuminate\\Http;\nclass Request {\n    public function input($key = null, $default = null) {}\n}\n")
        put(root, "app/helpers.php", "<?php\n\nconst APP_EDITION = 'pro';\ndefine('APP_VERSION', '1.0');\n\n/**\n * Format cents as a currency string.\n *\n * @param int $cents Amount in cents\n * @return string\n */\nfunction format_money(int $cents): string { return ''; }\n")
        put(root, "database/migrations/2024_01_01_000000_create_posts_table.php", """
        <?php
        return new class extends Migration {
            public function up(): void {
                Schema::create('posts', function (Blueprint $table) {
                    $table->id();
                    $table->string('title')->nullable();
                    $table->text('body');
                    $table->foreignId('user_id')->constrained();
                    $table->string('status')->default('draft');
                    $table->timestamps();
                });
            }
        };
        """)
        put(root, "database/migrations/2024_01_02_000000_create_users_table.php", """
        <?php
        return new class extends Migration {
            public function up(): void {
                Schema::create('users', function (Blueprint $table) {
                    $table->id();
                    $table->string('name');
                    $table->string('email')->unique();
                });
            }
        };
        """)
        put(root, "app/Enums/Status.php", """
        <?php
        namespace App\\Enums;
        enum Status: string {
            const DEFAULT = self::Draft;
            case Draft = 'draft';
            case Published = 'published';
            public function label(): string { return ucfirst($this->value); }
        }
        """)
        put(root, "app/Contracts/Publishable.php", """
        <?php
        namespace App\\Contracts;
        interface Publishable {
            const VERSION = 2;
            /** Publish the thing. */
            public function publish(): void;
        }
        """)
        put(root, "app/Models/HasSlug.php", "<?php\nnamespace App\\Models;\ntrait HasSlug {\n    /**\n     * Build a URL slug.\n     */\n    public function slugify(string $value): string { return ''; }\n}\n")
        put(root, "app/Models/User.php", """
        <?php
        namespace App\\Models;

        use Illuminate\\Database\\Eloquent\\Model;

        class User extends Model {
            use HasSlug;
            protected $fillable = ['name', 'email'];
            public function posts() { return $this->hasMany(Post::class); }
            public function getFullNameAttribute() { return $this->name; }
            public function scopeActive($query) { return $query->where('active', 1); }
        }
        """)
        put(root, "app/Models/Comment.php", "<?php\nnamespace App\\Models;\nuse Illuminate\\Database\\Eloquent\\Model;\nclass Comment extends Model {}\n")
        put(root, "app/Models/Post.php", """
        <?php
        namespace App\\Models;

        use App\\Contracts\\Publishable;
        use App\\Enums\\Status;
        use Illuminate\\Database\\Eloquent\\Model;

        /**
         * A blog post.
         *
         * @property-read int $comment_count
         */
        class Post extends Model implements Publishable {
            public const MAX_TITLE = 120;
            protected $casts = ['status' => Status::class];
            /** The author. */
            public function user() { return $this->belongsTo(User::class); }
            public function comments() { return $this->hasMany(Comment::class); }
            public function scopePublished($query) { return $query->where('status', 'published'); }
            public function publish(): void {}
            /**
             * Short title.
             *
             * @return string
             */
            public function shortTitle(int $max = 20): string { return ''; }
        }
        """)
        put(root, "app/Services/PostService.php", """
        <?php
        namespace App\\Services;

        use App\\Models\\Post;

        class PostService {
            public function __construct(private readonly Post $post) {}
            public function current(): Post { return $this->post; }
        }
        """)
        put(root, "resources/views/posts/show.blade.php", "x")
    }

    private struct Hit { var hit: NPHit?; var root: URL }

    /// Looks up the symbol at `§` in `src` as if it were the content of `rel`.
    private static func at(_ root: URL, _ rel: String, _ src: String) -> NPHit? {
        let off = (src as NSString).range(of: "§").location
        guard off != NSNotFound else { return nil }
        let clean = src.replacingOccurrences(of: "§", with: "")
        put(root, rel, clean)       // the editor buffer is normally saved: targets inside this file read the same text
        return NativePHP.lookup(url: root.appendingPathComponent(rel), text: clean as NSString, offset: off, root: root.path)
    }

    private static let ctl = "app/Http/Controllers/PostController.php"
    private static let imports = "<?php\nnamespace App\\Http\\Controllers;\n\nuse App\\Models\\Post;\nuse App\\Models\\User as Account;\nuse App\\Enums\\Status;\nuse App\\Contracts\\Publishable;\nuse App\\Services\\PostService;\nuse Illuminate\\Support\\Facades\\Cache;\n\n"

    /// Source line at the first target (trimmed) -- what the editor would land on.
    private static func landing(_ h: NPHit?) -> String {
        guard let t = h?.targets.first, let text = try? String(contentsOfFile: t.path, encoding: .utf8) else { return "" }
        let ns = text as NSString
        return ns.substring(with: ns.lineRange(for: NSRange(location: min(t.offset, max(0, ns.length - 1)), length: 0))).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func path(_ h: NPHit?) -> String { h?.targets.first?.path ?? "" }

    private static func body(_ code: String, params: String = "Post $post") -> String {
        imports + "class PostController {\n    public function __construct(private PostService $service) {}\n    public function show(\(params)) {\n        \(code)\n    }\n}\n"
    }

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-nativephp-\(getpid())")
        try? fm.removeItem(at: root)
        buildFixture(root)
        defer { try? fm.removeItem(at: root) }
        NPFiles.clear()

        // MARK: classes
        var h = at(root, ctl, imports.replacingOccurrences(of: "App\\Models\\Post;", with: "App\\Models\\Po§st;") + "class A {}\n")
        check("use line -> class", path(h).hasSuffix("app/Models/Post.php") && landing(h).hasPrefix("class Post"))
        h = at(root, ctl, imports.replacingOccurrences(of: "Models\\User as Account", with: "Models\\Us§er as Account") + "class A {}\n")
        check("use X as Y: X -> class", path(h).hasSuffix("app/Models/User.php"))
        h = at(root, ctl, imports.replacingOccurrences(of: "User as Account", with: "User as Acc§ount") + "class A {}\n")
        check("use alias name -> class", path(h).hasSuffix("app/Models/User.php"))
        h = at(root, ctl, body("$a = new Acc§ount();"))
        check("alias in new -> class", path(h).hasSuffix("app/Models/User.php"))
        h = at(root, ctl, body("$x = 1;", params: "Po§st $post"))
        check("type hint -> class", path(h).hasSuffix("app/Models/Post.php"))
        h = at(root, ctl, body("$x = Po§st::query();"))
        check("static call receiver -> class", path(h).hasSuffix("app/Models/Post.php"))
        h = at(root, ctl, body("$x = new Po§st;"))
        check("new without parens -> class", path(h).hasSuffix("app/Models/Post.php"))
        h = at(root, ctl, imports + "class A extends Po§st {}\n")
        check("extends -> class", path(h).hasSuffix("app/Models/Post.php"))
        h = at(root, ctl, imports + "class A implements Publi§shable, \\Countable {}\n")
        check("implements -> interface", path(h).hasSuffix("app/Contracts/Publishable.php") && landing(h).hasPrefix("interface"))
        h = at(root, ctl, imports + "class A implements \\Countable, Publi§shable {}\n")
        check("second implements entry -> interface", path(h).hasSuffix("app/Contracts/Publishable.php"))
        h = at(root, ctl, body("try { } catch (\\Exce§ption $e) {}"))
        check("catch builtin: stub declaration + hover", h != nil && PHPStubs.isStubFile(h!.targets.first?.path ?? "") && h!.markdown.contains("class Exception"))
        h = at(root, ctl, body("$s = Status::Dra§ft;"))
        check("enum case -> case line", path(h).hasSuffix("app/Enums/Status.php") && landing(h).hasPrefix("case Draft"))
        h = at(root, ctl, body("$s = Sta§tus::Draft;"))
        check("enum name -> enum", landing(h).hasPrefix("enum Status"))
        h = at(root, ctl, body("$s = Status::DEF§AULT;"))
        check("class const -> const line", landing(h).contains("const DEFAULT"))
        h = at(root, ctl, body("$s = Post::MAX_§TITLE;"))
        check("model const", landing(h).contains("MAX_TITLE = 120"))
        h = at(root, ctl, body("$s = Post::VERS§ION;"))
        check("interface const through implements", path(h).hasSuffix("Publishable.php") && landing(h).contains("VERSION"))
        h = at(root, ctl, body("$s = Post::cla§ss;"))
        check("::class -> class", landing(h).hasPrefix("class Post"))
        h = at(root, ctl, body("$f = 'App\\\\Models\\\\Po§st';"))
        check("class name in string", path(h).hasSuffix("app/Models/Post.php"))
        h = at(root, ctl, imports + "/**\n * @param \\App\\Models\\Po§st $p\n */\nfunction f($p) {}\n")
        check("docblock @param type", path(h).hasSuffix("app/Models/Post.php"))
        h = at(root, ctl, imports + "/**\n * @return Acc§ount|null\n */\nfunction f() {}\n")
        check("docblock @return alias", path(h).hasSuffix("app/Models/User.php"))
        h = at(root, ctl, body("$r = \\Illuminate\\Http\\Req§uest::class;"))
        check("fully qualified vendor class -> vendor file", path(h).contains("vendor/laravel/framework/src/Illuminate/Http/Request.php"))
        h = at(root, ctl, body("$x = Nope§Class::make();"))
        check("unknown class -> nil", h == nil)

        // MARK: members
        h = at(root, ctl, body("$post->comm§ents;"))
        check("relation property -> relation method", path(h).hasSuffix("app/Models/Post.php") && landing(h).contains("function comments"))
        check("relation hover mentions relation", h?.markdown.contains("Eloquent relation") == true)
        h = at(root, ctl, body("$post->user->full_na§me;"))
        check("accessor attribute -> getXAttribute", path(h).hasSuffix("app/Models/User.php") && landing(h).contains("getFullNameAttribute"))
        h = at(root, ctl, body("$post->ti§tle;"))
        check("column -> migration line", path(h).contains("database/migrations") && landing(h).contains("string('title')"))
        h = at(root, ctl, body("$post->created_§at;"))
        check("timestamps column -> timestamps()", landing(h).contains("timestamps()"))
        h = at(root, ctl, body("$post->i§d;"))
        check("id column", landing(h).contains("$table->id()"))
        check("column hover has type + table", h?.markdown.contains("posts") == true)
        h = at(root, ctl, body("$post->sa§ve();"))
        check("inherited vendor method", path(h).contains("Eloquent/Model.php") && landing(h).contains("function save"))
        h = at(root, ctl, body("$post->shortTit§le();"))
        check("own method", path(h).hasSuffix("app/Models/Post.php") && landing(h).contains("function shortTitle"))
        h = at(root, ctl, body("Post::publi§shed()->get();"))
        check("scope -> scopeX method", landing(h).contains("function scopePublished"))
        h = at(root, ctl, body("Post::wh§ere('a', 1);"))
        check("static where -> Eloquent Builder", path(h).contains("Eloquent/Builder.php") && landing(h).contains("function where"))
        h = at(root, ctl, body("Post::published()->wh§ere('a', 1);"))
        check("scope chain -> builder where", path(h).contains("Eloquent/Builder.php"))
        h = at(root, ctl, body("$post->user->posts()->wh§ere('a', 1);"))
        check("relation call -> builder where", path(h).contains("Eloquent/Builder.php"))
        h = at(root, ctl, body("$post->user->pos§ts;"))
        check("chained relation", landing(h).contains("function posts"))
        h = at(root, ctl, body("$u = Account::find(1); $u->slug§ify('x');"))
        check("trait method", path(h).hasSuffix("HasSlug.php") && landing(h).contains("function slugify"))
        h = at(root, ctl, body("Account::act§ive()->get();"))
        check("scope on User", path(h).hasSuffix("User.php") && landing(h).contains("scopeActive"))
        h = at(root, ctl, body("$this->service->curr§ent();"))
        check("promoted ctor property method", path(h).hasSuffix("PostService.php") && landing(h).contains("function current"))
        h = at(root, ctl, body("$this->serv§ice;"))
        check("promoted property decl", path(h).hasSuffix(ctl) && landing(h).contains("PostService $service"))
        h = at(root, ctl, body("$this->service->current()->shortTi§tle();"))
        check("method return type chain", landing(h).contains("function shortTitle"))
        h = at(root, ctl, body("$p->publ§ish();", params: "Publishable $p"))
        check("interface method via type hint", path(h).hasSuffix("Publishable.php") && landing(h).contains("function publish"))
        h = at(root, ctl, body("Status::Draft->lab§el();"))
        check("enum method", landing(h).contains("function label"))
        h = at(root, ctl, body("Cache::ge§t('k');"))
        check("facade static -> underlying manager via @see", path(h).contains("Cache/CacheManager.php") && landing(h).contains("function get"))
        h = at(root, ctl, body("Cache::forget§All();"))
        check("facade @method tag fallback", path(h).hasSuffix("Facades/Cache.php") && landing(h).contains("forgetAll"))
        h = at(root, ctl, body("$post->comment_cou§nt;"))
        check("@property-read docblock tag", landing(h).contains("@property-read") && landing(h).contains("comment_count"))
        h = at(root, ctl, body("Post::query()->where('ti§tle', 1);"))
        check("column in string argument", landing(h).contains("string('title')"))
        h = at(root, ctl, body("Post::with('com§ments')->get();"))
        check("relation name in with()", landing(h).contains("function comments"))
        h = at(root, ctl, body("Post::with('user.po§sts')->get();"))
        check("dotted relation name", landing(h).contains("function posts"))
        h = at(root, ctl, body("$post->nothing§here();"))
        check("unknown member -> nil", h == nil)

        // self / static / parent in a class
        put(root, "app/Base.php", "<?php\nnamespace App;\nclass Base {\n    public const KIND = 'b';\n    protected static $registry = [];\n    public function boot() {}\n}\n")
        let kid = "app/Kid.php"
        let kidHead = "<?php\nnamespace App;\n\nclass Kid extends Base {\n"
        h = at(root, kid, kidHead + "    public function go() { $this->bo§ot(); }\n}\n")
        check("$this->inheritedMethod", landing(h).contains("function boot") && path(h).hasSuffix("app/Base.php"))
        h = at(root, kid, kidHead + "    public function boot() { parent::bo§ot(); }\n}\n")
        check("parent::method", landing(h).contains("function boot") && path(h).hasSuffix("app/Base.php"))
        h = at(root, kid, kidHead + "    public function boot() { }\n    public function go() { return $this->bo§ot(); }\n}\n")
        check("own method in the live buffer", path(h).hasSuffix("app/Kid.php") && h?.targets.first?.line == 5 && landing(h).contains("function boot"))
        h = at(root, kid, kidHead + "    public function go() { return self::KI§ND . static::KIND; }\n}\n")
        check("self::CONST inherited", landing(h).contains("KIND = 'b'"))
        h = at(root, kid, kidHead + "    public function go() { return static::$regi§stry; }\n}\n")
        check("static::$prop", landing(h).contains("$registry"))
        h = at(root, kid, kidHead + "    public function go() { return $th§is; }\n}\n")
        check("$this -> class", landing(h).hasPrefix("class Kid"))

        // MARK: functions + constants + variables
        h = at(root, ctl, body("rou§te('home');"))
        check("vendor helper function -> helpers.php", path(h).hasSuffix("Foundation/helpers.php") && landing(h).contains("function route("))
        check("helper hover has docblock summary + @param", h?.markdown.contains("Generate the URL to a named route.") == true && h?.markdown.contains("@param") == true)
        h = at(root, ctl, body("$s = format_mo§ney(100);"))
        check("user helper (composer autoload files)", path(h).hasSuffix("app/helpers.php") && landing(h).contains("function format_money"))
        check("user helper hover signature", h?.markdown.contains("function format_money(int $cents): string") == true)
        h = at(root, ctl, body("$s = str_con§tains('a', 'b');"))
        check("builtin function: stub declaration + signature", h != nil && PHPStubs.isStubFile(h!.targets.first?.path ?? "") && h!.markdown.contains("str_contains(string $haystack"))
        h = at(root, ctl, body("$s = PHP_E§OL;"))
        check("builtin constant: stub declaration + doc", h != nil && PHPStubs.isStubFile(h!.targets.first?.path ?? "") && h!.markdown.contains("PHP_EOL") && h!.markdown.contains("End-of-line"))
        h = at(root, ctl, body("$s = APP_VERS§ION;"))
        check("define()d constant", path(h).hasSuffix("app/helpers.php") && landing(h).contains("define('APP_VERSION'"))
        h = at(root, ctl, body("$s = APP_EDI§TION;"))
        check("top-level const", landing(h).contains("const APP_EDITION"))
        h = at(root, ctl, body("$a = Post::find(1);\n        $b = $§a->title;"))
        check("variable -> its assignment", landing(h).contains("$a = Post::find(1)"))
        h = at(root, ctl, body("$z = $po§st->title;"))
        check("variable -> parameter", landing(h).contains("show(Post $post)"))
        check("variable hover shows type", h?.markdown.contains("App\\Models\\Post") == true)
        h = at(root, ctl, body("return §;"))
        check("keyword -> nil", h == nil)

        // MARK: hover content
        h = at(root, ctl, body("$post->shortTit§le();"))
        check("method hover: signature", h?.markdown.contains("public function shortTitle(int $max = 20): string") == true)
        check("method hover: docblock summary", h?.markdown.contains("Short title.") == true)
        check("method hover: origin", h?.markdown.contains("app/Models/Post.php:") == true && h?.markdown.contains("App\\Models\\Post") == true)
        h = at(root, ctl, body("$post->sa§ve();"))
        check("vendor method hover: @param/@return trimmed", h?.markdown.contains("Save the model to the database.") == true && h?.markdown.contains("**@return** `bool`") == true && h?.markdown.contains("vendor/laravel") == true)
        h = at(root, ctl, body("$x = Po§st::query();"))
        check("class hover: header + docblock + origin", h?.markdown.contains("class Post extends Model implements Publishable") == true && h?.markdown.contains("A blog post.") == true && h?.markdown.contains("app/Models/Post.php") == true)
        h = at(root, ctl, body("$x = Sta§tus::Draft;"))
        check("enum hover lists cases", h?.markdown.contains("`Draft`") == true && h?.markdown.contains("`Published`") == true)
        h = at(root, ctl, body("$post->us§er;"))
        check("property doc comment summary (relation docblock)", h?.markdown.contains("The author.") == true)

        // MARK: Blade
        let bl = "resources/views/posts/show.blade.php"
        h = at(root, bl, "@php\n    /** @var \\App\\Models\\Post $post */\n@endphp\n<h1>{{ $post->tit§le }}</h1>\n")
        check("blade {{ }} column via @var", landing(h).contains("string('title')"))
        h = at(root, bl, "@php $posts = \\App\\Models\\Post::all(); @endphp\n@foreach ($posts as $post)\n  <p>{{ $post->comm§ents->count() }}</p>\n@endforeach\n")
        check("blade foreach var typing", landing(h).contains("function comments"))
        h = at(root, bl, "@php $x = \\App\\Models\\Po§st::first(); @endphp\n")
        check("blade @php block class", path(h).hasSuffix("Models/Post.php"))
        h = at(root, bl, "<p>Po§st title</p>\n")
        check("blade plain HTML text -> nil", h == nil)
        h = at(root, bl, "{{-- Po§st --}}\n")
        check("blade comment -> nil", h == nil)
        h = at(root, bl, "@if (\\App\\Models\\Po§st::count() > 0) yes @endif\n")
        check("blade directive args", path(h).hasSuffix("Models/Post.php"))
        h = at(root, bl, "<div>{{ rou§te('home') }}</div>\n")
        check("blade function", path(h).hasSuffix("helpers.php"))
        h = at(root, ctl, imports + "?>\n<p>Po§st</p>\n")
        check("plain php template HTML -> nil", h == nil)

        // MARK: speed on a big file
        var big = imports + "class Big {\n"
        for n in 0..<4000 { big += "    public function m\(n)(Post $p): string { return $p->title . \"x\"; }\n" }
        big += "    public function last(Post $post) { return $post->comm§ents; }\n}\n"
        let t0 = Date()
        h = at(root, "app/Big.php", big)
        let dt = Date().timeIntervalSince(t0)
        check("4000-method file resolves (\(Int(dt * 1000)) ms)", landing(h).contains("function comments") && dt < 1.5)

        // MARK: bounds, prefs, API
        check("file cache stays bounded", NPFiles.cachedCount <= 6)
        let counts = NPFuncIndex.shared(root: root.path).counts
        check("function index (helpers) found route/view/format_money", counts.functions >= 3 && counts.files == 2 && counts.constants >= 2)
        let before = NativePHP.nativeOnly
        NativePHP.nativeOnly = true
        check("nativeOnly pref disables intelephense start", LanguageServerPrefs.isEnabled("intelephense") == false && LanguageServers.isEnabled("intelephense") == false)
        NativePHP.nativeOnly = false
        check("nativeOnly off keeps default", LanguageServerPrefs.isEnabled("intelephense") == true || UserDefaults.standard.object(forKey: "lsp.intelephense.enabled") != nil)
        NativePHP.nativeOnly = before
        check("handles php, phtml, blade; not js", NativePHP.handles(URL(fileURLWithPath: "/x/a.php")) && NativePHP.handles(URL(fileURLWithPath: "/x/a.blade.php")) && !NativePHP.handles(URL(fileURLWithPath: "/x/a.js")))
        let doc = NPDoc.parse("/**\n * Summary line one\n * continues.\n *\n * @param  string  $a  First\n *   wrapped\n * @return int|null Count\n * @throws \\RuntimeException\n * @deprecated Use other\n */")
        check("docblock parse", doc.summary == "Summary line one continues." && doc.params.first?.name == "$a" && doc.params.first?.text == "First wrapped" && doc.ret?.type == "int|null" && doc.throwsList == ["\\RuntimeException"] && doc.deprecated == "Use other")
        NPFiles.clear()
    }
}
