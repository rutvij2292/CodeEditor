import AppKit

/// Artisan command palette, route browser and the make:* dialog, all reachable from the Navigate menu (and so from Find Action).
extension AppDelegate {
    @objc func artisanPalette(_ sender: Any?) { active?.showArtisanPalette() }
    @objc func routeBrowser(_ sender: Any?) { active?.showRouteBrowser() }
    @objc func artisanMake(_ sender: Any?) { active?.showMakeDialog() }
}

enum ArtisanPalette {
    /// Fuzzy filter over picker rows (the picker's own filtering only applies to static item lists).
    static func filter(_ items: [PickerItem], query: String) -> [PickerItem] {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        if q.isEmpty { return items }
        var scored: [(Int, PickerItem)] = []
        for item in items { if let s = Fuzzy.score(q, in: item.key) { scored.append((s, item)) } }
        return scored.sorted { $0.0 > $1.0 }.map(\.1)
    }

    static func commandItems(_ commands: [ArtisanCommand], run: @escaping (ArtisanCommand) -> Void) -> [PickerItem] {
        commands.map { c in
            // The picker truncates details from the head, so shorten long descriptions here (tail ellipsis).
            PickerItem(title: c.name, detail: c.summary.count > 60 ? String(c.summary.prefix(59)) + "…" : c.summary, symbol: c.name.hasPrefix("make:") ? "plus.square" : "terminal",
                       key: "\(c.name) \(c.summary)") { run(c) }
        }
    }

    /// "migrate --seed" -> ("migrate", "--seed") when the first word is exactly a known command; nil otherwise.
    static func inlineInvocation(_ query: String, in commands: [ArtisanCommand]) -> (ArtisanCommand, String)? {
        guard let space = query.firstIndex(of: " ") else { return nil }
        let name = String(query[..<space])
        guard let c = commands.first(where: { $0.name == name }) else { return nil }
        return (c, String(query[query.index(after: space)...]).trimmingCharacters(in: .whitespaces))
    }

    /// Arguments of `command` still missing from what has been typed (quotes respected, `-flags` ignored).
    static func missingArguments(_ command: ArtisanCommand, typed: String) -> [ArtisanArgument] {
        var tokens: [String] = [], cur = "", quote: Character?
        for ch in typed {
            if let q = quote { if ch == q { quote = nil } else { cur.append(ch) } }
            else if ch == "\"" || ch == "'" { quote = ch }
            else if ch == " " { if !cur.isEmpty { tokens.append(cur); cur = "" } }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        let positional = tokens.filter { !$0.hasPrefix("-") }.count
        return Array(command.requiredArguments.dropFirst(positional))
    }
}

extension ProjectWindow {
    private func laravelProjectForArtisan() -> LaravelProject? {
        guard let root else { return nil }
        return LaravelProject.find(for: root.appendingPathComponent("artisan"))
    }

    private func artisanNotice(_ title: String, _ detail: String = "") {
        QuickPicker.present(over: window, placeholder: "Artisan", items: [PickerItem(title: title, detail: detail, symbol: "exclamationmark.triangle") {}])
    }

    private func openArtisanLocation(_ t: LaravelTarget) {
        open(t.url, line: t.line)
        current?.textView.goToLine(t.line, column: t.column)
    }

    /// Presents a picker immediately (with a loading row), fills it when php answers, and re-filters in place.
    private func presentArtisanPicker(placeholder: String, loading: String, rows: @escaping (LaravelProject) -> (@escaping (Result<[PickerItem], ArtisanError>) -> Void) -> Void,
                                      provider custom: ((String) -> [PickerItem]?)? = nil) {
        guard let p = laravelProjectForArtisan() else { artisanNotice("Not a Laravel project", "No artisan file found"); return }
        final class Box { var items: [PickerItem] = [] }
        let box = Box()
        box.items = [PickerItem(title: loading, symbol: "hourglass") {}]
        QuickPicker.present(over: window, placeholder: placeholder, items: [], provider: { q in
            if let r = custom?(q) { return r }
            return ArtisanPalette.filter(box.items, query: q)
        })
        rows(p)({ result in
            switch result {
            case .success(let items): box.items = items
            case .failure(let e): box.items = [PickerItem(title: e == .noPHP ? "php not found" : "artisan failed", detail: e.message, symbol: "exclamationmark.triangle") {}]
            }
            QuickPicker.reload()
        })
    }

    // MARK: Commands

    func showArtisanPalette() {
        guard let p = laravelProjectForArtisan() else { artisanNotice("Not a Laravel project", "No artisan file found"); return }
        var commands: [ArtisanCommand] = []
        presentArtisanPicker(placeholder: "Artisan command… (e.g. migrate --seed)", loading: "Loading artisan commands…",
                             rows: { [weak self] p in { done in
                                 ArtisanCatalog.shared.commands(p) { r in
                                     done(r.map { cmds in
                                         commands = cmds
                                         return ArtisanPalette.commandItems(cmds) { c in self?.chooseArtisanCommand(c, in: p) }
                                     })
                                 }
                             } },
                             provider: { [weak self] q in
                                 guard let self, let hit = ArtisanPalette.inlineInvocation(q, in: commands) else { return nil }
                                 return [self.artisanRunItem(hit.0, args: hit.1, in: p)]
                             })
    }

    private func artisanRunItem(_ c: ArtisanCommand, args: String, in p: LaravelProject) -> PickerItem {
        let missing = ArtisanPalette.missingArguments(c, typed: args)
        let detail = missing.isEmpty ? "⏎ run in Terminal" : "missing " + missing.map { "<\($0.name)>" }.joined(separator: " ") + " (artisan will ask)"
        return PickerItem(title: "php artisan \(c.name) \(args)".trimmingCharacters(in: .whitespaces), detail: detail, symbol: "play.fill") { [weak self] in
            self?.runArtisan(c.name, args: args, in: p)
        }
    }

    private func chooseArtisanCommand(_ c: ArtisanCommand, in p: LaravelProject) {
        if c.requiredArguments.isEmpty { runArtisan(c.name, args: "", in: p); return }
        // In-line argument prompt: whatever is typed becomes the argument string.
        QuickPicker.present(over: window, placeholder: "php artisan \(c.name) \(c.argumentHint)", items: [], provider: { [weak self] q in
            guard let self else { return [] }
            return [self.artisanRunItem(c, args: q.trimmingCharacters(in: .whitespaces), in: p)]
        })
    }

    func runArtisan(_ command: String, args: String, in p: LaravelProject) {
        guard let php = Artisan.findPHP() else { artisanNotice("php not found", ArtisanError.noPHP.message); return }
        let here = root?.standardizedFileURL.path
        let cd = p.root.standardizedFileURL.path == here ? nil : p.root.standardizedFileURL.path
        showTerminalPanel(focus: true)
        terminalPanel?.runCommand(Artisan.commandLine(php: php, command: command, args: args, cdTo: cd))
    }

    // MARK: Routes

    func showRouteBrowser() {
        presentArtisanPicker(placeholder: "Route… (method, uri, name or action)", loading: "Loading routes…", rows: { [weak self] p in { done in
            ArtisanCatalog.shared.routes(p) { r in
                done(r.map { routes in
                    RouteBrowser.items(routes) { route in
                        guard let self else { return }
                        if let t = RouteBrowser.target(for: route, in: p) { self.openArtisanLocation(t) }
                        else { self.artisanNotice("No source found for \(route.uri)", route.action) }
                    }
                })
            }
        } })
    }

    // MARK: make:*

    func showMakeDialog() {
        guard let p = laravelProjectForArtisan() else { artisanNotice("Not a Laravel project", "No artisan file found"); return }
        ArtisanCatalog.shared.commands(p) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let cmds):
                let makes = cmds.filter { $0.name.hasPrefix("make:") }
                if makes.isEmpty { self.artisanNotice("No make:* commands", "php artisan list has none"); return }
                MakeDialog.present(over: self.window, commands: makes, project: p) { [weak self] files in
                    guard let self else { return }
                    // Open in reverse so the primary file (first reported) ends up active.
                    for url in files.reversed() where FileManager.default.fileExists(atPath: url.path) { self.open(url) }
                }
            case .failure(let e): self.artisanNotice(e == .noPHP ? "php not found" : "artisan failed", e.message)
            }
        }
    }
}
