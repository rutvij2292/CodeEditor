import Foundation

/// Builds a first draft of the Feature Map for a Laravel project without any AI: scheduled tasks (what runs when), Artisan commands,
/// mailables / notifications / jobs / listeners (with the files that use them), and controllers (with their routes). One-shot, run only
/// when the user asks; every result is a draft the owner still has to read and confirm.
enum LaravelFeatureSeeder {
    static func isLaravel(_ root: URL) -> Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("artisan").path) }

    private struct Command { var signature: String; var description: String; var rel: String; var className: String }

    static func seed(root: URL) -> [Feature] {
        guard isLaravel(root) else { return [] }
        let phpFiles = files(root, under: ["app"], ext: "php")
        let texts = Dictionary(uniqueKeysWithValues: phpFiles.compactMap { rel in text(root, rel).map { (rel, $0) } })
        let commands = scanCommands(phpFiles, texts)
        var out: [Feature] = []

        // Scheduled tasks first: "when does X run" is the question that gets asked.
        var scheduledSignatures = Set<String>()
        let scheduleFiles = ["routes/console.php", "app/Console/Kernel.php"].filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        for sf in scheduleFiles {
            guard let t = text(root, sf) else { continue }
            for item in scanSchedule(t) {
                let cmd = commands.first { $0.signature == item.target || $0.className == item.target }
                if let c = cmd { scheduledSignatures.insert(c.signature) }
                let label = cmd?.signature ?? item.target
                var f = Feature.make(name: "Scheduled: " + label, area: "Scheduler", summary: cmd?.description ?? "",
                                     entryPoints: ["Scheduler: " + item.when], files: [cmd?.rel, sf].compactMap { $0 })
                f.origin = .agent
                out.append(f)
            }
        }

        for c in commands where !scheduledSignatures.contains(c.signature) {
            out.append(draft("Command: " + c.signature, "Artisan commands", c.description, ["php artisan " + c.signature], [c.rel]))
        }

        // Mail, notifications, jobs, listeners: find where each one is used.
        let kinds: [(dir: String, label: String, area: String)] = [
            ("app/Mail/", "Mail", "Email & notifications"), ("app/Notifications/", "Notification", "Email & notifications"),
            ("app/Jobs/", "Job", "Jobs & events"), ("app/Listeners/", "Listener", "Jobs & events"), ("app/Events/", "Event", "Jobs & events"),
        ]
        for k in kinds {
            for rel in phpFiles where rel.hasPrefix(k.dir) {
                let cls = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
                let users = phpFiles.filter { $0 != rel && (texts[$0]?.contains(cls) ?? false) }
                var entry = users.prefix(6).map { "Used by: " + $0 }
                if users.count > 6 { entry.append("… and \(users.count - 6) more files use it") }
                if users.isEmpty { entry.append("Not referenced from app/ (may be queued by name, config or a package)") }
                out.append(draft("\(k.label): \(cls)", k.area, "", entry, [rel]))
            }
        }

        // Controllers with the routes that point at them.
        let routes = scanRoutes(root)
        for rel in phpFiles where rel.hasPrefix("app/Http/Controllers/") && rel.hasSuffix("Controller.php") {
            let cls = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
            let sub = ((rel as NSString).deletingLastPathComponent as NSString).replacingOccurrences(of: "app/Http/Controllers", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let mine = routes.filter { $0.controller == cls }
            var entry = mine.prefix(15).map { "Route \($0.verb) /\($0.uri)" + ($0.method.isEmpty ? "" : "  → \($0.method)()") }
            if mine.count > 15 { entry.append("… and \(mine.count - 15) more routes") }
            if mine.isEmpty { entry.append("No route found for this controller (route groups, invokable or API resource may hide it)") }
            out.append(draft(cls.replacingOccurrences(of: "Controller", with: ""), sub.isEmpty ? "Web" : sub, "", entry, [rel]))
        }
        return out
    }

    private static func draft(_ name: String, _ area: String, _ summary: String, _ entry: [String], _ files: [String]) -> Feature {
        Feature.make(name: name, area: area, summary: summary, entryPoints: entry, files: files, status: .draft, origin: .agent)
    }

    // MARK: Scanners (internal for tests)

    /// Scheduled items in `source`: what is scheduled (command signature or class) and the chain that says when.
    static func scanSchedule(_ source: String) -> [(target: String, when: String)] {
        var out: [(String, String)] = []
        let ns = source as NSString
        let head = try! NSRegularExpression(pattern: #"(?:Schedule::|\$schedule->)(command|job|call|exec)\s*\(\s*(?:'([^']*)'|"([^"]*)"|(function|fn)\b|(?:new\s+)?([A-Za-z0-9_\\]+)(?:::class)?)"#)
        for m in head.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            var target = [2, 3, 5].compactMap { m.range(at: $0).location != NSNotFound ? ns.substring(with: m.range(at: $0)) : nil }.first ?? "closure"
            if m.range(at: 4).location != NSNotFound { target = "closure at line \(LaravelFS.lineCol(ns, m.range.location).0)" }
            if m.range(at: 4).location == NSNotFound {
                if m.range(at: 5).location != NSNotFound { target = target.components(separatedBy: "\\").last ?? target }       // App\\Jobs\\X -> X
                else if let cut = target.firstIndex(of: " ") { target = String(target[..<cut]) }                            // 'cmd --flag' -> cmd
            }
            // The statement runs to the next ";" after the match.
            let from = m.range.location + m.range.length
            let rest = ns.substring(from: from)
            let end = rest.firstIndex(of: ";") ?? rest.endIndex
            let chain = String(rest[..<end])
            let freq = try! NSRegularExpression(pattern: #"->\s*(everyMinute|everyTwoMinutes|everyFiveMinutes|everyTenMinutes|everyFifteenMinutes|everyThirtyMinutes|hourly|hourlyAt|everyOddHour|daily|dailyAt|twiceDaily|twiceDailyAt|weekly|weeklyOn|monthly|monthlyOn|twiceMonthly|quarterly|yearly|cron|at|weekdays|weekends|mondays|tuesdays|wednesdays|thursdays|fridays|saturdays|sundays|between|timezone|when|skip|environments|withoutOverlapping|onOneServer|runInBackground)\s*\(([^()]*)\)"#)
            let cns = chain as NSString
            var parts: [String] = []
            for c in freq.matches(in: chain, range: NSRange(location: 0, length: cns.length)) {
                let name = cns.substring(with: c.range(at: 1)), arg = cns.substring(with: c.range(at: 2)).trimmingCharacters(in: .whitespaces)
                if ["withoutOverlapping", "onOneServer", "runInBackground"].contains(name) { continue }
                parts.append(arg.isEmpty ? name : "\(name)(\(arg))")
            }
            out.append((target, parts.isEmpty ? "(schedule not recognised, open the file)" : String(parts.joined(separator: " ").prefix(160))))
        }
        return out
    }

    private static func scanCommands(_ rels: [String], _ texts: [String: String]) -> [Command] {
        let sig = try! NSRegularExpression(pattern: #"\$signature\s*=\s*(?:'([^']*)'|"([^"]*)")"#)
        let desc = try! NSRegularExpression(pattern: #"\$description\s*=\s*(?:'([^']*)'|"([^"]*)")"#)
        func first(_ r: NSRegularExpression, _ t: String) -> String? {
            let ns = t as NSString
            guard let m = r.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return [1, 2].compactMap { m.range(at: $0).location != NSNotFound ? ns.substring(with: m.range(at: $0)) : nil }.first
        }
        return rels.filter { $0.hasPrefix("app/Console/Commands/") }.compactMap { rel in
            guard let t = texts[rel], let s = first(sig, t) else { return nil }
            let name = String(s.split(separator: " ").first ?? "")
            let cls = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
            let d = first(desc, t) ?? ""
            return Command(signature: name, description: d == "Command description" ? "" : d, rel: rel, className: cls)     // Laravel's stub text is not a description
        }
    }

    struct RouteRow: Equatable { var verb: String; var uri: String; var controller: String; var method: String }

    /// Routes of the common `Route::verb('uri', [Controller::class, 'method'])` and `Controller::class` resource shapes. Group prefixes are not applied.
    static func scanRoutes(_ root: URL) -> [RouteRow] {
        var rows: [RouteRow] = []
        for rel in files(root, under: ["routes"], ext: "php") { if let t = text(root, rel) { rows += scanRoutes(source: t) } }
        return rows
    }

    static func scanRoutes(source: String) -> [RouteRow] {
        let re = try! NSRegularExpression(pattern: #"Route::(get|post|put|patch|delete|any|resource|apiResource)\(\s*['"]([^'"]*)['"]\s*,\s*\[?\s*(?:\\?[A-Za-z0-9_]+\\)*([A-Za-z0-9_]+)::class\s*(?:,\s*['"](\w+)['"])?"#)
        let ns = source as NSString
        return re.matches(in: source, range: NSRange(location: 0, length: ns.length)).map { m in
            func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            let verb = g(1)
            return RouteRow(verb: verb.hasSuffix("esource") ? "RESOURCE" : verb.uppercased(), uri: g(2).trimmingCharacters(in: CharacterSet(charactersIn: "/")), controller: g(3), method: g(4))
        }
    }

    // MARK: Files

    static func files(_ root: URL, under dirs: [String], ext: String) -> [String] {
        var out: [String] = []
        let skip: Set<String> = ["vendor", "node_modules", "storage", ".git"]
        for d in dirs {
            let base = root.appendingPathComponent(d)
            guard let en = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let u as URL in en {
                if skip.contains(u.lastPathComponent) { en.skipDescendants(); continue }
                guard u.pathExtension == ext else { continue }
                let p = u.standardizedFileURL.path, r = root.standardizedFileURL.path + "/"
                if p.hasPrefix(r) { out.append(String(p.dropFirst(r.count))) }
                if out.count > 20_000 { return out.sorted() }
            }
        }
        return out.sorted()
    }

    private static func text(_ root: URL, _ rel: String) -> String? {
        let url = root.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url), data.count < 1_500_000 else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
