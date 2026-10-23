import AppKit

/// Headless checks for native PHP diagnostics (NativePHPDiag*.swift). The valid-code fixtures matter most: every rule must stay
/// silent on realistic Laravel code.
enum SelfTestNativePHPDiag {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("diag: " + name, ok()) }

    private static var root = URL(fileURLWithPath: "/")

    private static func run(_ code: String, path: String = "app/Http/Controllers/T.php", groups: Set<NPDiagGroup> = Set(NPDiagGroup.allCases),
                            severity: Int = 2) -> [NPDiag] {
        let url = root.appendingPathComponent(path)
        let text = NSString(string: code)
        let fp = FastProject.shared(root: root)
        return fp.queue.sync { NativePHPDiag.analyze(url: url, text: text, fp: fp, groups: groups, classSeverity: severity) }
    }

    private static func codes(_ code: String, path: String = "app/Http/Controllers/T.php", groups: Set<NPDiagGroup> = Set(NPDiagGroup.allCases)) -> [String] {
        run(code, path: path, groups: groups).map { $0.code }
    }

    private static func messages(_ code: String, groups: Set<NPDiagGroup> = Set(NPDiagGroup.allCases)) -> [String] {
        run(code, groups: groups).map { $0.message }
    }

    private static let head = "<?php\n\nnamespace App\\Http\\Controllers;\n\nuse App\\Models\\Post;\nuse App\\Models\\User;\nuse App\\Enums\\Status;\nuse Illuminate\\Http\\Request;\n\n"

    /// A class wrapper with the standard imports; `body` is the class body (members).
    private static func cls(_ body: String, uses: String = "", extends: String = "") -> String {
        head + uses + "class T\(extends.isEmpty ? "" : " extends " + extends)\n{\n\(body)\n}\n"
    }

    /// Statements inside a public method with `$request`, `$post` typed parameters.
    private static func method(_ statements: String, params: String = "Request $request, Post $post") -> String {
        cls("    public function go(\(params))\n    {\n\(statements)\n    }")
    }

    /// Developer aid: `CE_DIAG_SCAN=/path/to/laravel/project` prints every native finding of its PHP files to stderr and exits.
    /// Used to hunt false positives on real code (nothing is written).
    static func scanProject(_ path: String) {
        let rootURL = URL(fileURLWithPath: path)
        let fp = FastProject.shared(root: rootURL)
        VendorIndex.shared(for: rootURL).refreshIfNeeded(force: true)
        VendorIndex.shared(for: rootURL).waitUntilIdle()
        var files: [String] = []
        for dir in (AppEnv.value("CE_DIAG_SCAN_DIRS").flatMap { $0.isEmpty ? nil : $0.split(separator: ",").map(String.init) } ?? ["app", "routes", "database", "config", "tests", "src", "lib", "includes"]) {
            let base = path + "/" + dir
            guard let en = FileManager.default.enumerator(atPath: base) else { continue }
            for case let rel as String in en where rel.hasSuffix(".php") && !rel.hasSuffix(".blade.php") { files.append(base + "/" + rel) }
        }
        files = Array(files.sorted().prefix(Int(AppEnv.value("CE_DIAG_SCAN_MAX") ?? "1500") ?? 1500))
        var byCode: [String: Int] = [:]
        var worst = 0.0
        for f in files {
            guard let t = FastProject.read(f) else { continue }
            let t0 = Date()
            let list = fp.queue.sync { NativePHPDiag.analyze(url: URL(fileURLWithPath: f), text: t, fp: fp) }
            let took = Date().timeIntervalSince(t0)
            worst = max(worst, took)
            if took > 0.4 { fputs("SCAN SLOW \(Int(took * 1000)) ms \(f.dropFirst(path.count + 1)) (\(t.length) chars)\n", stderr) }
            let table = NPLineStarts(t)
            for d in list {
                byCode[d.code, default: 0] += 1
                let pos = table.position(of: d.range.location)
                fputs("SCAN \(d.code) \(f.dropFirst(path.count + 1)):\(pos.line):\(pos.col) \(d.message) | \(t.substring(with: table_lineRange(t, d.range.location)).trimmingCharacters(in: .whitespaces).prefix(110))\n", stderr)
            }
        }
        fputs("SCAN SUMMARY files=\(files.count) worstMs=\(Int(worst * 1000)) \(byCode.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))\n", stderr)
    }

    private static func table_lineRange(_ t: NSString, _ loc: Int) -> NSRange { t.lineRange(for: NSRange(location: min(loc, max(0, t.length - 1)), length: 0)) }

    static func run() {
        if let p = AppEnv.value("CE_DIAG_SCAN") { scanProject(p); exit(0) }
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("ce-nativediag-\(getpid())")
        try? fm.removeItem(at: root)
        SelfTestNativePHP.buildFixture(root)
        defer { try? fm.removeItem(at: root) }
        // A realistic Model: magic __call / __get like Laravel's.
        SelfTestNativePHP.put(root, "vendor/laravel/framework/src/Illuminate/Database/Eloquent/Model.php", """
        <?php
        namespace Illuminate\\Database\\Eloquent;
        abstract class Model {
            public function save(array $options = []): bool { return true; }
            public function __call($method, $parameters) {}
            public static function __callStatic($method, $parameters) {}
            public function __get($key) {}
            public function __set($key, $value) {}
        }
        """)
        SelfTestNativePHP.put(root, "app/Http/Controllers/PostController.php", "<?php\nnamespace App\\Http\\Controllers;\nclass PostController {}\n")
        SelfTestNativePHP.put(root, "app/Services/Plain.php", "<?php\nnamespace App\\Services;\nclass Plain {\n    public function __construct(private string $name, private int $age = 3) {}\n    public function greet(string $who, string $punct = '!'): string { return ''; }\n    public static function make(int $n): self { return new self('x'); }\n    public function name() { return $this->name; }\n}\n")
        SelfTestNativePHP.put(root, "app/Services/Magic.php", "<?php\nnamespace App\\Services;\nclass Magic {\n    public function __call($m, $a) {}\n    public function real() {}\n}\n")
        SelfTestNativePHP.put(root, "app/Services/Documented.php", "<?php\nnamespace App\\Services;\n/**\n * @method static void shout()\n * @property string $label\n */\nclass Documented {}\n")
        SelfTestNativePHP.put(root, "app/Services/Child.php", "<?php\nnamespace App\\Services;\nclass Child extends Plain implements \\Countable {\n    public function count(): int { return 0; }\n    public function extra() {}\n}\n")
        SelfTestNativePHP.put(root, "app/Services/Orphan.php", "<?php\nnamespace App\\Services;\nclass Orphan extends \\Missing\\Base {\n    public function mine() {}\n}\n")
        SelfTestNativePHP.put(root, "app/Services/WithTrait.php", "<?php\nnamespace App\\Services;\nuse App\\Models\\HasSlug;\nclass WithTrait {\n    use HasSlug { slugify as protected makeSlug; }\n    public function own() {}\n}\n")
        let il = "vendor/laravel/framework/src/Illuminate/"
        SelfTestNativePHP.put(root, il + "Support/Facades/DB.php", "<?php\nnamespace Illuminate\\Support\\Facades;\nclass DB extends Facade {}\n")
        SelfTestNativePHP.put(root, il + "Support/Facades/Route.php", "<?php\nnamespace Illuminate\\Support\\Facades;\nclass Route extends Facade {}\n")
        SelfTestNativePHP.put(root, il + "Database/Eloquent/Relations/HasMany.php", "<?php\nnamespace Illuminate\\Database\\Eloquent\\Relations;\nclass HasMany {}\n")
        SelfTestNativePHP.put(root, il + "Database/Migrations/Migration.php", "<?php\nnamespace Illuminate\\Database\\Migrations;\nabstract class Migration {}\n")
        SelfTestNativePHP.put(root, il + "Database/Schema/Blueprint.php", "<?php\nnamespace Illuminate\\Database\\Schema;\nclass Blueprint {}\n")
        SelfTestNativePHP.put(root, il + "Support/Facades/Schema.php", "<?php\nnamespace Illuminate\\Support\\Facades;\nclass Schema extends Facade {}\n")
        SelfTestNativePHP.put(root, il + "Console/Command.php", "<?php\nnamespace Illuminate\\Console;\nclass Command { public function __call($m, $a) {} }\n")
        FastProject.shared(root: root).markDirty()
        NPFiles.clear()
        VendorIndex.shared(for: root).refreshIfNeeded(force: true)
        VendorIndex.shared(for: root).waitUntilIdle()           // deterministic: the vendor index is either loaded or not before any check runs

        syntaxChecks()
        classChecks()
        importChecks()
        variableChecks()
        memberChecks()
        argChecks()
        validLaravel()
        settingsAndMerge()
        bounds()
    }

    // MARK: Syntax

    private static func syntaxChecks() {
        let syn: Set<NPDiagGroup> = [.syntax]
        func s(_ code: String) -> [NPDiag] { run(code, groups: syn) }
        check("syntax: valid file is silent", s(cls("    public function a(): int { return 1; }")).isEmpty)
        let missingSemi = s("<?php\nfunction a() {\n    $x = 1\n    return $x;\n}\n")
        check("syntax: missing semicolon reported", !missingSemi.isEmpty && missingSemi[0].code == "syntax" && missingSemi[0].severity == 1)
        check("syntax: missing semicolon points at the previous line", missingSemi.first.map { (("<?php\nfunction a() {\n    $x = 1\n    return $x;\n}\n" as NSString).substring(to: $0.range.location).filter { $0 == "\n" }.count) } == 2)
        check("syntax: message mentions the expected token", missingSemi.first?.message.contains("';'") == true || missingSemi.first?.message.contains("unexpected") == true)
        let unclosed = s("<?php\nclass A {\n    public function a() {\n        return 1;\n    }\n")
        check("syntax: unclosed brace reported", !unclosed.isEmpty)
        let paren = s("<?php\n$x = foo(1, 2;\n")
        check("syntax: unclosed paren reported", !paren.isEmpty)
        let stray = s("<?php\nfunction a() {\n    return ];\n}\n")
        check("syntax: stray token reported", !stray.isEmpty)
        let two = s("<?php\nfunction a() {\n    $x = ;\n    $y = ;\n    $z = ;\n}\n")
        check("syntax: one finding per line, bounded", two.count <= NPDiagSyntax.maxErrors && Set(two.map { $0.range.location }).count == two.count)
        let cascade = s("<?php\nclass A {\n    public function a() {\n        $x = (1 + ;\n        foreach ($a as $b) {\n            echo $b\n        }\n    }\n}\n")
        check("syntax: no cascade of follow-up errors", cascade.count <= 2)
        check("syntax: semantic rules are skipped when syntax is broken", codes("<?php\nnamespace App;\nuse Foo\\Unused;\nnew Nope(;\n").allSatisfy { $0 == "syntax" })
        check("syntax: empty file is silent", run("").isEmpty)
        check("syntax: html around php tags is fine", s("<html>\n<?php if ($a): ?>\n  <b><?= $a ?></b>\n<?php endif; ?>\n</html>\n").isEmpty)
        check("syntax: Blade files are never analysed", run("<?php\n$x = ;\n", path: "resources/views/a.blade.php").isEmpty)
        // modern syntax must parse
        check("syntax: enum + match + readonly + first-class callable", s("""
        <?php
        enum Suit: string { case H = 'h'; case S = 's';
            public function label(): string { return match($this) { self::H => 'Hearts', self::S => 'Spades' }; } }
        final class P { public function __construct(public readonly int $x = 0) {} }
        $f = strlen(...);
        $g = $p->method(...);
        $h = P::make(...);
        """).isEmpty)
        check("syntax: attributes, named args, nullsafe, spread", s("""
        <?php
        #[Attribute(Attribute::TARGET_CLASS)]
        class A { public function __construct(#[SensitiveParameter] public ?string $v = null) {} }
        $x = $a?->b?->c(name: 'x', ...$rest);
        """).isEmpty)
        check("syntax: heredoc / nowdoc", s("<?php\n$a = <<<EOT\nHello {$name} and $other\nEOT;\n$b = <<<'RAW'\nraw $x\nRAW;\n").isEmpty)
        check("syntax: closures, arrow fns, static, union and intersection types", s("""
        <?php
        $f = static fn(int|string $a, A&B $b): ?int => $a;
        $g = function () use (&$x): void {};
        function t(): never { throw new Exception('x'); }
        """).isEmpty)
        check("syntax: the grammar's blind spots are vetoed by php -l when available", {
            guard NPDiagPHPLint.phpPath != nil else { return true }
            return s("<?php\nfunction f($h) {\n    return (string) match (true) {\n        count($h) < 2 => null,\n        default => 'x',\n    };\n}\n").isEmpty
        }())
        check("syntax: php -l agrees on real errors", { () -> Bool in
            guard NPDiagPHPLint.phpPath != nil else { return true }
            return NPDiagPHPLint.accepts("<?php\n$x = ;\n" as NSString) == false && NPDiagPHPLint.accepts("<?php\n$x = 1;\n" as NSString) == true
        }())
        check("syntax: without php the tree-sitter result stands", {
            let saved = NPDiagPHPLint.overridePath
            NPDiagPHPLint.overridePath = .some(nil)
            defer { NPDiagPHPLint.overridePath = saved }
            return !s("<?php\nfunction a() {\n    $x = 1\n    return $x;\n}\n").isEmpty && NPDiagPHPLint.accepts("<?php\n$x = ;\n" as NSString) == nil
        }())
        check("syntax: IDE stub files are never analysed", run("<?php\n$x = ;\n", path: ".phpstorm.meta.php").isEmpty && run("<?php\n$x = ;\n", path: "_ide_helper.php").isEmpty)
        check("syntax: PHP 8.4 property hooks", s("""
        <?php
        class U {
            public string $name { get => strtoupper($this->name); set(string $v) { $this->name = trim($v); } }
            public int $n { get { return 1; } }
        }
        """).isEmpty)
        check("syntax: PHP 8.4 asymmetric visibility", s("<?php\nclass U {\n    public private(set) string $name = 'x';\n    public protected(set) int $n = 1;\n}\n").isEmpty)
        check("syntax: PHP 8.4 new without parentheses chain", s("<?php\n$x = new Foo()->bar();\n$y = (new Foo)->baz();\n").isEmpty)
        check("syntax: readonly class and typed constants", s("<?php\nreadonly class R { public function __construct(public int $a) {} }\nclass C { const string X = 'a'; }\n").isEmpty)
    }

    // MARK: Undefined classes

    private static func classChecks() {
        let cl: Set<NPDiagGroup> = [.classes]
        func c(_ code: String) -> [String] { messages(code, groups: cl) }
        check("class: new of an undefined class", c(method("        $a = new Nope();")) == ["Undefined class 'Nope'"])
        check("class: reported as warning by default, error when configured",
              run(method("        $a = new Nope();"), groups: cl).first?.severity == 2 && run(method("        $a = new Nope();"), groups: cl, severity: 1).first?.severity == 1)
        check("class: imported project class is fine", c(method("        $a = new Post(); $u = new User();")).isEmpty)
        check("class: vendor class via use", c(method("        $r = new Request();")).isEmpty)
        check("class: unimported project class in a namespaced file is reported", c(method("        $a = new Comment();")) == ["Undefined class 'Comment'"])
        check("class: fully qualified project class", c(method("        $a = new \\App\\Models\\Comment();")).isEmpty)
        check("class: fully qualified undefined class", c(method("        $a = new \\App\\Models\\Nope();")) == ["Undefined class 'App\\Models\\Nope'"])
        check("class: global builtins with leading backslash", c(method("        $a = new \\DateTime(); throw new \\RuntimeException('x');")).isEmpty)
        check("class: unimported builtin in a namespace is reported (PHP would fail)", c(method("        $a = new DateTime();")) == ["Undefined class 'DateTime'"])
        check("class: builtins via use", c(cls("    public function a(): DateTimeInterface { return new DateTimeImmutable(); }", uses: "use DateTimeInterface;\nuse DateTimeImmutable;\n")).isEmpty)
        check("class: type hint parameter", c(method("        return;", params: "Nope $x")) == ["Undefined class 'Nope'"])
        check("class: nullable and union type hints", c(method("        return;", params: "?Nope $x, Post|Gone $y")) == ["Undefined class 'Nope'", "Undefined class 'Gone'"])
        check("class: builtin type names are never classes", c(method("        return;", params: "int $a, ?string $b, array|bool $c, callable $d, iterable $e, mixed $f, self $g, object $h")).isEmpty)
        check("class: return type", c(cls("    public function a(): Nope { }")) == ["Undefined class 'Nope'"])
        check("class: nullable and static return types", c(cls("    public function a(): ?Post { }\n    public function b(): static { }\n    public function c(): void { }")).isEmpty)
        check("class: property type", c(cls("    private Nope $a;\n    public ?Post $b = null;\n    protected readonly User $c;")) == ["Undefined class 'Nope'"])
        check("class: promoted constructor parameter type", c(cls("    public function __construct(private Nope $a, private readonly Post $b) {}")) == ["Undefined class 'Nope'"])
        check("class: extends and implements", c(head + "class T extends Gone implements Post, Missing {}\n") == ["Undefined class 'Gone'", "Undefined class 'Missing'"])
        check("class: interface extends list", c(head + "interface I extends Post, Absent {}\n") == ["Undefined class 'Absent'"])
        check("class: catch with alternatives", c(method("        try { } catch (\\Exception | Lost $e) { }")) == ["Undefined class 'Lost'"])
        check("class: instanceof", c(method("        if ($post instanceof Nada) { }")) == ["Undefined class 'Nada'"])
        check("class: static call and ::class", c(method("        Nope::make(); $n = Gone::class;")) == ["Undefined class 'Nope'", "Undefined class 'Gone'"])
        check("class: self / static / parent are fine", c(cls("    public function a() { self::x(); static::y(); parent::z(); return new static; }", extends: "Post")).isEmpty)
        check("class: trait use in class body", c(cls("    use Lacking;\n    use \\App\\Models\\HasSlug;")) == ["Undefined class 'Lacking'"])
        check("class: attribute names", c(head + "#[Absent]\n#[\\Attribute]\nclass T {\n    #[Post(1), Gone]\n    public function a() {}\n}\n") == ["Undefined class 'Absent'", "Undefined class 'Gone'"])
        check("class: closure and arrow function types", c(method("        $f = function (Nope $a): Gone { }; $g = fn(Missing $m) => 1;")) == ["Undefined class 'Nope'", "Undefined class 'Gone'", "Undefined class 'Missing'"])
        check("class: class declared in the same file", c(head + "class Local {}\nclass T extends Local { public function a(Local $l): Local { return new Local; } }\n").isEmpty)
        check("class: enum and interface declared in the same file", c(head + "enum E { case A; }\ninterface Ifc {}\nclass T implements Ifc { public function a(E $e) { return E::A; } }\n").isEmpty)
        check("class: alias import", c(head + "use App\\Models\\Comment as Remark;\nclass T { public function a(Remark $r) { return new Remark; } }\n").isEmpty)
        check("class: undefined import is reported once on the use line, not at each use",
              c(head + "use App\\Models\\Absent;\nclass T { public function a(Absent $x) { return new Absent; } }\n") == ["Undefined class 'App\\Models\\Absent'"])
        check("class: partial namespace alias", c(head + "use App\\Models;\nclass T { public function a(Models\\Post $x, Models\\Gone $y) {} }\n") == ["Undefined class 'Models\\Gone'"])
        check("class: group use", c(head.replacingOccurrences(of: "use App\\Models\\Post;\nuse App\\Models\\User;\n", with: "use App\\Models\\{Post, User, Nonexistent};\n") + "class T { public function a(Post $p, User $u) {} }\n") == ["Undefined class 'App\\Models\\Nonexistent'"])
        check("class: use function / const imports are not classes", c(head + "use function App\\helper;\nuse const App\\FOO;\nclass T {}\n").isEmpty)
        check("class: global namespace file is conservative for bare names", c("<?php\n$a = new Whatever();\nRoute::get('/', fn() => 1);\n").isEmpty)
        check("class: facade imports", c(method("        Cache::get('k');", params: "Request $r").replacingOccurrences(of: "use Illuminate\\Http\\Request;\n", with: "use Illuminate\\Http\\Request;\nuse Illuminate\\Support\\Facades\\Cache;\n")).isEmpty)
        check("class: Facades\\ real-time facade names", c(head + "use Facades\\App\\Services\\Thing;\nclass T { public function a() { return Thing::go(); } }\n").isEmpty)
        check("class: namespace-relative and function calls are not class refs", c(method("        $x = namespace\\Sub\\fn1(); foo(); strlen('a'); $y = Post::query();")).isEmpty)
        check("class: docblock-only mentions are never checked", c(cls("    /** @param Nope $x @return Gone */\n    public function a($x) {}")).isEmpty)
        check("class: strings are not class references", c(method("        $s = 'new Nope()'; $t = \"Nope::go\";")).isEmpty)
        check("class: constants and enum cases are not class refs", c(method("        $a = PHP_EOL . E_ALL . SORT_ASC; $s = Status::Draft; $t = Status::Published;")).isEmpty)
        check("class: named arguments are not class refs", c(method("        $x = $post->update(title: 'a', body: 'b'); $r = foo(name: Post::class);")).isEmpty)
        check("class: multiple namespaces in one file are skipped", c("<?php\nnamespace A { class X { function f(Nope $n) {} } }\nnamespace B { class Y {} }\n").isEmpty)
        check("class: class_alias files are skipped", c("<?php\nnamespace A;\nclass_alias(\\B\\C::class, 'A\\D');\nclass X { function f(D $d, Nope $n) {} }\n").isEmpty)
        check("class: HTML templates mixing text and PHP are not analysed semantically", c("<html>\n<body>Use the following format <?php echo $x; ?>\n</body></html>\n").isEmpty && c("Use this text\n<?php new Nope(); ?>").isEmpty)
        check("class: pure code files with a closing tag are analysed", c("<?php\nnamespace App;\nclass A { function f(Nope $n) {} }\n?>\n") == ["Undefined class 'Nope'"])
        check("class: code file with a shebang line", c("#!/usr/bin/env php\n<?php\nnamespace App;\nclass A { function f(Nope $n) {} }\n") == ["Undefined class 'Nope'"])
        check("class: Composer namespace and global autoload-file classes are known", c(method("        $a = \\Composer\\InstalledVersions::getVersion('x');")).isEmpty)
        check("class: Blade file is skipped", run("<?php new Nope();", path: "resources/views/x.blade.php", groups: cl).isEmpty)
        check("class: names outside the project prefixes are judged only once the vendor index is loaded", {
            let ready = VendorIndex.shared(for: root).isReady
            return c("<?php\nnamespace Tests\\Feature;\nclass ExampleTest { public function a(Foo $x) {} }\n") == (ready ? ["Undefined class 'Foo'"] : [])
        }())
        check("class: range covers exactly the name", { () -> Bool in
            let code = method("        $a = new Nope();")
            guard let d = run(code, groups: cl).first else { return false }
            return (code as NSString).substring(with: d.range) == "Nope"
        }())
    }

    // MARK: Imports

    private static func importChecks() {
        let im: Set<NPDiagGroup> = [.imports]
        func i(_ code: String) -> [NPDiag] { run(code, groups: im) }
        let base = "<?php\nnamespace App\\Http\\Controllers;\n\n"
        let unused = i(base + "use App\\Models\\Post;\nuse App\\Models\\User;\n\nclass T { public function a(Post $p) {} }\n")
        check("import: unused import is a hint", unused.count == 1 && unused[0].severity == 4 && unused[0].code == "unused-import" && unused[0].message == "Unused import 'App\\Models\\User'")
        check("import: range covers the imported name", { () -> Bool in
            let code = base + "use App\\Models\\User;\nclass T {}\n"
            guard let d = i(code).first else { return false }
            return (code as NSString).substring(with: d.range) == "App\\Models\\User"
        }())
        check("import: used in a type hint, new, static, extends, catch, instanceof, attribute, ::class, trait",
              i(base + "use A\\One; use A\\Two; use A\\Three; use A\\Four; use A\\Five; use A\\Six; use A\\Seven; use A\\Eight; use A\\Nine;\n#[Nine]\nclass T extends Four { use Eight; public function a(One $a) { new Two; Three::x(); try {} catch (Five $e) {} if ($a instanceof Six) {} return Seven::class; } }\n").isEmpty)
        check("import: used only in a docblock", i(base + "use App\\Models\\Post;\nuse App\\Models\\User;\n/** @var Post $x */\nclass T { /** @param User $u */ public function a($u) {} }\n").isEmpty)
        check("import: used only as a namespace prefix", i(base + "use App\\Models;\nclass T { public function a(Models\\Post $p) {} }\n").isEmpty)
        check("import: alias use", i(base + "use App\\Models\\Post as Article;\nclass T { public function a(Article $p) {} }\n").isEmpty)
        check("import: unused alias reported by alias, not by class name", { () -> Bool in
            let r = i(base + "use App\\Models\\Post as Article;\nclass T { public function a(Post $p) {} }\n")
            return r.count == 1 && r[0].code == "unused-import"
        }())
        check("import: group use entries are checked individually", { () -> Bool in
            let r = i(base + "use App\\Models\\{Post, User, Comment};\nclass T { public function a(Post $p, Comment $c) {} }\n")
            return r.count == 1 && r[0].message == "Unused import 'App\\Models\\User'"
        }())
        check("import: function and const imports are never reported", i(base + "use function App\\helper;\nuse const App\\FOO;\nclass T {}\n").isEmpty)
        check("import: duplicate import", { () -> Bool in
            let r = i(base + "use App\\Models\\Post;\nuse App\\Models\\Post;\nclass T { public function a(Post $p) {} }\n")
            return r.count == 1 && r[0].code == "duplicate-import" && r[0].severity == 2
        }())
        check("import: duplicate import is case-insensitive on the name", i(base + "use App\\Models\\Post;\nuse app\\models\\post;\nclass T { public function a(Post $p) {} }\n").map { $0.code } == ["duplicate-import"])
        check("import: same short name from two namespaces is an error", { () -> Bool in
            let r = i(base + "use App\\Models\\Post;\nuse Other\\Post;\nclass T { public function a(Post $p) {} }\n")
            return r.count == 1 && r[0].severity == 1 && r[0].message.contains("already in use")
        }())
        check("import: closure use() is not an import", i(base + "use App\\Models\\Post;\nclass T { public function a(Post $p) { $x = 1; return function () use ($x) { return $x; }; } }\n").isEmpty)
        check("import: trait use in the class is not an import", i(base + "use App\\Models\\HasSlug;\nclass T { use HasSlug; }\n").isEmpty)
        check("import: string mentions count as a use (conservative)", i(base + "use App\\Models\\Post;\nclass T { public function a() { return 'Post'; } }\n").isEmpty)
        check("import: no imports -> nothing", i(base + "class T {}\n").isEmpty)
        check("import: imports in multi-namespace files are skipped", i("<?php\nnamespace A { use X\\Unused; class Q {} }\nnamespace B { class R {} }\n").isEmpty)
        check("import: unused import in a global-namespace file", i("<?php\nuse App\\Models\\User;\nclass T {}\n").map { $0.code } == ["unused-import"])
        check("import: Optimize imports (PHPImports) removes what the diagnostic reports", {
            let code = base + "use App\\Models\\Post;\nuse App\\Models\\User;\n\nclass T { public function a(Post $p) {} }\n"
            guard let e = PHPImports.optimize(code as NSString) else { return false }
            let out = (code as NSString).replacingCharacters(in: e.range, with: e.text)
            return !out.contains("App\\Models\\User") && out.contains("App\\Models\\Post")
        }())
    }

    // MARK: Variables

    private static func variableChecks() {
        let vr: Set<NPDiagGroup> = [.variables]
        func v(_ stmts: String, params: String = "Request $request") -> [String] { messages(method(stmts, params: params), groups: vr) }
        check("var: undefined variable read", v("        return $usre->name;") == ["Undefined variable '$usre'"])
        check("var: every read is reported", v("        echo $a; echo $a;").count == 2)
        check("var: parameters are defined", v("        return $request->input('a');").isEmpty)
        check("var: assignment defines", v("        $x = 1; return $x;").isEmpty)
        check("var: definition after the read is accepted (flow-insensitive)", v("        echo $x; $x = 1;").isEmpty)
        check("var: compound assignments define", v("        $s .= 'a'; $n += 1; $c ??= []; return [$s, $n, $c];").isEmpty)
        check("var: increment defines", v("        $i++; ++$j; return $i + $j;").isEmpty)
        check("var: subscript assignment defines", v("        $a['k'] = 1; $b[] = 2; return [$a, $b];").isEmpty)
        check("var: foreach key and value", v("        foreach ($request->all() as $k => $val) { echo $k, $val; }").isEmpty)
        check("var: foreach destructuring and by reference", v("        foreach ($request->all() as [$a, $b]) { echo $a, $b; } foreach ($request->all() as &$r) { echo $r; }").isEmpty)
        check("var: foreach over an undefined list", v("        foreach ($items as $i) { echo $i; }") == ["Undefined variable '$items'"])
        check("var: list and short destructuring", v("        [$a, $b] = [1, 2]; list($c, $d) = [3, 4]; ['k' => $e] = ['k' => 1]; return $a + $b + $c + $d + $e;").isEmpty)
        check("var: catch variable", v("        try { } catch (\\Exception $e) { return $e->getMessage(); }").isEmpty)
        check("var: closure use and parameters", v("        $y = 1; $f = function ($a) use ($y) { return $a + $y; }; return $f(2);").isEmpty)
        check("var: closure does not see the outer scope", v("        $y = 1; $f = function () { return $y; }; return $f;") == ["Undefined variable '$y'"])
        check("var: use by reference defines in both scopes", v("        $f = function () use (&$count) { $count++; }; $f(); return $count;").isEmpty)
        check("var: arrow function sees the parent scope and its own parameters", v("        $m = 2; $f = fn($x) => $x * $m; return $f(1);").isEmpty)
        check("var: nested arrow functions", v("        $m = 2; $f = fn($x) => fn($y) => $x + $y + $m; return $f;").isEmpty)
        check("var: global and static declarations", v("        global $conf; static $cache = []; return [$conf, $cache];").isEmpty)
        check("var: isset / empty / ?? / unset never report", v("        if (isset($a) || empty($b)) {} $c = $d ?? 1; $e = $f['x']['y'] ?? null; unset($g); return $c . $e;").isEmpty)
        check("var: passed to a function (possible by-reference output)", v("        preg_match('/a/', 'a', $m); return $m;").isEmpty)
        check("var: by-reference marker", v("        $a = &$b; return $a;").isEmpty)
        check("var: extract disables the check for the scope", v("        extract($request->all()); return $name;").isEmpty)
        check("var: include / require disable the check", v("        include 'x.php'; return $fromInclude;").isEmpty)
        check("var: compact only reads (no define)", v("        $a = 1; return compact('a');").isEmpty)
        check("var: variable variables disable the check", v("        $n = 'a'; $$n = 1; return $a;").isEmpty)
        check("var: get_defined_vars disables the check", v("        $a = 1; return get_defined_vars() + [$b];").isEmpty)
        check("var: superglobals and $this", v("        return [$_GET, $_POST, $_SERVER, $_ENV, $_SESSION, $_COOKIE, $_FILES, $_REQUEST, $GLOBALS, $this];").isEmpty)
        check("var: @var docblock asserts a variable", v("        /** @var \\App\\Models\\Post $injected */\n        return $injected->title;").isEmpty)
        check("var: static property access is not a variable", v("        return Post::$table . self::$count . static::$x;").isEmpty)
        check("var: dynamic property name is a read", v("        return $request->$prop;") == ["Undefined variable '$prop'"])
        check("var: while assignment", v("        while ($row = array_shift($queue)) { echo $row; }") .isEmpty)
        check("var: assignment in a condition", v("        if (($u = $request->user()) !== null) { return $u; }").isEmpty)
        check("var: for loop", v("        for ($i = 0, $n = 3; $i < $n; $i++) { echo $i; }").isEmpty)
        check("var: match / ternary / null-safe", v("        $x = 1; return match ($x) { 1 => $x, default => $x ?: 0 };").isEmpty)
        check("var: string interpolation is not scanned", v("        $a = 1; return \"value {$a} and $b\";").isEmpty)
        check("var: heredoc is not scanned", v("        $a = 1; return <<<EOT\n  $a and $zzz\n  EOT;").isEmpty)
        check("var: top-level script scope is ignored", codes("<?php\necho $anything;\n$x = $y;\n", groups: vr).isEmpty)
        check("var: class property declarations are not reads", codes(cls("    public $a;\n    protected static $b = 1;\n    private ?int $c = null;"), groups: vr).isEmpty)
        check("var: abstract / interface methods have no body", codes(head + "abstract class T { abstract public function a($x): void; }\ninterface I { public function b($y); }\n", groups: vr).isEmpty)
        check("var: promoted constructor parameters", codes(cls("    public function __construct(private Post $post, protected readonly ?User $user = null) { $this->post = $post; }"), groups: vr).isEmpty)
        check("var: anonymous class properties do not leak into the method scope", v("        $o = new class { public $name = 'x'; public function f($z) { return $z; } }; return $o;").isEmpty)
        check("var: nested named function is its own scope", v("        $a = 1; function inner($p) { return $p; } return $a;").isEmpty)
        check("var: variadic and by-ref parameters", codes(cls("    public function a(int ...$nums) { return $nums; }\n    public function b(array &$out) { $out[] = 1; }"), groups: vr).isEmpty)
        check("var: typed property hooks body does not trip the scan", codes(cls("    public string $name { get => $this->name; set { $this->name = $value; } }"), groups: vr).isEmpty)
        check("var: first-class callable and static closures", v("        $f = static fn() => 1; $g = strlen(...); return [$f, $g];").isEmpty)
        check("var: result is capped", { () -> Bool in
            let reads = (0..<200).map { "echo $u\($0);" }.joined(separator: " ")
            return run(method(reads), groups: vr).count <= NativePHPDiag.maxResults
        }())
        check("var: range covers the variable", { () -> Bool in
            let code = method("        return $usre;")
            guard let d = run(code, groups: vr).first else { return false }
            return (code as NSString).substring(with: d.range) == "$usre"
        }())
    }

    // MARK: Members

    private static func memberChecks() {
        let mb: Set<NPDiagGroup> = [.members]
        func m(_ body: String, uses: String = "", extends: String = "") -> [String] { messages(cls(body, uses: uses, extends: extends), groups: mb) }
        let plain = "use App\\Services\\Plain;\nuse App\\Services\\Magic;\nuse App\\Services\\Child;\nuse App\\Services\\Orphan;\nuse App\\Services\\Documented;\nuse App\\Services\\WithTrait;\n"
        func mp(_ stmts: String, params: String = "") -> [String] { m("    public function go(\(params)) {\n\(stmts)\n    }", uses: plain) }
        check("member: undefined method on $this", m("    public function a() { return $this->nope(); }") == ["Undefined method 'nope'"])
        check("member: own and declared methods are fine", m("    public function a() { return $this->b(); }\n    private function b() { return 1; }").isEmpty)
        check("member: case-insensitive method names", m("    public function a() { return $this->B(); }\n    public function b() { return 1; }").isEmpty)
        check("member: inherited from a project parent", m("    public function a() { return $this->greet('x'); }", uses: plain, extends: "Plain").isEmpty)
        check("member: undefined on a project parent chain", m("    public function a() { return $this->missing(); }", uses: plain, extends: "Child") == ["Undefined method 'missing'"])
        check("member: through an interface and the second parent level", m("    public function a() { return $this->count() + $this->extra() + $this->name(); }", uses: plain, extends: "Child").isEmpty)
        check("member: trait methods and trait aliases", m("    public function a() { return $this->slugify('x') . $this->makeSlug('y') . $this->own(); }", uses: plain, extends: "WithTrait").isEmpty)
        check("member: unknown parent (not resolvable) -> silent", m("    public function a() { return $this->whatever(); }", uses: plain, extends: "Orphan").isEmpty)
        check("member: vendor Eloquent model with magic -> silent", m("    public function a() { return $this->whereActive(); }", extends: "Post").isEmpty)
        check("member: class with __call -> silent", m("    public function a() { return $this->anything(); }\n    public function __call($m, $a) {}").isEmpty)
        check("member: parent with __call -> silent", m("    public function a() { return $this->anything(); }", uses: plain, extends: "Magic").isEmpty)
        check("member: @method / @property docblocks -> silent", m("    public function a() { return $this->shout(); }", uses: plain, extends: "Documented").isEmpty)
        check("member: file with method_exists guards -> silent", m("    public function a($o) { if (method_exists($this, 'x')) { return $this->x(); } }").isEmpty)
        check("member: undefined property read on $this", m("    private $known = 1;\n    public function a() { return $this->knwon; }") == ["Undefined property 'knwon'"])
        check("member: declared and promoted properties", m("    private $known = 1;\n    public function __construct(private int $promo = 0) {}\n    public function a() { return $this->known + $this->promo; }").isEmpty)
        check("member: dynamic property assignment elsewhere in the file", m("    public function a() { $this->dyn = 1; return $this->dyn; }").isEmpty)
        check("member: property assigned through array write", m("    public function a() { $this->bag['k'] = 1; return $this->bag; }").isEmpty)
        check("member: property hooks declared", m("    public string $name { get => 'x'; set { } }\n    public function a() { return $this->name; }").isEmpty)
        check("member: Eloquent virtual members on models are silent", m("    public function a(Post $p) { return $p->title . $p->user->name . $p->comments()->count(); }").isEmpty)
        check("member: typed parameter, undefined method", mp("        return $p->nope();", params: "Plain $p").contains("Undefined method 'nope'"))
        check("member: typed parameter, existing and inherited methods", mp("        return $p->greet('a') . $p->name() . $p->extra() . $p->count();", params: "Child $p").isEmpty)
        check("member: typed parameter with instanceof narrowing -> silent", mp("        if ($p instanceof Child) { return $p->extra(); } return $p->nope();", params: "Plain $p").isEmpty)
        check("member: reassigned parameter -> silent", mp("        $p = $other; return $p->nope();", params: "Plain $p, $other").isEmpty)
        check("member: untyped / union parameter -> silent", mp("        return $p->nope() . $q->nope();", params: "$p, Plain|Child $q").isEmpty)
        check("member: new assignment then undefined method", mp("        $x = new Plain('a'); return $x->nope();") == ["Undefined method 'nope'"])
        check("member: new assignment, existing method", mp("        $x = new Plain('a'); return $x->greet('b');").isEmpty)
        check("member: assigned twice -> silent", mp("        $x = new Plain('a'); $x = foo(); return $x->nope();").isEmpty)
        check("member: Magic receiver -> silent", mp("        $x = new Magic; return $x->whatever();").isEmpty)
        check("member: static call on a project class", mp("        return Plain::nope(3);") == ["Undefined method 'nope'"])
        check("member: static call existing", mp("        return Plain::make(3);").isEmpty)
        check("member: static call on a class with magic (Eloquent) -> silent", mp("        return Post::whereActive()->get();").isEmpty)
        check("member: static call on facade (no class) -> silent", mp("        return Cache::get('a') . DB::table('x');").isEmpty)
        check("member: self / static / parent calls", m("    public function a() { return self::nope() . static::nope2() . parent::nope3(); }\n    public static function nope() {}", uses: plain, extends: "Plain") == ["Undefined method 'nope2'", "Undefined method 'nope3'"])
        check("member: enum static methods are fine", mp("        return Status::from('draft') . Status::tryFrom('x') . Status::cases() . Status::Draft->label();").isEmpty)
        check("member: builtin class receiver -> silent", mp("        $d = new \\DateTime(); return $d->nope() . \\Closure::fromCallable('x');").isEmpty)
        check("member: chained calls are not checked past the first hop", mp("        return $this->go()->nope();").isEmpty)
        check("member: nullsafe on $this", m("    public function a() { return $this?->nope(); }") == ["Undefined method 'nope'"])
        check("member: method named like a property in the same class", m("    public function name() { return 1; }\n    public function a() { return $this->name; }").isEmpty)
        check("member: $this inside an anonymous class is not the outer class", m("    public function a() { return new class { public function f() { return $this->inner(); } public function inner() {} }; }").isEmpty)
        check("member: second class in a file -> silent", codes(head + "class A { public function a() { return $this->x(); } }\nclass B { public function b() { return $this->y(); } }\n", groups: mb).isEmpty)
        check("member: trait files -> silent", codes(head + "trait Tr { public function a() { return $this->hostMethod(); } }\n", groups: mb).isEmpty)
        check("member: $this inside a closure may be rebound (macros)", m("    public function a() { return function () { return $this->ghost(); }; }").isEmpty)
        check("member: new $this->className() is not a method call", m("    private $job;\n    public function a() { return new $this->job(1, 2); }").isEmpty)
        check("member: class declared inside a conditional block is not trusted", codes(head + "if (!class_exists(T::class, false)) {\n    class T { public function a() { return $this->b(); } private function b() { return 1; } }\n}\n", groups: mb).isEmpty)
        check("member: interface-typed parameter -> silent (implementations add methods)", codes(head + "interface Shape { public function area(); }\nclass T { public function a(Shape $s) { return $s->perimeter(); } }\n", groups: mb).isEmpty)
        check("member: @param docblock narrows the parameter type -> silent", mp("        return $p->nope();", params: "Plain $p").contains("Undefined method 'nope'") && codes(head + "class T {\n    /** @param \\App\\Services\\Child $p */\n    public function a(\\App\\Services\\Plain $p) { return $p->extra(); }\n}\n", groups: mb).isEmpty)
        check("member: heredoc constant before methods does not hide them", { () -> Bool in
            SelfTestNativePHP.put(root, "app/Services/Odd.php", "<?php\nnamespace App\\Services;\nclass Odd {\n    public const NS = <<<EOT\nxmlns:a=\"b\"\nEOT;\n    public static function create($m) { return 1; }\n    public function later() {}\n}\n")
            FastProject.shared(root: root).markDirty()
            return mp("        return Odd::create(1) . (new Odd)->later();", params: "").isEmpty
        }())
        check("member: abstract classes calling declared abstract methods", m("    abstract public function hook();\n    public function a() { return $this->hook(); }").isEmpty)
    }

    // MARK: Argument counts

    private static func argChecks() {
        let ag: Set<NPDiagGroup> = [.args]
        func a(_ stmts: String, params: String = "", extends: String = "", uses: String = "use App\\Services\\Plain;\n") -> [String] {
            messages(cls("    public function go(\(params)) {\n\(stmts)\n    }\n    private function two($a, $b, $c = 1) {}\n    private function va($a, ...$rest) {}\n    private function none() {}", uses: uses, extends: extends), groups: ag)
        }
        check("args: too few arguments to a method", a("        $this->two(1);") == ["Too few arguments to 'two': expected 2, found 1"])
        check("args: exact, optional and extra arguments are fine", a("        $this->two(1, 2); $this->two(1, 2, 3); $this->none(); $this->two(1, 2, 3, 4);").isEmpty)
        check("args: zero arguments to a method that needs some", a("        $this->two();") == ["Too few arguments to 'two': expected 2, found 0"])
        check("args: variadics", a("        $this->va(1); $this->va(1, 2, 3, 4);").isEmpty && a("        $this->va();") == ["Too few arguments to 'va': expected 1, found 0"])
        check("args: named arguments are skipped", a("        $this->two(a: 1);").isEmpty)
        check("args: spread arguments are skipped", a("        $this->two(...$args);").isEmpty)
        check("args: first-class callable syntax is skipped", a("        $f = $this->two(...);").isEmpty)
        check("args: trailing comma", a("        $this->two(1, 2,);").isEmpty)
        check("args: nested calls and arrays count as one argument each", a("        $this->two([1, 2, 3], foo(1, 2));").isEmpty && a("        $this->two(foo(1, 2));") == ["Too few arguments to 'two': expected 2, found 1"])
        check("args: constructor of a project class", a("        $p = new Plain();") == ["Too few arguments to constructor of 'Plain': expected 1, found 0"])
        check("args: constructor with enough arguments / defaults", a("        $p = new Plain('a'); $q = new Plain('a', 5);").isEmpty)
        check("args: inherited constructor through the hierarchy", a("        $p = new Child();", uses: "use App\\Services\\Child;\n") == ["Too few arguments to constructor of 'Child': expected 1, found 0"])
        check("args: static method of a project class", a("        Plain::make();") == ["Too few arguments to 'make': expected 1, found 0"])
        check("args: parent::method()", a("        parent::greet();", extends: "Plain") == ["Too few arguments to 'greet': expected 1, found 0"])
        check("args: typed parameter receiver", a("        $p->greet();", params: "Plain $p") == ["Too few arguments to 'greet': expected 1, found 0"])
        check("args: helper function from composer autoload files", a("        return format_money();") == ["Too few arguments to function 'format_money': expected 1, found 0"])
        check("args: helper function with enough arguments", a("        return format_money(100) . route('x') . view('a') . view();").isEmpty)
        check("args: function declared in the same file", codes("<?php\nfunction add($a, $b) { return $a + $b; }\nadd(1);\nadd(1, 2);\n", groups: ag) == ["arg-count"])
        check("args: function declared twice -> silent", codes("<?php\nif (true) { function add($a, $b) {} } else { function add($a) {} }\nadd();\n", groups: ag).isEmpty)
        check("args: unknown functions and builtins are silent", a("        strlen(); array_map(); foo(); Foo::bar();").isEmpty)
        check("args: methods of unknown classes are silent", a("        $x = new \\DateTime(); $x->format();").isEmpty)
        check("args: not reported when the rule group is off", messages(cls("    public function go() { $this->two(1); }\n    private function two($a, $b) {}"), groups: [.members]).isEmpty)
        check("args: severity is error", run(cls("    public function go() { $this->two(1); }\n    private function two($a, $b) {}"), groups: ag).first?.severity == 1)
        check("args: arity parser", { () -> Bool in
            let t: [(String, Int, Int?)] = [("", 0, 0), ("$a", 1, 1), ("$a, $b = 1", 1, 2), ("Foo $a, int|string $b = [1, 2], ...$c", 1, nil), ("array $o = ['a' => 1, 'b' => 2]", 0, 1),
                                            ("#[Attr(1, 2)] $a, $b", 2, 2), ("$a = null, $b", 2, 2), ("?Foo $f = null", 0, 1)]
            return t.allSatisfy { (p, mn, mx) in
                guard let r = NPDiagContext.arity(p) else { return false }
                return r.min == mn && r.max == mx
            }
        }())
    }

    // MARK: Valid Laravel code stays silent

    private static func validLaravel() {
        let controller = """
        <?php

        declare(strict_types=1);

        namespace App\\Http\\Controllers;

        use App\\Enums\\Status;
        use App\\Models\\Comment;
        use App\\Models\\Post;
        use App\\Models\\User;
        use Illuminate\\Http\\Request;
        use Illuminate\\Support\\Collection;
        use Illuminate\\Support\\Facades\\Cache;
        use Illuminate\\Support\\Facades\\DB;
        use Illuminate\\Support\\Facades\\Route;

        /**
         * Handles posts.
         *
         * @property-read int $counter
         */
        #[\\AllowDynamicProperties]
        final class PostController
        {
            public const PER_PAGE = 15;

            private array $cache = [];

            public function __construct(private readonly Request $request, protected ?User $user = null) {}

            #[\\ReturnTypeWillChange]
            public function index(Request $request): string
            {
                $posts = Post::query()->where('status', Status::Published)->latest()->paginate(self::PER_PAGE);
                $titles = $posts->map(fn (Post $p) => $p->title)->all();
                $total = Cache::get('total', 0) + count($titles);
                $user = $request->user();
                $byUser = Post::where('user_id', $user->id)->get()->groupBy('status');

                Collection::macro('toUpper', fn () => $this->map(fn ($v) => strtoupper($v)));
                $upper = collect($titles)->toUpper();

                DB::table('posts')->where('id', 1)->update(['title' => 'x']);

                foreach ($posts as $post) {
                    $post->comments()->create(['body' => 'hi']);
                    echo $post->title, $post->user->name, $post->comment_count;
                }

                $status = Status::from('draft');
                $label = Status::Draft->label() . Status::tryFrom('x')?->label() . count(Status::cases());

                $state = match (true) {
                    $total > 10 => 'many',
                    default => 'few',
                };

                $sorted = static fn (int $a, int $b): int => $a <=> $b;
                $len = strlen(...);
                $method = $this->helper(...);

                try {
                    $result = DB::transaction(function () use ($user, $posts) {
                        $posts->each(fn ($p) => $p->update(['user_id' => $user->id]));
                        return $posts->count();
                    });
                } catch (\\Throwable $e) {
                    report($e);
                    return view('posts.index', compact('posts', 'total', 'state'));
                } finally {
                    $this->cache = [];
                }

                $html = <<<HTML
                    <p>{$user->name} wrote $result posts $undefinedInHeredoc</p>
                    HTML;

                [$first, $second] = [1, 2];
                ['a' => $alpha] = ['a' => 1];
                $this->counter = 1;
                $format = format_money(100);
                $url = route('posts.index', ['page' => 1]);

                return view('posts.index', ['posts' => $posts]) . $html . $url . $format . $first . $second . $alpha . $label . $upper . $byUser . $len . $method . $status . $sorted;
            }

            private function helper(string $a = 'x'): string
            {
                return $a . $this->request->input('q') . $this->user?->name;
            }

            public function show(Post $post, Comment ...$comments): string
            {
                if ($post instanceof Post && !empty($comments)) {
                    return $post->publish() ?: $post->title;
                }
                static $calls = 0;
                $calls++;
                return (string) $calls;
            }

            public function __call($name, $arguments)
            {
                return $this->$name(...$arguments);
            }
        }
        """
        let res = run(controller, groups: Set(NPDiagGroup.allCases))
        check("valid: realistic Laravel controller is completely silent", res.isEmpty)
        if !res.isEmpty { for r in res { fputs("  unexpected: \(r.code) \(r.message) @\(r.range.location)\n", stderr) } }

        let model = """
        <?php

        namespace App\\Models;

        use Illuminate\\Database\\Eloquent\\Model;
        use Illuminate\\Database\\Eloquent\\Relations\\HasMany;

        class Article extends Model
        {
            use HasSlug;

            protected $fillable = ['title'];
            protected $casts = ['published_at' => 'datetime'];

            public function comments(): HasMany
            {
                return $this->hasMany(Comment::class);
            }

            public function scopeDraft($query)
            {
                return $query->where('status', 'draft');
            }

            public function getTitleUpperAttribute(): string
            {
                return strtoupper($this->title);
            }

            public static function booted(): void
            {
                static::creating(function (self $a) {
                    $a->slug = $a->slugify($a->title);
                });
            }
        }
        """
        let mres = run(model, path: "app/Models/Article.php")
        check("valid: Eloquent model with scopes, accessors, relations, traits is silent", mres.isEmpty)
        if !mres.isEmpty { for r in mres { fputs("  unexpected: \(r.code) \(r.message) @\(r.range.location)\n", stderr) } }

        let routes = "<?php\n\nuse Illuminate\\Support\\Facades\\Route;\nuse App\\Http\\Controllers\\PostController;\n\nRoute::get('/', [PostController::class, 'index'])->name('home');\nRoute::middleware('auth')->group(function () {\n    Route::resource('posts', PostController::class);\n});\nRoute::get('/x', function () { return view('welcome'); });\n"
        check("valid: routes file is silent", run(routes, path: "routes/web.php").isEmpty)

        let migration = "<?php\n\nuse Illuminate\\Database\\Migrations\\Migration;\nuse Illuminate\\Database\\Schema\\Blueprint;\nuse Illuminate\\Support\\Facades\\Schema;\n\nreturn new class extends Migration {\n    public function up(): void {\n        Schema::create('posts', function (Blueprint $table) {\n            $table->id();\n            $table->timestamps();\n        });\n    }\n};\n"
        check("valid: anonymous-class migration (Migration class absent from fixture vendor is tolerated only by import)", run(migration, path: "database/migrations/x.php").filter { $0.code != "undefined-class" }.isEmpty)

        let hooks = "<?php\nnamespace App\\Models;\nclass Temp {\n    public function __construct(public string $raw = '') {}\n    public string $upper { get => strtoupper($this->raw); set(string $v) { $this->raw = $v; } }\n    public private(set) int $count = 0;\n    public function bump(): int { return ++$this->count; }\n}\n"
        let hres = run(hooks, path: "app/Models/Temp.php")
        check("valid: PHP 8.4 property hooks and asymmetric visibility", hres.isEmpty)
        if !hres.isEmpty { for r in hres { fputs("  unexpected: \(r.code) \(r.message)\n", stderr) } }

        let readonlyEnum = "<?php\nnamespace App\\Dto;\nuse App\\Enums\\Status;\nreadonly class Dto {\n    public function __construct(public Status $status = Status::Draft, public array $tags = []) {}\n    public function with(Status $s): static { return new static($s, $this->tags); }\n}\nenum Level: int {\n    case Low = 1;\n    public static function default(): self { return self::Low; }\n    public function next(): self { return match($this) { self::Low => self::Low }; }\n}\n"
        let rres = run(readonlyEnum, path: "app/Dto/Dto.php")
        check("valid: readonly class, enum with methods, static return", rres.isEmpty)
        if !rres.isEmpty { for r in rres { fputs("  unexpected: \(r.code) \(r.message)\n", stderr) } }

        let blade = "@php $x = $y; new Nope(); @endphp\n<p>{{ $undefined->foo() }}</p>\n"
        check("valid: Blade templates are never analysed", run(blade, path: "resources/views/p.blade.php").isEmpty)
        check("valid: Blade with embedded PHP tag", run("<?php $a = new Nope(); echo $b; ?>\n", path: "resources/views/q.blade.php").isEmpty)

        let pest = "<?php\n\nuse App\\Models\\User;\n\nit('works', function () {\n    $user = User::factory()->create();\n    expect($user)->toBeInstanceOf(User::class);\n    $this->actingAs($user)->get('/')->assertOk();\n});\n"
        check("valid: Pest test file (closures with $this)", run(pest, path: "tests/Feature/A.php").isEmpty)

        let config = "<?php\n\nreturn [\n    'name' => env('APP_NAME', 'Laravel'),\n    'providers' => [App\\Providers\\AppServiceProvider::class],\n    'aliases' => Illuminate\\Support\\Facades\\Facade::defaultAliases()->merge(['Foo' => App\\Foo::class])->toArray(),\n];\n"
        check("valid: config file", run(config, path: "config/app.php").filter { $0.code != "undefined-class" }.isEmpty)

        let trait = "<?php\nnamespace App\\Models;\ntrait Sluggable {\n    public function makeSlug(): string { return $this->slugSource() . $this->other; }\n    abstract protected function slugSource(): string;\n}\n"
        check("valid: trait calling host members", run(trait, path: "app/Models/Sluggable.php").isEmpty)

        let command = "<?php\nnamespace App\\Console\\Commands;\nuse Illuminate\\Console\\Command;\nclass Run extends Command {\n    protected $signature = 'run';\n    public function handle(): int {\n        $this->info('x');\n        $this->line($this->argument('a'));\n        return self::SUCCESS;\n    }\n}\n"
        check("valid: console command with inherited helpers (parent absent from fixture is tolerated)", run(command, path: "app/Console/Commands/Run.php").filter { !["undefined-class", "undefined-method", "undefined-property"].contains($0.code) }.isEmpty)
    }

    // MARK: Settings, merge, controller

    private static func settingsAndMerge() {
        let before = NPDiagGroup.allCases.map { $0.enabled }
        check("settings: all groups default to on", before.allSatisfy { $0 })
        NPDiagGroup.classes.enabled = false
        check("settings: a group can be switched off", !NativePHPDiag.enabledGroups.contains(.classes) && NativePHPDiag.enabledGroups.contains(.syntax))
        NPDiagGroup.classes.enabled = true
        check("settings: group keys are stable", NPDiagGroup.imports.key == "php.diag.imports" && NPDiagGroup.syntax.key == "php.diag.syntax")
        let sev = NativePHPDiag.classSeverity
        NativePHPDiag.classSeverity = 1
        check("settings: class severity pref", NativePHPDiag.classSeverity == 1)
        NativePHPDiag.classSeverity = 7
        check("settings: class severity is clamped to warning or error", NativePHPDiag.classSeverity == 2)
        NativePHPDiag.classSeverity = sev
        check("settings: handles php/phtml and not Blade", NativePHPDiag.handles(URL(fileURLWithPath: "/a/b.php")) && NativePHPDiag.handles(URL(fileURLWithPath: "/a/b.phtml"))
              && !NativePHPDiag.handles(URL(fileURLWithPath: "/a/b.blade.php")) && !NativePHPDiag.handles(URL(fileURLWithPath: "/a/b.js")))

        // dedupe against Intelephense
        func d(_ sev: Int, _ line: Int, _ col: Int, _ endCol: Int, _ code: String?, _ msg: String = "m") -> FileProblems.Diagnostic {
            FileProblems.Diagnostic(severity: sev, message: msg, line: line, column: col, endLine: line, endColumn: endCol, source: "x", code: code)
        }
        let lsp = [d(1, 5, 10, 15, nil, "Undefined type 'Foo'"), d(1, 9, 1, 3, nil, "';' expected")]
        check("merge: same range is dropped", NativePHPDiag.dedupe([d(2, 5, 10, 13, "undefined-class")], against: lsp).isEmpty)
        check("merge: overlapping range is dropped", NativePHPDiag.dedupe([d(2, 5, 12, 20, "undefined-class")], against: lsp).isEmpty)
        check("merge: other line is kept", NativePHPDiag.dedupe([d(2, 6, 10, 13, "undefined-class")], against: lsp).count == 1)
        check("merge: same line, disjoint ranges is kept", NativePHPDiag.dedupe([d(2, 5, 20, 25, "undefined-variable")], against: lsp).count == 1)
        check("merge: syntax errors on the same line as an Intelephense error are deduplicated", NativePHPDiag.dedupe([d(1, 9, 7, 8, "syntax")], against: lsp).isEmpty)
        check("merge: unused import hint dropped when the server warns on that line", NativePHPDiag.dedupe([d(4, 3, 5, 20, "unused-import")], against: [d(2, 3, 1, 30, nil, "unused")]).isEmpty)
        check("merge: nothing to dedupe against keeps everything", NativePHPDiag.dedupe([d(2, 1, 1, 2, "x")], against: []).count == 1)
        let url = root.appendingPathComponent("app/Merge.php")
        NativeProblems.set(url: url, [d(2, 5, 12, 20, "undefined-class"), d(2, 20, 1, 4, "undefined-variable", "Undefined variable '$x'")])
        let merged = NativePHPDiag.merged(lsp, path: url.standardizedFileURL.path)
        check("merge: merged list holds the server diagnostics plus the non-duplicate native ones, sorted",
              merged.count == 3 && merged.map { $0.line } == [5, 9, 20] && merged.last?.code == "undefined-variable")
        check("merge: files without native findings are untouched", NativePHPDiag.merged(lsp, path: "/nope/x.php").count == lsp.count)
        NativeProblems.set(url: url, [])

        // Problems panel integration (native-only file)
        let panelURL = root.appendingPathComponent("app/Panel.php")
        let list = [NPDiag(range: NSRange(location: 0, length: 3), severity: 1, message: "Syntax error", code: "syntax", group: .syntax)]
        NativeProblems.set(url: panelURL, NativePHPDiag.diagnostics(list, in: "abc\n" as NSString))
        let probs = LanguageServers.problems(forRoot: root)
        check("panel: native PHP findings reach the Problems list", probs.contains { $0.url.lastPathComponent == "Panel.php" && $0.errorCount == 1 })
        NativeProblems.set(url: panelURL, [])

        // line/column conversion
        let table = NPLineStarts("ab\ncd\n\nef" as NSString)
        let p1 = table.position(of: 0), p2 = table.position(of: 4), p3 = table.position(of: 7), p4 = table.position(of: 100)
        check("lines: offsets map to 1-based line and column", p1.line == 1 && p1.col == 1 && p2.line == 2 && p2.col == 2 && p3.line == 4 && p3.col == 1 && p4.line == 4)

        // controller on a real tab (headless)
        if let w = (NSApp.delegate as? AppDelegate)?.active {
            let file = root.appendingPathComponent("app/Http/Controllers/Live.php")
            let code = head + "class Live {\n    public function a() {\n        return $oops;\n    }\n}\n"
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? code.write(to: file, atomically: true, encoding: .utf8)
            w.open(file)
            if let tab = w.current, tab.url.standardizedFileURL == file.standardizedFileURL {
                let c = NativePHPDiagController.controller(for: tab)
                check("controller: attached to PHP tabs", c != nil)
                if let c {
                    let list = run(code)
                    c.apply(list, text: tab.textView.string)
                    check("controller: findings stored and drawn", !c.all.isEmpty && c.squiggleCount == c.visible.count && c.squiggleCount > 0)
                    check("controller: Problems list shows them", NativeProblems.diagnostics(forPath: file.standardizedFileURL.path).contains { $0.code == "undefined-variable" })
                    check("controller: hover provider returns them", !NativePHPDiagController.hoverDiagnostics(for: tab).isEmpty)
                    let was = c.passes
                    c.apply(list, text: tab.textView.string + "x")             // stale result (buffer length differs) is dropped
                    check("controller: stale results are dropped", c.passes == was)
                    let hint = c.visible.first?.range.location ?? 0
                    tab.textView.insertText("// edit\n", replacementRange: NSRange(location: 0, length: 0))
                    check("controller: squiggles shift with edits", (c.visible.first?.range.location ?? 0) >= hint)
                    w.close(file.standardizedFileURL.path)
                    check("controller: detached on close (problems cleared)", NativeProblems.diagnostics(forPath: file.standardizedFileURL.path).isEmpty)
                }
            } else {
                check("controller: tab opened", false)
            }
        }
    }

    // MARK: Bounds

    private static func bounds() {
        let big = "<?php\nnamespace App;\nclass Big {\n" + (0..<3000).map { "    public function f\($0)(int $a): int { return $a + \($0); }\n" }.joined() + "}\n"
        var t0 = Date()
        let r = run(big, path: "app/Big.php")
        let ms = Date().timeIntervalSince(t0) * 1000
        check("bounds: 3000-method file is silent and fast (\(Int(ms)) ms)", r.isEmpty && ms < 2500)
        let huge = "<?php\nnamespace App;\n" + String(repeating: "// padding line padding line padding line padding\n", count: 14_000) + "class H { function a() { return $nope; } }\n"
        check("bounds: files over the size cap only get the syntax pass", (huge as NSString).length > NativePHPDiag.maxBytes && run(huge, path: "app/Huge.php").isEmpty)
        let many = "<?php\nnamespace App;\nclass M {\n    public function a() {\n" + (0..<400).map { "        $v\($0)->x();\n" }.joined() + "    }\n}\n"
        t0 = Date()
        let mr = run(many, path: "app/Many.php")
        check("bounds: result count is capped", mr.count <= NativePHPDiag.maxResults)
        check("bounds: analysis time is bounded (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)", Date().timeIntervalSince(t0) < 3)
        let broken = "<?php\n" + String(repeating: "function f( {\n", count: 500)
        check("bounds: pathological syntax errors stay capped", run(broken, path: "app/Broken.php").count <= NPDiagSyntax.maxErrors)
    }
}
