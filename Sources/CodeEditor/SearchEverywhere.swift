import AppKit

/// Double Shift: the tabbed Search Everywhere dialog (All / Classes / Files / Symbols / Actions / Text), like PhpStorm's.
/// Every tab is a provider over an index that already exists (file index, symbol index, vendor index, menu actions, Find engine);
/// nothing here keeps state beyond the open dialog.
enum SearchEverywhere {
    /// Find-in-files results for the Text tab: started after a short pause, capped, shown as they arrive.
    private final class TextSearch {
        let engine: FindEngine
        var query = "", nonProject = false
        var matches: [FindMatch] = []
        var token: CancelToken?
        var pending: DispatchWorkItem?
        var searching = false
        init(engine: FindEngine) { self.engine = engine }

        func results(for q: String, nonProject np: Bool) -> Bool {      // true = results for exactly this query are in `matches`
            if q == query, np == nonProject { return !searching }
            pending?.cancel(); token?.cancel()
            query = q; nonProject = np; matches = []
            guard q.count >= 3 else { searching = false; return true }
            searching = true
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.query == q else { return }
                var o = FindOptions(query: q)
                o.includeIgnored = np
                var t: CancelToken?
                t = self.engine.search(o, batch: { [weak self] found in
                    DispatchQueue.main.async {
                        guard let self, self.query == q, self.matches.count < 100 else { return }
                        self.matches += found.prefix(100 - self.matches.count)
                        if self.matches.count >= 100 { t?.cancel() }
                        QuickPicker.reload()
                    }
                }, done: { [weak self] _ in
                    DispatchQueue.main.async { guard let self, self.query == q else { return }; self.searching = false; QuickPicker.reload() }
                })
                self.token = t
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return false
        }
    }

    static func present(in w: ProjectWindow, tab: Int = 0) {
        guard let root = w.root else { QuickPicker.present(over: w.window, placeholder: "Search everywhere…", items: w.actionItems()); return }
        let actions = w.actionItems()
        let recents = w.recentRelativePaths()
        let symbols = w.symbols
        let vendor = symbols.map { VendorIndex.shared(for: $0.root) }
        var typeItems: [PickerItem] = [], symbolItems: [PickerItem] = []
        var built = false
        func buildSymbolItems() {
            guard !built, let symbols, !symbols.entries.isEmpty else { return }
            let open: (SymbolIndex.Entry) -> Void = { [weak w] e in w?.open(root.appendingPathComponent(e.relativePath), line: e.symbol.line) }
            let all = GoToSymbol.items(entries: symbols.entries, typesOnly: false, open: open)
            typeItems = GoToSymbol.items(entries: symbols.entries, typesOnly: true, open: open)
            let typeKeys = Set(typeItems.map(\.key))
            symbolItems = all.filter { !typeKeys.contains($0.key) }
            built = true
        }
        if let symbols { if symbols.entries.isEmpty { symbols.rebuild { QuickPicker.reload() } } else { symbols.rebuild() } }
        let text = TextSearch(engine: FindEngine(root: root, files: { [weak w] in w?.projectFiles ?? [] }))

        func q(_ s: String) -> [Character] { Array(s.lowercased().filter { !$0.isWhitespace }) }
        func classes(_ s: String, _ np: Bool, limit: Int) -> [PickerItem] {
            buildSymbolItems()
            let k = q(s)
            var out = k.isEmpty ? Array(typeItems.prefix(limit)) : Array(QuickPicker.filter(typeItems, query: k).prefix(limit))
            if np, let vendor, k.count >= 2 {
                vendor.refreshIfNeeded()
                out += GoToSymbol.vendorItems(vendor.searchTypes(s, limit: limit), vendor: vendor) { [weak w] url, line in w?.open(url, line: line) }
            }
            return out
        }
        func files(_ s: String, _ np: Bool, limit: Int) -> [PickerItem] {
            if s.trimmingCharacters(in: .whitespaces).isEmpty { return recents.prefix(limit).map(w.fileItem) }
            var out = (w.index?.search(s, limit: limit) ?? []).map { w.fileItem($0.path) }
            if np, let vendor { out += vendor.searchFiles(s, limit: limit).map { w.fileItem($0.path) } }
            return out
        }
        func syms(_ s: String, _ np: Bool, limit: Int) -> [PickerItem] {
            buildSymbolItems()
            let k = q(s)
            var out = k.isEmpty ? Array(symbolItems.prefix(limit)) : Array(QuickPicker.filter(symbolItems, query: k).prefix(limit))
            if np, let vendor, k.count >= 3 {
                vendor.refreshIfNeeded()
                out += GoToSymbol.vendorItems(vendor.searchMembers(s, limit: limit), vendor: vendor) { [weak w] url, line in w?.open(url, line: line) }
            }
            return out
        }
        func acts(_ s: String, limit: Int) -> [PickerItem] {
            let k = q(s)
            if k.isEmpty { return Array(actions.prefix(limit)) }
            return Array(actions.compactMap { a in Fuzzy.score(k, in: a.key).map { ($0, a) } }.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1))
        }
        func textRows(_ s: String, _ np: Bool) -> [PickerItem] {
            let done = text.results(for: s.trimmingCharacters(in: .whitespaces), nonProject: np)
            if text.matches.isEmpty {
                if s.trimmingCharacters(in: .whitespaces).count < 3 { return [PickerItem(title: "Type at least 3 characters to search the project text", symbol: "text.magnifyingglass") {}] }
                return done ? [] : [PickerItem(title: "Searching…", symbol: "text.magnifyingglass") {}]
            }
            return text.matches.map { m in
                let rel = m.url.path.hasPrefix(root.path + "/") ? String(m.url.path.dropFirst(root.path.count + 1)) : m.url.path
                var item = PickerItem(title: m.lineText.trimmingCharacters(in: .whitespaces), detail: "\(rel):\(m.line)", symbol: "text.alignleft",
                                      key: m.lineText) { [weak w] in w?.open(m.url, line: m.line) }
                item.footer = ((m.url.path as NSString).abbreviatingWithTildeInPath) + ":\(m.line)"
                item.runSplit = { [weak w] in w?.openInRightSplit(m.url, line: m.line) }
                return item
            }
        }

        let tabs = [
            PickerTab(title: "All") { s, np in
                if s.trimmingCharacters(in: .whitespaces).isEmpty { return recents.prefix(12).map(w.fileItem) }
                return classes(s, np, limit: 4) + files(s, np, limit: 8) + syms(s, np, limit: 4) + acts(s, limit: 5)
            },
            PickerTab(title: "Classes") { s, np in classes(s, np, limit: 100) },
            PickerTab(title: "Files") { s, np in files(s, np, limit: 100) },
            PickerTab(title: "Symbols") { s, np in syms(s, np, limit: 100) },
            PickerTab(title: "Actions") { s, _ in acts(s, limit: 100) },
            PickerTab(title: "Text") { s, np in textRows(s, np) },
        ]
        QuickPicker.presentTabbed(over: w.window, tabs: tabs, placeholder: "Search everywhere", selectedTab: tab)
    }
}
