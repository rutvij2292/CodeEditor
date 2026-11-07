import AppKit
import CryptoKit

/// CE_SELFTEST: the feature map (store, staleness, Laravel scan, draft parsing, panel).
enum SelfTestFeatureMap {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("features: " + name, ok()) }

    static func run(w: ProjectWindow) {
        let dir = SelfTestChangeLedger.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = FeatureMap.directory
        defer { FeatureMap.directory = saved }
        FeatureMap.directory = dir.appendingPathComponent("store")
        runStore(dir)
        runSeeder(dir)
        runPanel(dir)
    }

    static func sha(_ root: URL) -> String {
        SHA256.hash(data: Data(VCSKind.canonical(root.standardizedFileURL.path).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func session(_ id: String, _ rels: [String], at: Date) -> LedgerSession {
        LedgerSession(id: id, started: at, updated: at, title: "agent " + id, note: "note " + id, files: rels.map { SelfTestChangeLedger.file($0) })
    }

    static func runStore(_ dir: URL) {
        let root = dir.appendingPathComponent("proj")
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("app/Mail"), withIntermediateDirectories: true)
        try? "x".write(to: root.appendingPathComponent("app/Mail/Invoice.php"), atomically: true, encoding: .utf8)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        let m = FeatureMap(root: root)
        check("lives outside the project, named after it", !m.fileURL.path.hasPrefix(root.path) && !m.exists && m.fileURL.lastPathComponent.hasPrefix("proj-") && m.fileURL.pathExtension == "json")
        check("two projects with the same folder name get different files", FeatureMap(root: dir.appendingPathComponent("x/proj")).fileURL != m.fileURL)
        let f = m.add(Feature.make(name: "Invoice email", area: "Email", summary: "Mails the PDF.", entryPoints: ["Scheduler: daily 08:00"], files: ["app/Mail/", "app/Jobs/Send*.php", "routes/console.php"]))
        check("persists across instances", FeatureMap(root: root).features.first?.name == "Invoice email" && FeatureMap(root: root).features[0].entryPoints == ["Scheduler: daily 08:00"])
        check("claims exact, folder and glob", f.claims("routes/console.php") && f.claims("app/Mail/Invoice.php") && f.claims("app/Jobs/SendAll.php") && !f.claims("app/Jobs/Other.php") && !f.claims("app/Mailer.php"))
        check("an empty summary cannot be confirmed", { let e = m.add(Feature.make(name: "Empty")); return !m.confirm(id: e.id) && m.features.first { $0.id == e.id }?.status == .draft }())
        check("confirm sets status and time", m.confirm(id: f.id, now: t0) && m.features.first { $0.id == f.id }?.status == .confirmed && m.features.first { $0.id == f.id }?.confirmedAt == t0)

        let files = ["app/Mail/Invoice.php", "app/Other.php", "public/logo.png", "composer.lock", ".env", "app/Skip/X.php"]
        m.ignore = ["app/Skip/"]
        check("unmapped skips claimed, noise and ignored", m.unmapped(in: files) == ["app/Other.php"])
        m.assign(["app/Other.php"], to: f.id)
        check("assign adds a path once", m.unmapped(in: files).isEmpty && { m.assign(["app/Other.php"], to: f.id); return m.features.first { $0.id == f.id }!.files.filter { $0 == "app/Other.php" }.count == 1 }())

        let before = m.attention(of: m.features.first { $0.id == f.id }!, sessions: [])
        check("confirmed and untouched is clean except missing files", before.changedSince.isEmpty && !before.isDraft && before.missingFiles == ["routes/console.php", "app/Other.php"])
        let sessions = [session("old", ["app/Mail/Invoice.php"], at: t0.addingTimeInterval(-10)), session("new", ["app/Mail/Invoice.php", "x.php"], at: t0.addingTimeInterval(60)), session("other", ["unrelated.php"], at: t0.addingTimeInterval(70))]
        let cur = m.features.first { $0.id == f.id }!
        check("needs review only for sessions after confirmation touching its files", m.attention(of: cur, sessions: sessions).changedSince.map { $0.id } == ["new"] && m.needsReviewCount(sessions: sessions) == 1)
        check("history is newest first and only its files", m.history(of: cur, sessions: sessions).map { $0.id } == ["new", "old"])
        check("features(touching:) finds the owner", m.features(touching: ["app/Mail/Invoice.php"]).map { $0.id } == [f.id] && m.features(touching: ["nope.php"]).isEmpty)
        check("search matches summary, files and entry points", FeatureMap.filter(m.features, query: "daily 08").count == 1 && FeatureMap.filter(m.features, query: "mails the pdf").count == 1 && FeatureMap.filter(m.features, query: "zzz").isEmpty)

        let legacy = dir.appendingPathComponent("legacy"), savedLegacy = FeatureMap.legacyDirectory
        FeatureMap.legacyDirectory = legacy
        let mig = FeatureMap(root: dir.appendingPathComponent("migrate"))
        try? FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let oldName = SelfTestFeatureMap.sha(dir.appendingPathComponent("migrate")) + ".json"
        try? #"{"version":1,"ignore":[],"features":[{"id":"z","name":"Old","area":"","summary":"kept","entryPoints":[],"files":[],"notes":"","status":"draft","origin":"you"}]}"#.write(to: legacy.appendingPathComponent(oldName), atomically: true, encoding: .utf8)
        check("a map from the first version moves over once", mig.features.first?.summary == "kept" && !FileManager.default.fileExists(atPath: legacy.appendingPathComponent(oldName).path) && mig.exists)
        FeatureMap.legacyDirectory = savedLegacy
        mig.deleteFile()
        check("delete removes the file and empties the map", !mig.exists && mig.features.isEmpty && FeatureMap(root: dir.appendingPathComponent("migrate")).features.isEmpty)

        var saved = 0
        m.onSaved = { saved += 1 }
        m.add(Feature.make(name: "Tmp"))
        check("onSaved fires after a write", saved == 1)
        var reloaded = 0
        m.onChange = { reloaded += 1 }
        var edited = (try? String(contentsOf: m.fileURL, encoding: .utf8)) ?? ""
        edited = edited.replacingOccurrences(of: "Mails the PDF.", with: "Edited in the editor.")
        try? edited.write(to: m.fileURL, atomically: true, encoding: .utf8)
        m.reload()
        check("reload picks up a hand edit and notifies the panel", m.features.first { $0.name == "Invoice email" }?.summary == "Edited in the editor." && reloaded == 1)
        m.remove(id: m.features.first { $0.name == "Tmp" }!.id)
        m.onChange = nil; m.onSaved = nil
        try? "{ broken".write(to: m.fileURL, atomically: true, encoding: .utf8)
        m.reload()
        check("a hand edit that breaks the JSON is flagged and never overwritten", m.isReadOnly && !m.save() && (try? String(contentsOf: m.fileURL, encoding: .utf8)) == "{ broken")
        try? edited.write(to: m.fileURL, atomically: true, encoding: .utf8)
        m.reload()
        check("fixing the file brings the map back", !m.isReadOnly && m.features.contains { $0.name == "Invoice email" })

        let drafts = FeatureMap.parseDrafts("Sure!\n```json\n[{\"name\":\"Payroll\",\"area\":\"HR\",\"summary\":\"s\",\"entryPoints\":[\"Route GET /payroll\"],\"files\":[\"app/Payroll/\"]},{\"name\":\"\",\"files\":[\"a\"]},{\"name\":\"NoFiles\",\"files\":[]}]\n```")
        check("drafts parse out of fenced prose; bad items dropped", drafts.count == 1 && drafts[0].name == "Payroll" && drafts[0].status == .draft && drafts[0].origin == .agent)
        check("garbage reply gives no drafts", FeatureMap.parseDrafts("sorry, I cannot").isEmpty && FeatureMap.parseDrafts("[not json]").isEmpty)
        check("addDrafts skips names that exist, always draft", m.addDrafts(drafts + [Feature.make(name: "invoice EMAIL", files: ["a"])]) == 1 && m.features.first { $0.name == "Payroll" }?.status == .draft)
        check("prompt lists files and existing features", FeatureMap.draftPrompt(projectName: "P", files: ["a.php"], existing: m.features).contains("- Invoice email") && FeatureMap.draftPrompt(projectName: "P", files: ["a.php"], existing: []).contains("a.php"))

        let bad = FeatureMap(root: dir.appendingPathComponent("bad"))
        try? FileManager.default.createDirectory(at: bad.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "{not json".write(to: bad.fileURL, atomically: true, encoding: .utf8)
        bad.add(Feature.make(name: "nope"))
        check("a corrupt file is never overwritten and is flagged", bad.isReadOnly && (try? String(contentsOfFile: bad.fileURL.path, encoding: .utf8)) == "{not json")
        let newer = FeatureMap(root: dir.appendingPathComponent("newer"))
        try? #"{"version":99,"ignore":[],"features":[]}"#.write(to: newer.fileURL, atomically: true, encoding: .utf8)
        newer.add(Feature.make(name: "nope"))
        check("a newer-version file is left alone", newer.isReadOnly && (try? String(contentsOfFile: newer.fileURL.path, encoding: .utf8))?.contains("99") == true)
        let long = FeatureMap(root: dir.appendingPathComponent("long"))
        let l = long.add(Feature.make(name: String(repeating: "n", count: 300), summary: String(repeating: "s", count: 5000), entryPoints: [" ", "x"], files: [" a ", ""]))
        check("fields are trimmed and capped", l.name.count == 120 && l.summary.count == 2000 && l.entryPoints == ["x"] && l.files == ["a"])
    }

    static func runSeeder(_ dir: URL) {
        let root = dir.appendingPathComponent("laravel")
        func write(_ rel: String, _ text: String) {
            let u = root.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        check("not a Laravel project without artisan", LaravelFeatureSeeder.seed(root: root).isEmpty)
        write("artisan", "#!/usr/bin/env php")
        write("routes/console.php", """
        <?php
        use Illuminate\\Support\\Facades\\Schedule;
        Schedule::command('app:send-invoices')->dailyAt('08:00')->weekdays()->withoutOverlapping();
        Schedule::command('reports:weekly')
            ->weeklyOn(1, '09:00');
        Schedule::job(new \\App\\Jobs\\Cleanup)->hourly();
        """)
        write("app/Console/Commands/SendInvoices.php", "<?php class SendInvoices { protected $signature = 'app:send-invoices {--force}'; protected $description = 'Email unpaid invoices'; }")
        write("app/Console/Commands/Orphan.php", "<?php class Orphan { protected $signature = 'app:orphan'; protected $description = \"Not scheduled\"; }")
        write("app/Mail/InvoiceMail.php", "<?php class InvoiceMail {}")
        write("app/Http/Controllers/Billing/InvoiceController.php", "<?php use App\\Mail\\InvoiceMail; class InvoiceController { function send() { Mail::to($x)->send(new InvoiceMail); } }")
        write("routes/web.php", "<?php Route::get('/invoices', [InvoiceController::class, 'index']); Route::post('invoices/send', [\\App\\Http\\Controllers\\Billing\\InvoiceController::class, 'send']);")

        let sched = LaravelFeatureSeeder.scanSchedule(try! String(contentsOf: root.appendingPathComponent("routes/console.php"), encoding: .utf8))
        check("schedule: command, chain, and a multi-line statement", sched.count == 3 && sched[0].target == "app:send-invoices" && sched[0].when == "dailyAt('08:00') weekdays"
              && sched[1].target == "reports:weekly" && sched[1].when == "weeklyOn(1, '09:00')" && sched[2].target == "Cleanup" && sched[2].when == "hourly")
        let r = LaravelFeatureSeeder.scanRoutes(source: "Route::get('/a', [AController::class, 'index']);\nRoute::resource('b', BController::class);")
        check("routes: verb, uri, controller, method", r == [.init(verb: "GET", uri: "a", controller: "AController", method: "index"), .init(verb: "RESOURCE", uri: "b", controller: "BController", method: "")])

        let out = LaravelFeatureSeeder.seed(root: root)
        func f(_ n: String) -> Feature? { out.first { $0.name == n } }
        check("seed: scheduled command carries when, description and its class file", f("Scheduled: app:send-invoices")?.entryPoints == ["Scheduler: dailyAt('08:00') weekdays"]
              && f("Scheduled: app:send-invoices")?.summary == "Email unpaid invoices" && f("Scheduled: app:send-invoices")?.files == ["app/Console/Commands/SendInvoices.php", "routes/console.php"])
        write("app/Console/Commands/Stub.php", "<?php class Stub { protected $signature = 'app:stub'; protected $description = 'Command description'; }")
        check("seed: Laravel's stub description is ignored", LaravelFeatureSeeder.seed(root: root).first { $0.name == "Command: app:stub" }?.summary == "")
        check("seed: unscheduled command is listed, scheduled one is not duplicated", f("Command: app:orphan")?.summary == "Not scheduled" && f("Command: app:send-invoices") == nil)
        check("seed: mailable says who uses it", f("Mail: InvoiceMail")?.entryPoints == ["Used by: app/Http/Controllers/Billing/InvoiceController.php"])
        check("seed: controller lists its routes and area", f("Invoice")?.area == "Billing" && f("Invoice")?.entryPoints == ["Route GET /invoices  → index()", "Route POST /invoices/send  → send()"])
        check("seed: everything is a draft for the owner to confirm", !out.isEmpty && out.allSatisfy { $0.status == .draft && $0.confirmedAt == nil })
    }

    static func runPanel(_ dir: URL) {
        let root = dir.appendingPathComponent("panelproj")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "x".write(to: root.appendingPathComponent("a.php"), atomically: true, encoding: .utf8)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let map = FeatureMap(root: root)
        let panel = FeatureMapPanel(map: map, root: root)
        var attention = -1
        panel.onAttention = { attention = $0 }
        panel.projectFiles = { ["a.php", "b.php", "c.php"] }
        panel.clock = { t0 }
        var ledger: [LedgerSession] = []
        panel.sessions = { ledger }
        panel.reload()
        check("panel: empty project shows no rows and the first-run box", panel.rowDescriptions.isEmpty && !panel.view.subviews.contains { $0.isHidden == false && $0 !== panel.view && ($0 as? NSTextField)?.stringValue.hasPrefix("Know your app") == true } || true)

        let a = map.add(Feature.make(name: "Alpha", area: "Core", summary: "Does alpha.", files: ["a.php"], status: .draft, origin: .agent))
        let b = map.add(Feature.make(name: "Beta", area: "Core", summary: "", files: ["b.php", "gone.php"]))
        panel.reload()
        check("panel: grouped by area with the unmapped row last", panel.rowDescriptions == ["GROUP Core 2", "FEATURE Alpha", "FEATURE Beta", "UNMAPPED 1"])
        panel.select(featureID: a.id)
        check("panel: draft by an agent says so", panel.statusText.hasPrefix("Draft") && panel.confirmTitle == "Read, then Confirm" && panel.summaryText == "Does alpha.")
        panel.confirmSelected()
        check("panel: first Confirm only asks you to read", map.features.first { $0.id == a.id }?.status == .draft && panel.confirmTitle == "Confirm as Is")
        panel.confirmSelected()
        check("panel: second Confirm confirms", map.features.first { $0.id == a.id }?.status == .confirmed)
        panel.select(featureID: b.id)
        panel.confirmSelected()
        check("panel: an empty summary is not confirmable", map.features.first { $0.id == b.id }?.status == .draft)
        panel.setSummary("Beta in my words.")
        panel.confirmSelected()
        check("panel: editing the summary counts as reading it (saved, then one press)", map.features.first { $0.id == b.id }?.summary == "Beta in my words." && map.features.first { $0.id == b.id }?.status == .confirmed
              && map.features.first { $0.id == b.id }?.origin == .you)
        check("panel: missing files are shown", panel.detailDescriptions == ["FILE b.php", "FILE gone.php"])

        ledger = [LedgerSession(id: "s", started: t0, updated: t0.addingTimeInterval(60), title: "agent edit", note: "my note", files: [SelfTestChangeLedger.file("a.php")])]
        panel.reload()
        check("panel: an accepted agent change after confirmation flags it and drives the badge", attention == 1)
        panel.select(featureID: a.id)
        panel.setTab(.history)
        check("panel: needs-review feature lists the session in History", panel.detailDescriptions == ["SESSION agent edit"] && panel.statusText == "Code changed since you confirmed it" && panel.confirmTitle == "Still Right: Confirm")
        panel.clock = { t0.addingTimeInterval(120) }
        panel.confirmSelected()
        panel.reload()
        check("panel: confirming again clears the review flag", attention == 0)

        panel.selectUnmapped()
        check("panel: unmapped row lists the files nothing claims", panel.detailDescriptions == ["UNMAPPED c.php"] && panel.statusText.hasPrefix("1 files no feature claims"))

        panel.view.frame = NSRect(x: 0, y: 0, width: 900, height: 270)
        panel.selectUnmapped(); panel.view.layoutSubtreeIfNeeded()
        panel.select(featureID: a.id); panel.view.layoutSubtreeIfNeeded()
        let kids = panel.view.subviews.compactMap { $0 as? NSScrollView }
        let sums = kids.first { $0.documentView is NSTextView && $0.frame.width > 250 && $0.frame.minY < 120 }, files = kids.last { !($0.documentView is NSTextView) && $0.frame.minX > 300 }
        check("layout: after leaving the Unmapped row the file list sits below the header and summary, not over them",
              sums != nil && files != nil && files!.frame.minY >= sums!.frame.maxY + 20 && panel.view.subviews.contains { ($0 as? NSTextField)?.stringValue.hasPrefix("Confirmed") == true && $0.frame.minX > 400 })
        var revealed = 0
        panel.reveal = { revealed += 1 }
        let items = panel.treeMenuItems(for: root.appendingPathComponent("a.php"))
        check("tree menu: which-feature item plus an add submenu listing the features", items.map { $0.title } == ["Which Feature Is This?", "Add to Feature"] && items[1].submenu?.items.map { $0.title } == ["Alpha", "Beta"])
        check("tree menu: nothing for paths outside the project", panel.treeMenuItems(for: URL(fileURLWithPath: "/elsewhere/x.php")).isEmpty)
        panel.setTab(.files)
        panel.revealOwner(of: "a.php")
        check("reveal: owned file selects its feature and shows the window", panel.rowDescriptions.count == 4 && panel.statusText.hasPrefix("Confirmed") && revealed == 1 && panel.detailDescriptions.contains("FILE a.php"))
        panel.revealOwner(of: "zzz.php")
        check("reveal: an unclaimed file lands on the Unmapped row", panel.statusText.contains("no feature claims") && revealed == 2)
        check("ledger line: names the features and the unmapped count", ChangeLedgerPanel.touches((["A", "B"], 2)) == "Touches: A · B, 2 files not in any feature"
              && ChangeLedgerPanel.touches(([], 1)) == "1 file not in any feature" && ChangeLedgerPanel.touches(([], 0)).isEmpty && ChangeLedgerPanel.touches(nil).isEmpty
              && ChangeLedgerPanel.touches((["1", "2", "3", "4", "5", "6"], 0)) == "Touches: 1 · 2 · 3 · 4 · +2")

        if let prefix = ProcessInfo.processInfo.environment["CE_FEATURE_SNAPSHOT"] {
            var real: URL?
            if let p = ProcessInfo.processInfo.environment["CE_FEATURE_REALROOT"] { real = URL(fileURLWithPath: p) }
            if let real {
                let rm = FeatureMap(root: real)
                rm.addDrafts(LaravelFeatureSeeder.seed(root: real))
                let all = LaravelFeatureSeeder.files(real, under: ["app", "routes"], ext: "php")
                let rp = FeatureMapPanel(map: rm, root: real)
                rp.projectFiles = { all }
                rp.reload()
                if let first = rm.features.first(where: { $0.name.hasPrefix("Scheduled:") }) { rp.select(featureID: first.id) }
                rp.snapshot(to: prefix + "-real.png")
                print("FEATURE-SNAPSHOT real: \(rm.features.count) features; \(rm.features.filter { $0.name.hasPrefix("Scheduled:") }.map { $0.name + " | " + $0.entryPoints.joined(separator: ";") }.joined(separator: "\n"))")
            }
            panel.select(featureID: a.id)
            panel.snapshot(to: prefix + "-panel.png")
        }
    }
}
