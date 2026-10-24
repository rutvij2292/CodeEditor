import AppKit

/// Headless checks for the bundled PHP built-in stubs (PHPStubs + their integration in the native service): lazy loading, bounded
/// cache, definition / hover / signature help / inherited members on built-in classes and functions, and no false positives in the
/// diagnostics. Snippets mark the pointer with `§`.
enum SelfTestNativePHPStubs {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("stubs: " + name, ok()) }

    private static let ctl = "app/Http/Controllers/PostController.php"

    private static func put(_ root: URL, _ rel: String, _ text: String) { SelfTestNativePHP.put(root, rel, text) }

    private static func src(_ code: String, params: String = "Post $post") -> String {
        "<?php\nnamespace App\\Http\\Controllers;\n\nuse App\\Models\\Post;\nuse App\\Support\\Carbonish;\nuse App\\Support\\MyEx;\nuse App\\Support\\Bag;\n\nclass PostController {\n    public function show(\(params)) {\n        \(code)\n    }\n}\n"
    }

    private static func prep(_ root: URL, _ s: String) -> (URL, NSString, Int)? {
        let off = (s as NSString).range(of: "§").location
        guard off != NSNotFound else { return nil }
        let clean = s.replacingOccurrences(of: "§", with: "")
        put(root, ctl, clean)
        return (root.appendingPathComponent(ctl), clean as NSString, off)
    }

    private static func hit(_ root: URL, _ code: String, params: String = "Post $post") -> NPHit? {
        guard let (u, t, off) = prep(root, src(code, params: params)) else { return nil }
        return NativePHP.lookup(url: u, text: t, offset: off, root: root.path)
    }

    private static func sig(_ root: URL, _ code: String, params: String = "Post $post") -> NPSigHelp? {
        guard let (u, t, off) = prep(root, src(code, params: params)) else { return nil }
        if case .help(let h) = NativePHP.signatureHelp(url: u, text: t, caret: off, root: root.path) { return h }
        return nil
    }

    private static func active(_ h: NPSigHelp?) -> String? {
        guard let h, h.active >= 0, h.active < h.ranges.count else { return nil }
        return (h.label as NSString).substring(with: h.ranges[h.active])
    }

    /// The stub source line the first target lands on.
    private static func landing(_ h: NPHit?) -> String {
        guard let t = h?.targets.first, let text = try? String(contentsOfFile: t.path, encoding: .utf8) else { return "" }
        let ns = text as NSString
        return ns.substring(with: ns.lineRange(for: NSRange(location: min(t.offset, max(0, ns.length - 1)), length: 0))).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inStub(_ h: NPHit?) -> Bool { h?.targets.first.map { PHPStubs.isStubFile($0.path) } ?? false }

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-nativestubs-\(getpid())")
        try? fm.removeItem(at: root)
        SelfTestNativePHP.buildFixture(root)
        defer { try? fm.removeItem(at: root) }
        NPFiles.clear()

        guard PHPStubs.root != nil else { check("bundled PhpStubs directory found", false); return }

        // MARK: lazy loading
        PHPStubs.reset()
        check("lazy: nothing mapped before the first lookup", !PHPStubs.isLoaded && PHPStubs.lookupCount == 0 && PHPStubs.cachedClassCount == 0)
        check("index: DateTime", PHPStubs.classEntry("datetime")?.kind == "c" && PHPStubs.classEntry("\\DateTime")?.name == "DateTime")
        check("lazy: first lookup maps the index, parses no class", PHPStubs.isLoaded && PHPStubs.classParseCount == 0)
        check("index: case-insensitive classes, case-sensitive constants", PHPStubs.hasClass("pdoexception") && PHPStubs.constantEntry("json_pretty_print") == nil && PHPStubs.constantEntry("JSON_PRETTY_PRINT") != nil)
        check("index: functions and interfaces", PHPStubs.functionEntry("JSON_ENCODE")?.signature.hasPrefix("json_encode(mixed $value") == true && PHPStubs.classEntry("ArrayAccess")?.extra == "interface")
        check("index: unknown names", PHPStubs.classEntry("NoSuchBuiltin") == nil && PHPStubs.functionEntry("nope_nope") == nil)
        check("index: prefix search", PHPStubs.search(kind: "f", prefix: "mb_str", limit: 50).count >= 5 && PHPStubs.search(kind: "c", prefix: "Reflection", limit: 50).count >= 10)
        check("index: Laravel-relevant extensions present", ["ZipArchive", "SplFileObject", "ArrayObject", "ArrayIterator", "Closure", "Generator", "DOMDocument", "SimpleXMLElement", "mysqli",
                                                            "PDO", "PDOStatement", "DateTimeImmutable", "Throwable", "JsonException", "CURLFile", "Random\\Randomizer", "NumberFormatter"].allSatisfy { PHPStubs.hasClass($0) })

        // MARK: fixture classes
        put(root, "app/Support/Carbonish.php", "<?php\nnamespace App\\Support;\nclass Carbonish extends \\DateTimeImmutable implements \\JsonSerializable {\n    public function jsonSerialize(): mixed { return []; }\n}\n")
        put(root, "app/Support/MyEx.php", "<?php\nnamespace App\\Support;\nclass MyEx extends \\RuntimeException {}\n")
        put(root, "app/Support/Bag.php", "<?php\nnamespace App\\Support;\nclass Bag implements \\ArrayAccess, \\IteratorAggregate, \\Countable {\n    public function offsetExists(mixed $o): bool { return true; }\n    public function offsetGet(mixed $o): mixed { return 1; }\n    public function offsetSet(mixed $o, mixed $v): void {}\n    public function offsetUnset(mixed $o): void {}\n    public function getIterator(): \\Traversable { return new \\ArrayIterator([]); }\n    public function count(): int { return 0; }\n}\n")

        // MARK: definition and hover on classes
        var h = hit(root, "$p = new \\PD§O('sqlite::memory:');")
        check("new \\PDO lands in the stub class", inStub(h) && landing(h).hasPrefix("class PDO"))
        check("hover: class doc and stub origin", h?.markdown.contains("class PDO") == true && h?.markdown.contains("PHP built-in stub") == true && h?.markdown.contains("connection between PHP") == true)
        check("lazy: one class parsed for that lookup (no mass parsing)", PHPStubs.classParseCount >= 1 && PHPStubs.classParseCount <= 4)
        h = hit(root, "try { } catch (\\PDOExc§eption $e) {}")
        check("catch (\\PDOException $e)", inStub(h) && landing(h).hasPrefix("class PDOException"))
        h = hit(root, "try { } catch (\\Thro§wable $e) {}")
        check("catch \\Throwable", inStub(h) && landing(h).hasPrefix("interface Throwable"))
        h = hit(root, "$z = new \\ZipArch§ive();")
        check("ZipArchive", inStub(h) && landing(h).hasPrefix("class ZipArchive"))
        h = hit(root, "$z = new \\SplFileObje§ct('x');")
        check("SplFileObject", inStub(h))
        h = hit(root, "$z = new \\Array§Object([]);")
        check("ArrayObject", inStub(h))
        h = hit(root, "$z = new \\DOMDoc§ument();")
        check("DOMDocument", inStub(h))
        h = hit(root, "$z = new \\Random\\Randomi§zer();")
        check("namespaced built-in Random\\Randomizer", inStub(h) && landing(h).hasSuffix("class Randomizer"))

        // MARK: functions and constants
        h = hit(root, "$j = json_enc§ode($post);")
        check("function: definition in stub", inStub(h) && landing(h).hasPrefix("function json_encode("))
        check("function: hover signature, return type, doc", h?.markdown.contains("function json_encode(mixed $value, int $flags = 0, int $depth = 512): string|false") == true
              && h?.markdown.contains("JSON representation") == true && h?.markdown.contains("PHP built-in stub") == true)
        h = hit(root, "$j = mb_sub§str('a', 1);")
        check("mb_substr", inStub(h) && h?.markdown.contains("?int $length = null") == true)
        h = hit(root, "$j = preg_ma§tch('/a/', 'a');")
        check("preg_match", inStub(h))
        h = hit(root, "$j = array_ma§p(fn ($x) => $x, []);")
        check("array_map", inStub(h) && h?.markdown.contains("array_map(") == true)
        h = hit(root, "$j = json_encode($post, JSON_PRETTY_PR§INT);")
        check("constant: definition and value", inStub(h) && landing(h).hasPrefix("const JSON_PRETTY_PRINT = 128") && h?.markdown.contains("PHP built-in stub") == true)
        h = hit(root, "$j = curl_in§it();")
        check("curl_init", inStub(h))

        // MARK: members via type inference
        h = hit(root, "$pdo = new \\PDO('x');\n        $pdo->que§ry('select 1');")
        check("$pdo->query()", inStub(h) && landing(h).hasPrefix("public function query("))
        check("hover: return type and docblock", h?.markdown.contains("PDOStatement|false") == true && h?.markdown.contains("PDO") == true)
        h = hit(root, "$d = new \\DateTime();\n        $d->for§mat('Y');")
        check("$date->format()", inStub(h) && landing(h).hasPrefix("public function format("))
        h = hit(root, "$d = new Carbonish();\n        $d->for§mat('Y');")
        check("Carbon-like class extends DateTimeImmutable: inherited format()", inStub(h) && landing(h).hasPrefix("public function format("))
        h = hit(root, "$d = new Carbonish();\n        $d->modi§fy('+1 day');")
        check("inherited modify() through two levels", inStub(h) && landing(h).hasPrefix("public function modify("))
        h = hit(root, "$e = new MyEx('x');\n        $e->getMess§age();")
        check("Exception subclass: getMessage() from Exception stub", inStub(h) && landing(h).contains("function getMessage("))
        h = hit(root, "try { } catch (\\PDOException $e) {\n            $e->getMess§age();\n        }")
        check("catch variable typed by built-in exception", inStub(h) && landing(h).contains("function getMessage("))
        h = hit(root, "$e = new \\InvalidArgumentException('x');\n        $e->getPre§vious();")
        check("InvalidArgumentException -> LogicException -> Exception chain", inStub(h) && landing(h).contains("getPrevious"))
        h = hit(root, "$e = new \\Exception('x');\n        $e->getTrace§AsString();")
        check("Exception::getTraceAsString", inStub(h))
        h = hit(root, "$a = new \\ArrayObject([]);\n        $a->getIter§ator();")
        check("ArrayObject member", inStub(h))
        h = hit(root, "$z = new \\ZipArchive();\n        $z->addFi§le('a');")
        check("ZipArchive member", inStub(h) && landing(h).hasPrefix("public function addFile("))
        h = hit(root, "$f = new \\SplFileObject('x');\n        $f->fge§ts();")
        check("SplFileObject member", inStub(h))
        h = hit(root, "$c = \\Closure::fromCall§able('strlen');")
        check("Closure static method", inStub(h) && landing(h).hasPrefix("public static function fromCallable("))
        h = hit(root, "$g = (function (): \\Generator { yield 1; })();\n        $g->curr§ent();")
        check("Generator member via closure call (best effort)", h == nil || inStub(h))
        h = hit(root, "$g->curr§ent();", params: "\\Generator $g")
        check("Generator typed parameter: current()", inStub(h) && landing(h).hasPrefix("public function current("))
        h = hit(root, "$c->cou§nt();", params: "\\Countable $c")
        check("interface typed parameter: Countable::count", inStub(h) && landing(h).hasPrefix("public function count("))
        h = hit(root, "$i->rew§ind();", params: "\\Iterator $i")
        check("Iterator::rewind", inStub(h))
        h = hit(root, "$i->get§Iterator();", params: "\\IteratorAggregate $i")
        check("IteratorAggregate::getIterator", inStub(h))
        h = hit(root, "$b = new Bag();\n        $b->coun§t();")
        check("user class implementing ArrayAccess/Countable keeps its own members", !inStub(h) && h?.targets.first?.path.hasSuffix("Bag.php") == true)
        h = hit(root, "class A implements \\ArrayAcc§ess {}\n        ")
        check("implements \\ArrayAccess", inStub(h) && landing(h).hasPrefix("interface ArrayAccess"))
        h = hit(root, "$m = new \\mysq§li('h');")
        check("mysqli", inStub(h))
        h = hit(root, "$m = new \\mysqli('h');\n        $m->que§ry('x');")
        check("mysqli::query", inStub(h))
        h = hit(root, "$m = new \\SimpleXMLElement('<a/>');\n        $m->addChi§ld('b');")
        check("SimpleXMLElement::addChild", inStub(h))

        // MARK: signature help
        var s = sig(root, "json_encode($post, §);")
        check("sig: json_encode second parameter", s?.label == "json_encode(mixed $value, int $flags = 0, int $depth = 512): string|false" && active(s) == "int $flags = 0")
        s = sig(root, "$d = new \\DateTime(§);")
        check("sig: new DateTime", s?.label.hasPrefix("DateTime(string $datetime") == true)
        s = sig(root, "$pdo = new \\PDO('x');\n        $pdo->query('a', §);")
        check("sig: $pdo->query second parameter", s?.label.hasPrefix("query(string $query") == true && active(s)?.contains("fetchMode") == true)
        s = sig(root, "$x = mb_substr('a', 1, §);")
        check("sig: mb_substr third parameter", active(s) == "?int $length = null")
        s = sig(root, "$x = array_map(§);")
        check("sig: array_map", s?.label.hasPrefix("array_map(") == true)
        s = sig(root, "$x = \\Closure::fromCallable(§);")
        check("sig: Closure::fromCallable", s?.label.hasPrefix("fromCallable(") == true)
        s = sig(root, "$d = new Carbonish();\n        $d->setTime(1, §);")
        check("sig: inherited DateTimeImmutable::setTime", s?.label.hasPrefix("setTime(int $hour") == true && active(s)?.contains("minute") == true)
        s = sig(root, "$x = str_replace('a', 'b', §);")
        check("sig: str_replace (curated table still wins or stub)", s?.label.hasPrefix("str_replace(") == true)
        s = sig(root, "$x = curl_setopt($ch, §);")
        check("sig: curl_setopt", s?.label.hasPrefix("curl_setopt(") == true)

        // MARK: bounded cache
        let fp = FastProject.shared(root: root)
        let names = ["PDO", "PDOStatement", "DateTime", "DateTimeImmutable", "DateInterval", "DatePeriod", "DateTimeZone", "ZipArchive", "SplFileObject", "SplFileInfo",
                     "ArrayObject", "ArrayIterator", "Closure", "Generator", "DOMDocument", "DOMElement", "DOMNode", "SimpleXMLElement", "mysqli", "mysqli_result",
                     "ReflectionClass", "ReflectionMethod", "ReflectionProperty", "ReflectionFunction", "Exception", "ErrorException", "SplStack", "SplQueue",
                     "SplObjectStorage", "WeakMap", "NumberFormatter", "IntlDateFormatter", "XMLWriter", "XMLReader", "CURLFile", "Collator", "SessionHandler", "SplHeap"]
        var parsed = 0
        fp.queue.sync { for n in names where fp.classInfo(n) != nil { parsed += 1 } }
        check("cache: \(names.count) built-in classes resolved", parsed >= 35)
        check("cache: parsed stub classes stay within the cap (\(PHPStubs.cachedClassCount) <= \(PHPStubs.maxCachedClasses))", PHPStubs.cachedClassCount <= PHPStubs.maxCachedClasses && PHPStubs.cachedClassCount > 0)
        PHPStubs.reset()
        check("reset releases the index and cache", !PHPStubs.isLoaded && PHPStubs.cachedClassCount == 0)

        // MARK: heavy use: every stub class parsed once, every function signature read (footprint stays small)
        let before = NativePHPBench.footprintMB()
        let t0 = Date()
        var classesParsed = 0, sigs = 0
        fp.queue.sync {
            for e in PHPStubs.search(kind: "c", prefix: "", limit: 2000) where fp.classInfo(e.name) != nil { classesParsed += 1 }
            for e in PHPStubs.search(kind: "f", prefix: "", limit: 5000) {
                if let t = NPFiles.text(e.path), NPFuncIndex.signature(t, nameLoc: e.loc) != nil { sigs += 1 }
            }
        }
        let grew = NativePHPBench.footprintMB() - before
        fputs("STUBS stress: \(classesParsed) classes + \(sigs) function signatures in \(Int(Date().timeIntervalSince(t0) * 1000)) ms, footprint +\(String(format: "%.1f", grew)) MB, cached classes \(PHPStubs.cachedClassCount), NPFiles \(NPFiles.cachedCount)\n", stderr)
        check("stress: all stub classes parse, all function signatures read (\(classesParsed) / \(sigs))", classesParsed >= 330 && sigs >= 2000)
        check("stress: footprint growth stays small (\(String(format: "%.1f", grew)) MB) and caches bounded", grew < 40 && PHPStubs.cachedClassCount <= PHPStubs.maxCachedClasses && NPFiles.cachedCount <= 6)

        // MARK: diagnostics: no built-in is reported undefined
        let diagSrc = """
        <?php

        namespace App\\Http\\Controllers;

        use PDO;
        use PDOException;
        use DateTimeImmutable;
        use ZipArchive;
        use SplFileObject;
        use ArrayObject;
        use Generator;
        use Closure;
        use JsonException;
        use Throwable;
        use Stringable;
        use DOMDocument;
        use SimpleXMLElement;
        use mysqli;
        use Random\\Randomizer;

        final class T implements \\Countable, \\JsonSerializable, Stringable
        {
            public function __construct(private PDO $pdo, private ?DateTimeImmutable $at = null, private ?Closure $cb = null) {}
            public function count(): int { return 0; }
            public function jsonSerialize(): mixed { return []; }
            public function __toString(): string { return ''; }
            public function gen(): Generator { yield 1; }
            public function go(ZipArchive $z, SplFileObject $f, ArrayObject $a, DOMDocument $d, SimpleXMLElement $x, mysqli $m, \\Iterator $i, \\ReflectionClass $r)
            {
                try {
                    $s = new \\SplStack();
                    $o = new \\stdClass();
                    $w = new \\WeakMap();
                    $q = new Randomizer();
                    $e = new \\DateTime();
                    $tz = new \\DateTimeZone('UTC');
                    $u = new \\NumberFormatter('en', 1);
                } catch (PDOException | JsonException $ex) {
                    throw new \\RuntimeException($ex->getMessage(), 0, $ex);
                } catch (Throwable $t) {
                    throw $t;
                }
                return $this->pdo instanceof PDO;
            }
        }
        """
        let diags = fp.queue.sync { NativePHPDiag.analyze(url: root.appendingPathComponent("app/Http/Controllers/T.php"), text: NSString(string: diagSrc), fp: fp) }
        check("diagnostics: built-in classes in every position are not reported (\(diags.map { $0.message }))", diags.isEmpty)
        let bad = diagSrc.replacingOccurrences(of: "$o = new \\stdClass();", with: "$o = new \\stdClass();\n                    $n = new NotThere\\Missing();")
        let badDiags = fp.queue.sync { NativePHPDiag.analyze(url: root.appendingPathComponent("app/Http/Controllers/T.php"), text: NSString(string: bad), fp: fp) }
        check("diagnostics: genuinely unknown namespaced class is still reported", badDiags.contains { $0.message.contains("NotThere") })

        // MARK: stub files are not analysed
        if let stubFile = PHPStubs.classPath("DateTime") {
            check("diagnostics skip stub files", !NativePHPDiag.handles(URL(fileURLWithPath: stubFile)))
        } else { check("DateTime stub path", false) }
        PHPStubs.reset()
    }
}
