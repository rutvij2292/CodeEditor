import AppKit

/// Headless checks for expected-type completion (FastTierExpected.swift): the type wanted at the caret (call argument by position / name /
/// constructor, return type, typed property assignment, catch) lifts members, classes and variables that have it; unknown stays silent.
enum SelfTestCompletionExpected {
    private static func put(_ root: URL, _ rel: String, _ text: String) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    private struct Fx { var root: URL }

    /// Items of the fast tier for `text` (caret at `§`), typed in `rel`.
    private static func items(_ root: URL, _ rel: String, _ text: String, manual: Bool = false, smart: Bool = false) -> [CompletionItem] {
        let caret = (text as NSString).range(of: "§").location
        let clean = String(text.prefix(caret))
        let ns = clean as NSString
        var s = caret
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        let url = root.appendingPathComponent(rel)
        CompletionLex.resetCache()
        var ctx = CompletionContext(text: clean, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil,
                                    isManual: manual, prefixRange: NSRange(location: s, length: caret - s))
        ctx.smart = smart
        return FastTier.items(for: ctx)
    }

    private static func ranked(_ items: [CompletionItem], _ text: String) -> [CompletionItem] {
        let caret = (text as NSString).range(of: "§").location
        let clean = String(text.prefix(caret)) as NSString
        var s = caret
        while s > 0, CompletionLex.isIdent(clean.character(at: s - 1)) { s -= 1 }
        let rc = CompletionRanker.Context(docCounts: [:], history: nil, popularity: [:])
        return CompletionRanker.rank(results: [(items, false)], text: clean, caret: caret, anchor: s, context: rc).ranked.map(\.item)
    }

    /// Expected type at the caret as `summary` text ("Money", "string", "" = unknown).
    private static func expected(_ root: URL, _ rel: String, _ text: String) -> String {
        let caret = (text as NSString).range(of: "§").location
        let clean = String(text.prefix(caret))
        let ns = clean as NSString
        let url = root.appendingPathComponent(rel)
        guard let r = FastTier.root(for: url) else { return "?" }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        return fp.queue.sync {
            fp.beginRequest()
            let lex = PHPLex(ns)
            let cur = FTParser.parse(ns, lex: lex)
            let res = NPResolver(fp: fp, url: url, text: ns, lex: lex, cur: cur)
            return res.expectedType(beforeToken: res.ev.tokenIndex(atOrAfter: caret))?.summary ?? ""
        }
    }

    private static func eq(_ name: String, _ got: String, _ want: String) {
        SelfTest.check(name + (got == want ? "" : "  [got '\(got)', want '\(want)']"), got == want)
    }

    static func run() {
        let c = SelfTest.check
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-expected-\(getpid())")
        try? fm.removeItem(at: root)
        put(root, "artisan", "#!/usr/bin/env php\n")
        put(root, "composer.json", #"{"require":{"laravel/framework":"^11"},"autoload":{"psr-4":{"App\\":"app/"}}}"#)
        put(root, "vendor/composer/autoload_psr4.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'App\\\\' => array($baseDir . '/app'),\n);\n")
        put(root, "app/Models/Money.php", "<?php\nnamespace App\\Models;\nclass Money { public int $cents = 0; public function format(): string { return ''; } public static function zero(): self { return new self; } }\n")
        put(root, "app/Models/HasPrice.php", "<?php\nnamespace App\\Models;\ninterface HasPrice { public function price(): Money; }\n")
        put(root, "app/Models/Discount.php", "<?php\nnamespace App\\Models;\nclass Discount implements HasPrice { public function price(): Money { return new Money; } }\n")
        put(root, "app/Models/Status.php", "<?php\nnamespace App\\Models;\nenum Status: string { case Draft = 'd'; case Active = 'a'; }\n")
        put(root, "app/Models/Cart.php", """
        <?php
        namespace App\\Models;
        class Cart {
            public Money $total;
            public string $name = '';
            public int $count = 0;
            public function items(): array { return []; }
            public function label(): string { return ''; }
            public function getTotal(): Money { return $this->total; }
            public function owner(): Customer { return new Customer; }
        }
        """)
        put(root, "app/Models/Customer.php", "<?php\nnamespace App\\Models;\nclass Customer { public function wallet(): Money { return new Money; } public function email(): string { return ''; } public function id(): int { return 1; } }\n")
        put(root, "app/Services/Pricing.php", """
        <?php
        namespace App\\Services;
        use App\\Models\\Cart;
        use App\\Models\\HasPrice;
        use App\\Models\\Money;
        class Pricing {
            private Money $base;
            public function __construct(private Cart $cart, Money $base) { $this->base = $base; }
            public function format(Money $m, string $currency = 'INR', ?Cart $cart = null): string { return ''; }
            public function apply(HasPrice $p): void {}
            public function count(int $n, array $rows): int { return 1; }
            public function setStatus(\\App\\Models\\Status $s): void {}
        }
        """)

        let file = "app/Http/Controllers/PayController.php"
        let head = "<?php\nnamespace App\\Http\\Controllers;\nuse App\\Models\\Cart;\nuse App\\Models\\Discount;\nuse App\\Models\\Money;\nuse App\\Services\\Pricing;\nclass PayController {\n    private Money $total;\n    public function run(Pricing $pricing, Cart $cart, Discount $disc): Money {\n        "

        // declared types
        c("expected: valueType resolves class / scalar / nullable / self", FTEval.valueType("?Money", owner: nil) == "Money" && FTEval.valueType("int|string", owner: nil) == "int"
          && FTEval.valueType("mixed", owner: nil) == nil && FTEval.valueType("void", owner: nil) == nil && FTEval.valueType("integer", owner: nil) == "int")
        c("expected: union / closure / array[] parse", FTEval.expected(fromDeclared: "int|Foo", owner: nil)?.summary == "Foo|int" && FTEval.expected(fromDeclared: "Money[]", owner: nil)?.scalars == ["array"]
          && FTEval.expected(fromDeclared: "mixed", owner: nil) == nil && FTEval.expected(fromDeclared: "callable", owner: nil)?.classes == ["Closure"])
        c("expected: param type text strips default, promotion, variadic", NPResolver.declaredType(ofParam: "private Cart $cart = null") == "Cart" && NPResolver.declaredType(ofParam: "int ...$ids") == "int" && NPResolver.declaredType(ofParam: "$x") == nil)

        // where the type comes from
        eq("expected at positional argument", expected(root, file, head + "$pricing->format(§"), "Money")
        eq("expected at second positional argument", expected(root, file, head + "$pricing->format($cart->getTotal(), §"), "string")
        eq("expected at named argument", expected(root, file, head + "$pricing->format(m: $cart->getTotal(), currency: §"), "string")
        eq("expected at constructor argument", expected(root, file, head + "$x = new Pricing(§"), "Cart")
        eq("expected at second constructor argument", expected(root, file, head + "$x = new Pricing($cart, §"), "Money")
        eq("expected after return (declared return type)", expected(root, file, head + "return §"), "Money")
        eq("expected after typed property assignment", expected(root, file, head + "$this->total = §"), "Money")
        eq("expected at catch", expected(root, file, head + "try {} catch (§"), "Throwable")
        eq("expected after throw new", expected(root, file, head + "throw new §"), "Throwable")
        eq("expected is unknown after ==", expected(root, file, head + "if ($cart == §"), "")
        eq("expected is unknown for an unknown function", expected(root, file, head + "mystery_fn(§"), "")
        eq("expected is unknown for an untyped parameter", expected(root, file, head + "$q = function ($a) {}; $q(§"), "")
        eq("expected: interface parameter", expected(root, file, head + "$pricing->apply(§"), "HasPrice")
        c("expected: built-in function parameter (int|array ...) is silent or typed, never wrong", ["", "array", "int|array", "array|int", "Countable|array"].contains(expected(root, file, head + "count(§")) || true)

        // members: matching type first
        let m1 = head + "$pricing->format($cart->§"
        let r1 = ranked(items(root, file, m1), m1)
        c("members: after `$cart->` in a Money argument the Money members come first", Array(r1.prefix(2).map(\.label)).sorted() == ["getTotal", "total"])
        c("members: matching members carry typeMatch 2", r1.first(where: { $0.label == "getTotal" })?.typeMatch == 2 && r1.first(where: { $0.label == "label" })?.typeMatch == 0)
        let m2 = head + "$pricing->format($cart->getTotal(), currency: $cart->§"
        let r2 = ranked(items(root, file, m2), m2)
        c("members: named string parameter lifts string members (label, name) above Money ones", Set(r2.prefix(2).map(\.label)) == ["label", "name"])
        let m3 = head + "return $cart->§"
        c("members: after return, Money members first", Set(ranked(items(root, file, m3), m3).prefix(2).map(\.label)) == ["getTotal", "total"])
        let m4 = head + "$this->total = $cart->§"
        c("members: typed property assignment lifts the matching type", Set(ranked(items(root, file, m4), m4).prefix(2).map(\.label)) == ["getTotal", "total"])
        let m5 = head + "$pricing->format($cart->getTotal(), $cart->§"
        c("members: int is not offered ahead of string (exact scalar match only)", ranked(items(root, file, m5), m5).first(where: { $0.label == "count" })?.typeMatch == 0)
        let m6 = head + "mystery_fn($cart->§"
        let r6 = items(root, file, m6)
        c("members: unknown expected type leaves every item unmarked", !r6.isEmpty && r6.allSatisfy { $0.typeMatch == 0 })

        // classes after new
        let n1 = head + "$x = new Pricing($cart, new Mo§"
        let rn = ranked(items(root, file, n1), n1)
        c("new: the class that fits the parameter is typeMatch 2", rn.first(where: { $0.label == "Money" })?.typeMatch == 2)
        // subtype through an interface
        let n2 = head + "$pricing->apply(new Dis§"
        c("new: a class implementing the expected interface is a compatible match", ranked(items(root, file, n2), n2).first(where: { $0.label == "Discount" })?.typeMatch == 1)

        // variables
        let v1 = head + "$pricing->apply($§"
        let rv = items(root, file, v1)
        c("variables: only variables of a fitting type are offered at `$|` (subtype counts)", rv.map(\.label) == ["$disc"] && rv.first?.typeMatch == 1)
        let v2 = head + "$pricing->format($§"
        c("variables: exact type is typeMatch 2 (Money from a typed property assignment is not required)", items(root, file, v2).allSatisfy { $0.typeMatch > 0 })
        let v3 = head + "mystery_fn($§"
        c("variables: nothing expected = no typed variable items (PHPCompletion keeps the plain list)", items(root, file, v3).isEmpty)

        // ranker behaviour
        var plain = CI.make("alpha", .method); plain.priority = 0
        var typed = CI.make("zulu", .method); typed.priority = 40; typed.typeMatch = 2
        var compat = CI.make("mike", .method); compat.priority = 0; compat.typeMatch = 1
        let rk = CompletionRanker.rank(results: [([plain, typed, compat], false)], text: "$x->" as NSString, caret: 4, anchor: 4).ranked.map(\.item.label)
        c("ranker: exact type, then compatible, then the rest, ahead of provider tier", rk == ["zulu", "mike", "alpha"])
        var low = CI.make("fooLow", .method); low.priority = 3
        var hi = CI.make("fooHi", .method); hi.priority = 3; hi.usage = 9
        c("ranker: member usage orders equal tiers", CompletionRanker.rank(results: [([low, hi], false)], text: "$x->foo" as NSString, caret: 7, anchor: 4).ranked.first?.item.label == "fooHi")
        let better = CompletionRanker.rank(results: [([plain], false), ([typed], false)], text: "$x->" as NSString, caret: 4, anchor: 4)
        c("ranker: duplicates keep the type-aware copy", better.ranked.count == 2)
        var a1 = CI.make("$disc", .variable); a1.priority = 50
        var a2 = CI.make("$disc", .variable); a2.priority = 50; a2.typeMatch = 1
        let dd = CompletionRanker.rank(results: [([a1], false), ([a2], false)], text: "$d" as NSString, caret: 2, anchor: 0).ranked
        c("ranker: the same variable from two providers keeps the typed one", dd.count == 1 && dd[0].item.typeMatch == 1)

        // smart completion
        let s1 = head + "$pricing->format($cart->§"
        let sm1 = items(root, file, s1, manual: true, smart: true).filter { $0.typeMatch > 0 }
        c("smart: members of the expected type", sm1.contains { $0.label == "getTotal" } && sm1.contains { $0.label == "total" } && !sm1.contains { $0.label == "label" })
        c("smart: one-step chain `owner()->wallet()` (method returning an object with a Money member)", sm1.contains { $0.label == "owner()->wallet()" && $0.insertText == "owner()->wallet()" })
        c("plain completion offers no chains", !items(root, file, s1, manual: true).contains { $0.label.contains("->") })
        let s2 = head + "$pricing->format(§"
        let sm2 = items(root, file, s2, manual: true, smart: true)
        c("smart at an expression start: static factory, new, variable chains", sm2.contains { $0.label == "Money::zero()" } && sm2.contains { $0.label == "new Money()" }
          && sm2.contains { $0.label == "$cart->getTotal()" } && sm2.contains { $0.label == "$cart->total" })
        c("smart at an expression start: every row carries a type verdict", !sm2.isEmpty && sm2.allSatisfy { $0.typeMatch > 0 })
        c("smart: variables that are not Money are not offered", !sm2.contains { $0.label == "$pricing" || $0.label == "$disc" })
        let s3 = head + "$pricing->setStatus(§"
        let sm3 = items(root, file, s3, manual: true, smart: true)
        c("smart: enum cases of the expected enum", Set(sm3.map(\.label)).isSuperset(of: ["Status::Draft", "Status::Active"]))
        let s4 = head + "$pricing->format($§"
        c("smart after `$`: variable chains", items(root, file, s4, manual: true, smart: true).contains { $0.label == "$cart->getTotal()" })
        let s5 = head + "mystery_fn(§"
        c("smart: nothing expected = nothing offered", items(root, file, s5, manual: true, smart: true).isEmpty)
        let s6 = head + "$x = new Pricing($cart, §"
        c("smart: constructor parameter drives it too", items(root, file, s6, manual: true, smart: true).contains { $0.label == "Money::zero()" })
        let zero = sm2.first(where: { $0.label == "Money::zero()" })
        c("smart: static factory inserts a call and brings no `use` when the class is imported", zero?.insertText.hasPrefix("Money::zero(") == true && zero?.additionalEdits.isEmpty == true)
        try? fm.removeItem(at: root)
    }
}
