import AppKit

/// Headless checks for go-to-definition cases Intelephense answers that the native engine used to miss: conditional `@return`
/// helpers (`response()`, `redirect()`), ternary / `??` receivers, list destructuring from a same-file method, properties inside
/// interpolated strings, properties assigned from `new` in a constructor, and module migrations (`Modules/X/database/migrations`).
/// Snippets mark the pointer with `§`.
enum SelfTestNativePHPMisses {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("nativemiss: " + name, ok()) }
    private static func put(_ root: URL, _ rel: String, _ text: String) { SelfTestNativePHP.put(root, rel, text) }

    private static func buildFixture(_ root: URL) {
        put(root, "artisan", "#!/usr/bin/env php\n")
        put(root, "composer.json", #"{"require":{"laravel/framework":"^11"},"autoload":{"psr-4":{"App\\":"app/","Modules\\":"Modules/"}}}"#)
        put(root, "vendor/composer/autoload_psr4.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'Illuminate\\\\' => array($vendorDir . '/laravel/framework/src/Illuminate'),\n    'Vendor\\\\Svc\\\\' => array($vendorDir . '/svc/src'),\n    'App\\\\' => array($baseDir . '/app'),\n    'Modules\\\\' => array($baseDir . '/Modules'),\n);\n")
        put(root, "vendor/composer/autoload_files.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'a1' => $vendorDir . '/laravel/framework/src/Illuminate/Foundation/helpers.php',\n);\n")
        let il = "vendor/laravel/framework/src/Illuminate/"
        put(root, il + "Foundation/helpers.php", """
        <?php
        if (! function_exists('response')) {
            /**
             * @param  string|null  $content
             * @param  int  $status
             * @return ($content is null ? \\Illuminate\\Contracts\\Routing\\ResponseFactory : \\Illuminate\\Http\\Response)
             */
            function response($content = null, $status = 200, array $headers = [])
            {
            }
        }
        if (! function_exists('redirect')) {
            /**
             * @param  string|null  $to
             * @return ($to is null ? \\Illuminate\\Routing\\Redirector : \\Illuminate\\Http\\RedirectResponse)
             */
            function redirect($to = null, $status = 302)
            {
            }
        }
        if (! function_exists('pick')) {
            /**
             * @param  mixed  $v
             * @return ($v is string ? \\App\\Alpha : ($v is int ? \\App\\Beta : \\App\\Gamma))
             */
            function pick($v = null)
            {
            }
        }
        """)
        put(root, il + "Contracts/Routing/ResponseFactory.php", "<?php\nnamespace Illuminate\\Contracts\\Routing;\ninterface ResponseFactory {\n    public function json($data = [], $status = 200);\n}\n")
        put(root, il + "Http/Response.php", "<?php\nnamespace Illuminate\\Http;\nclass Response {\n    public function status() {}\n}\n")
        put(root, il + "Http/RedirectResponse.php", "<?php\nnamespace Illuminate\\Http;\nclass RedirectResponse {\n    public function with($key, $value = null) {}\n}\n")
        put(root, il + "Routing/Redirector.php", "<?php\nnamespace Illuminate\\Routing;\nclass Redirector {\n    /**\n     * @return \\Illuminate\\Http\\RedirectResponse\n     */\n    public function route($route) {}\n    public function away($path) {}\n}\n")
        put(root, "app/Alpha.php", "<?php\nnamespace App;\nclass Alpha {\n    public function alpha() {}\n}\n")
        put(root, "app/Beta.php", "<?php\nnamespace App;\nclass Beta {\n    public function beta() {}\n}\n")
        put(root, "app/Gamma.php", "<?php\nnamespace App;\nclass Gamma {\n    public function gamma() {}\n}\n")
        // untyped properties assigned from `new` (generated API client style)
        put(root, "vendor/svc/src/Client.php", "<?php\nnamespace Vendor\\Svc;\nclass Client {\n    public $messages;\n    public $other;\n    public function __construct() {\n        $this->messages = new Res\\Messages($this);\n        $this->other = new \\App\\Alpha();\n    }\n}\n")
        put(root, "vendor/svc/src/Res/Messages.php", "<?php\nnamespace Vendor\\Svc\\Res;\nclass Messages {\n    public function send($to) {}\n}\n")
        // module with its own migrations
        put(root, "Modules/Blog/app/Models/Article.php", "<?php\nnamespace Modules\\Blog\\app\\Models;\nuse Illuminate\\Database\\Eloquent\\Model;\nclass Article extends Model {\n    protected $table = 'articles';\n}\n")
        put(root, il + "Database/Eloquent/Model.php", "<?php\nnamespace Illuminate\\Database\\Eloquent;\nabstract class Model {\n    public function save() {}\n}\n")
        put(root, "Modules/Blog/database/migrations/2024_01_01_000000_create_articles_table.php", "<?php\nuse Illuminate\\Support\\Facades\\Schema;\nreturn new class extends Migration {\n    public function up() {\n        Schema::create('articles', function (Blueprint $table) {\n            $table->id();\n            $table->string('subtitle');\n        });\n    }\n};\n")
    }

    private static func lookup(_ root: URL, _ code: String, rel: String = "app/Http/Probe.php") -> NPHit? {
        let full = "<?php\nnamespace App\\Http;\n\nuse App\\Alpha;\nuse Modules\\Blog\\app\\Models\\Article;\nuse Vendor\\Svc\\Client;\n\nclass Probe {\n    private Client $client;\n    public function __construct(private string $name = 'x') {}\n    public function run(Article $article, $flag, $unknown) {\n        \(code)\n    }\n    private function pair() {\n        $a = new \\App\\Alpha();\n        return [$a, new \\App\\Beta(), 3];\n    }\n}\n"
        let off = (full as NSString).range(of: "§").location
        guard off != NSNotFound else { return nil }
        let clean = full.replacingOccurrences(of: "§", with: "")
        put(root, rel, clean)
        return NativePHP.lookup(url: root.appendingPathComponent(rel), text: clean as NSString, offset: off, root: root.path)
    }

    private static func file(_ h: NPHit?) -> String { (h?.targets.first?.path as NSString?)?.lastPathComponent ?? "" }

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-nativemiss-\(getpid())")
        try? fm.removeItem(at: root)
        buildFixture(root)
        defer { try? fm.removeItem(at: root) }
        NPFiles.clear()

        // conditional @return on helpers
        check("response()->json: no argument takes the default (null) branch", file(lookup(root, "return response()->js§on([]);")) == "ResponseFactory.php")
        check("response('x')->status: non-null argument takes the other branch", file(lookup(root, "return response('x')->sta§tus();")) == "Response.php")
        check("response($unknown): unknown argument gives no answer", lookup(root, "return response($unknown)->sta§tus();") == nil)
        check("redirect()->away", file(lookup(root, "return redirect()->aw§ay('x');")) == "Redirector.php")
        check("redirect()->route(..)->with: chain continues through a docblock return", file(lookup(root, "return redirect()->route('a')->wi§th('k', 'v');")) == "RedirectResponse.php")
        check("redirect('/x')->with: URL argument takes the RedirectResponse branch", file(lookup(root, "return redirect('/x')->wi§th('k');")) == "RedirectResponse.php")
        check("nested conditional: string", file(lookup(root, "return pick('a')->alp§ha();")) == "Alpha.php")
        check("nested conditional: int", file(lookup(root, "return pick(5)->bet§a();")) == "Beta.php")
        check("nested conditional: default branch not taken without argument knowledge", lookup(root, "return pick($unknown)->gam§ma();") == nil)
        check("nested conditional: array falls to the last branch", file(lookup(root, "return pick([])->gam§ma();")) == "Gamma.php")

        // ternary / coalesce receivers
        check("ternary with agreeing branches", file(lookup(root, "$x = $flag ? new Alpha : new Alpha();\n        $x->alp§ha();")) == "Alpha.php")
        check("ternary with different classes gives no answer", lookup(root, "$x = $flag ? new Alpha : new \\App\\Beta();\n        $x->alp§ha();") == nil)
        check("ternary with one unknown branch uses the known one", file(lookup(root, "$x = $flag ? new Alpha : $unknown;\n        $x->alp§ha();")) == "Alpha.php")
        check("coalesce", file(lookup(root, "$x = $unknown ?? new Alpha();\n        $x->alp§ha();")) == "Alpha.php")
        check("short ternary", file(lookup(root, "$x = $unknown ?: new Alpha();\n        $x->alp§ha();")) == "Alpha.php")
        check("ternary inside call arguments does not split the receiver", file(lookup(root, "$x = (new Alpha())->alp§ha($flag ? 1 : 2);")) == "Alpha.php")

        // list destructuring from a method of the same file
        check("list destructuring: element 1 of the returned array", file(lookup(root, "[$a, $b] = $this->pair();\n        $b->be§ta();")) == "Beta.php")
        check("list destructuring: element 0", file(lookup(root, "[$a, $b] = $this->pair();\n        $a->alp§ha();")) == "Alpha.php")
        check("list(): same", file(lookup(root, "list($a, $b) = $this->pair();\n        $b->be§ta();")) == "Beta.php")
        check("list destructuring: scalar element gives no answer", lookup(root, "[$a, $b, $c] = $this->pair();\n        $c->be§ta();") == nil)
        check("array element assignment is not a destructuring", lookup(root, "$arr[$flag] = new Alpha();\n        $flag->alp§ha();") == nil)

        // properties inside double-quoted strings
        let nameHit = lookup(root, "return \"Hello $this->na§me today\";")
        check("interpolated $this->prop (simple syntax)", file(nameHit) == "Probe.php" && nameHit?.kind == "property")
        check("interpolated {$a->b->c} chain", file(lookup(root, "return \"x {$this->client->mess§ages} y\";")) == "Client.php")
        check("single-quoted string is not interpolated", lookup(root, "return 'Hello $this->na§me today';") == nil)

        // untyped property assigned from `new` in the owner's file
        check("property typed by constructor assignment (relative name)", file(lookup(root, "$this->client->messages->se§nd('me');")) == "Messages.php")
        check("property typed by constructor assignment (absolute name)", file(lookup(root, "$this->client->other->alp§ha();")) == "Alpha.php")

        // module migrations
        let col = lookup(root, "return $article->sub§title;")
        check("column declared in a module migration", col != nil && col?.targets.first?.path.contains("Modules/Blog/database/migrations/") == true)
    }
}
