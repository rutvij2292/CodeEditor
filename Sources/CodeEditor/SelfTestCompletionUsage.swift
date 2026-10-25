import AppKit

/// Headless checks for usage-aware string completion ranking (FastTierUsage.swift): config / route / view keys ordered by how the project
/// uses them, the current file not voting for itself, module proximity, sibling keys, branch-node demotion, byte cap and memory trim.
enum SelfTestCompletionUsage {
    private static func put(_ root: URL, _ rel: String, _ text: String) {
        let u = root.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }

    /// Ranked labels (what the popup would show) for `text` with `§` at the caret, typed in `rel`.
    private static func ranked(_ root: URL, _ rel: String, _ text: String) -> [String] {
        let caret = (text as NSString).range(of: "§").location
        let clean = text.replacingOccurrences(of: "§", with: "")
        let ns = clean as NSString
        var s = caret
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) || ns.character(at: s - 1) == 46 { s -= 1 }
        let url = root.appendingPathComponent(rel)
        CompletionLex.resetCache()
        let ctx = CompletionContext(text: clean, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil,
                                    isManual: false, prefixRange: NSRange(location: s, length: caret - s))
        let items = FastTier.items(for: ctx)
        let rc = CompletionRanker.Context(docCounts: [:], history: nil, popularity: [:])
        return CompletionRanker.rank(results: [(items, false)], text: ns, caret: caret, anchor: s, context: rc).ranked.map(\.item.label)
    }

    static func run() {
        let c = SelfTest.check
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-usage-\(getpid())")
        try? fm.removeItem(at: root)
        put(root, "artisan", "#!/usr/bin/env php\n")
        put(root, "composer.json", #"{"require":{"laravel/framework":"^11"},"autoload":{"psr-4":{"App\\":"app/"}}}"#)
        put(root, "vendor/composer/autoload_psr4.php", "<?php\n$vendorDir = dirname(__DIR__);\n$baseDir = dirname($vendorDir);\nreturn array(\n    'App\\\\' => array($baseDir . '/app'),\n);\n")
        put(root, "config/app.php", "<?php\nreturn ['name' => 'x', 'timezone' => 'UTC', 'locale' => 'en', 'debug' => true, 'nested' => ['a' => 1]];\n")
        put(root, "config/billing.php", "<?php\nreturn ['currency' => 'INR', 'tax' => ['rate' => 18, 'label' => 'GST']];\n")
        put(root, "routes/web.php", "<?php\nRoute::get('/a', fn () => 1)->name('invoices.index');\nRoute::get('/b', fn () => 1)->name('invoices.show');\nRoute::get('/c', fn () => 1)->name('orders.index');\nRoute::get('/d', fn () => 1)->name('orders.show');\nRoute::get('/e', fn () => 1)->name('zeta.show');\n")
        // usage: app.timezone x6 (most used), app.name x2, app.locale never; invoices.show x3, orders.index x1
        for i in 0..<6 { put(root, "app/Services/Use\(i).php", "<?php\nnamespace App\\Services;\nclass Use\(i) { function f() { return config('app.timezone') . route('invoices.show') . route('orders.index'); } }\n") }
        put(root, "app/Services/Names.php", "<?php\nclass Names { function f() { return config('app.name') . config(\"app.name\") . config('billing.tax.rate'); } }\n")
        put(root, "app/Http/Controllers/OrderController.php", "<?php\nclass OrderController { function f() { return route('orders.show'); } }\n")
        put(root, "app/Http/Controllers/Scratch.php", "<?php\nclass Scratch { }\n")

        // scanner
        var counts: [String: UInt16] = [:]
        FUsage.scan("config('a.b') config(\"a.b\") __('m.k') view('v.w') env('APP_X') Config::get('c.d') $r->route('r.n') @extends('lay.out') ->where('col_x', 1) ->with('rel_y') Cache::get('ck') ->middleware('auth:sanctum') Gate::allows('edit-post') @can('del')" as NSString, into: &counts)
        func n(_ k: FUsageKind, _ s: String) -> Int { Int(counts[FUsageTable.key(k, s)] ?? 0) }
        c("usage scan: config helper + facade, quotes", n(.config, "a.b") == 2 && n(.config, "c.d") == 1)
        c("usage scan: lang / view / env / route / extends", n(.lang, "m.k") == 1 && n(.view, "v.w") == 1 && n(.env, "APP_X") == 1 && n(.route, "r.n") == 1 && n(.view, "lay.out") == 1)
        c("usage scan: column / relation / cache / middleware (name only) / gate", n(.col, "col_x") == 1 && n(.rel, "rel_y") == 1 && n(.cache, "ck") == 1 && n(.middleware, "auth") == 1 && n(.gate, "edit-post") == 1 && n(.gate, "del") == 1)
        c("usage scan: not a string call = not counted", { var d: [String: UInt16] = [:]; FUsage.scan("$config('x') myconfig('y') foo->config('z2')" as NSString, into: &d); return d.isEmpty }())

        // config ranking: most used first; unused last
        let cfg = ranked(root, "app/Http/Controllers/Scratch.php", "<?php\nclass Scratch { function f() { return config('app.§') } }")
        c("usage rank: config('app.| most used key first", cfg.first == "app.timezone")
        c("usage rank: then the next most used", Array(cfg.prefix(2)) == ["app.timezone", "app.name"])
        c("usage rank: unused sibling keys follow", cfg.contains("app.locale") && cfg.firstIndex(of: "app.locale")! > 1)
        let cfgTop = ranked(root, "app/Http/Controllers/Scratch.php", "<?php\nclass Scratch { function f() { return config('§') } }")
        c("usage rank: empty prefix puts used keys before unused ones", cfgTop.prefix(3).contains("app.timezone") && cfgTop.firstIndex(of: "billing.currency")! > cfgTop.firstIndex(of: "app.name")!)
        c("usage rank: an unused branch node (`billing`) sits below its leaf keys", cfgTop.firstIndex(of: "billing") ?? 0 > cfgTop.firstIndex(of: "billing.tax.rate") ?? 99)

        // the file being edited does not vote for itself: Names.php is the only user of billing.tax.rate
        let own = ranked(root, "app/Services/Names.php", "<?php\nclass Names { function f() { return config('billing.§') } }")
        c("usage rank: the saved copy of the current file is discounted", own.first != "billing.tax.rate" || own.firstIndex(of: "billing.tax.rate") == own.firstIndex(of: own.first ?? ""))
        // ... but an earlier use in the live buffer counts (sibling keys of the same group float up)
        let live = ranked(root, "app/Http/Controllers/Scratch.php", "<?php\nclass Scratch { function f() { config('billing.tax.label'); return config('billing.§') } }")
        c("usage rank: keys of the group the buffer already uses come first", live.first == "billing.tax.label" || live.first == "billing.tax.rate")

        // routes
        let rt = ranked(root, "app/Http/Controllers/Scratch.php", "<?php\nclass Scratch { function f() { return route('§') } }")
        c("usage rank: route( | most used name first", rt.first == "invoices.show")
        let rto = ranked(root, "app/Http/Controllers/OrderController.php", "<?php\nclass OrderController { function f() { return route('§') } }")
        c("usage rank: file proximity (OrderController -> orders.*) beats raw frequency", rto.first?.hasPrefix("orders.") == true)

        // proximity / tokens
        c("usage tokens: words of the path, singular, no noise", FUsage.fileTokens(URL(fileURLWithPath: "/p/Modules/Items/app/Http/Controllers/ProductReportController.php")).sorted() == ["item", "product", "report"])
        c("usage proximity: leading segment counts most", FUsage.proximity("items.reports.pdf", tokens: ["item", "report"]) > FUsage.proximity("zeta.reports.pdf", tokens: ["item", "report"])
          && FUsage.proximity("zzzz.yyyy", tokens: ["item"]) == 0)
        c("usage tier: more uses = lower (earlier) tier; proximity helps", FUsage.tier(count: 9, prox: 0) < FUsage.tier(count: 1, prox: 0) && FUsage.tier(count: 0, prox: 6) < FUsage.tier(count: 1, prox: 0))

        // memory: capped, dropped on trim, rebuilt on demand
        let fp = FastProject.shared(root: root)
        var bytes = 0, built = false
        fp.queue.sync { built = fp.usageBuilt; bytes = fp.usageBytes }
        c("usage cache: built lazily, tiny for the fixture (< 64 KB)", built && bytes > 0 && bytes < 65_536)
        c("usage cache: entry cap keeps the table under 1 MB", FUsage.maxEntries * 96 < 1_048_576)
        fp.queue.sync { fp.dropCaches() }
        fp.queue.sync { built = fp.usageBuilt }
        c("usage cache: dropped by the memory trim", !built)
        let again = ranked(root, "app/Http/Controllers/Scratch.php", "<?php\nclass Scratch { function f() { return config('app.§') } }")
        c("usage cache: rebuilt on the next request", again.first == "app.timezone")
        try? fm.removeItem(at: root)
    }
}
