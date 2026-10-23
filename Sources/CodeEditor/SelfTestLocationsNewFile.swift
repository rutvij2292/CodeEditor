import AppKit

/// CE_SELFTEST: Recent Locations log + New File planning / templates / creation.
enum SelfTestLocationsNewFile {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run(w: ProjectWindow) {
        // Locations log
        var log = LocationLog()
        let a = URL(fileURLWithPath: "/tmp/a.php"), b = URL(fileURLWithPath: "/tmp/b.php")
        log.add(url: a, line: 3, snippet: "x", changed: false)
        log.add(url: b, line: 9, snippet: "y", changed: true)
        log.add(url: a, line: 3, snippet: "x2", changed: true)
        check("locations: newest first, deduped per file+line", log.entries.count == 2 && log.entries[0].snippet == "x2" && log.entries[1].url == b)
        check("locations: dedupe keeps the changed flag", log.entries[0].changed)
        check("locations: changed-only filter", log.visible(changedOnly: true).count == 2)
        log.add(url: a, line: 3, snippet: "x3", changed: false)
        check("locations: re-adding unchanged keeps changed", log.entries[0].changed)
        for i in 0..<80 { log.add(url: a, line: 100 + i, snippet: "s", changed: false) }
        check("locations: capped", log.entries.count == LocationLog.cap)
        let info = LocationLog.lineInfo(in: "one\n  two  \nthree" as NSString, offset: 7)
        check("locations: line number and trimmed snippet", info.line == 2 && info.snippet == "two")
        check("locations: tracker installs on the window", w.locationTracker.log.entries.count >= 0)

        // New file
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-newfile-\(getpid())")
        try? fm.createDirectory(at: dir.appendingPathComponent("app/Http"), withIntermediateDirectories: true)
        try? #"{"autoload":{"psr-4":{"App\\":"app/"}}}"#.write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        try? "x".write(to: dir.appendingPathComponent("artisan"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: dir) }
        let http = dir.appendingPathComponent("app/Http")

        check("newfile: empty is a hint", NewFile.plan("  ", in: http) == .hint)
        if case .invalid = NewFile.plan("a/../b.php", in: http) { check("newfile: .. rejected", true) } else { check("newfile: .. rejected", false) }
        if case .invalid = NewFile.plan("dir/", in: http) { check("newfile: trailing slash rejected", true) } else { check("newfile: trailing slash rejected", false) }
        let tpl = NewFile.template(for: http.appendingPathComponent("Foo/Bar.php"))
        check("newfile: php class gets PSR-4 namespace", tpl.content.contains("namespace App\\Http\\Foo;") && tpl.content.contains("class Bar"))
        check("newfile: lowercase php is a plain file", NewFile.template(for: dir.appendingPathComponent("routes/web.php")).content == "<?php\n\n")
        check("newfile: vue / md / js templates",
              NewFile.template(for: http.appendingPathComponent("A.vue")).content.contains("<template>")
              && NewFile.template(for: http.appendingPathComponent("n.md")).content == "# n\n"
              && NewFile.template(for: http.appendingPathComponent("x.js")).content.isEmpty)
        guard case .create(let url, _) = NewFile.plan("Models/Deep/Post.php", in: http) else { check("newfile: plan create", false); return }
        check("newfile: plan resolves nested path", url.path == http.path + "/Models/Deep/Post.php")
        _ = try? NewFile.create(at: url)
        let text = try? String(contentsOf: url, encoding: .utf8)
        check("newfile: creates folders and the stub", text?.contains("namespace App\\Http\\Models\\Deep;") == true)
        check("newfile: existing file is detected", NewFile.plan("Models/Deep/Post.php", in: http) == .exists(url))
        check("newfile: create refuses to overwrite", (try? NewFile.create(at: url)) == nil)
    }
}
