import AppKit
import SwiftTreeSitter

/// Navigate > Changed Symbols: one row per changed method / function / component across the files git (or the pending Claude review)
/// says changed, with how many lines were added and removed. Enter jumps to the first changed line. Built on demand: status, HEAD
/// text and outlines are read off the main thread and dropped as soon as the popup is up (nothing stays resident).
enum ChangedSymbols {
    static let maxFiles = 60
    static let maxFileBytes = 512 * 1024

    struct Row {
        var path: String
        var rel: String
        var name: String
        var kind: BreadcrumbSymbolKind?
        var line: Int          // first changed line (1-based, in the current text)
        var added = 0
        var removed = 0
        var isNewFile = false
    }

    struct FileJob {
        var path: String           // absolute
        var rel: String            // relative to the repo
        var key: String?
        var buffer: String?        // open editor text
        var baseline: String?      // pending Claude review baseline; nil = git HEAD
        var isNew: Bool
    }

    /// Hunks of `new` against `old` grouped by the innermost construct containing them. Pure (tests call it).
    static func rows(path: String, rel: String, old: String, new: String, outline: BreadcrumbOutline?, isNew: Bool = false) -> [Row] {
        let hunks = GitGutter.hunks(old: old, new: new)
        guard !hunks.isEmpty else { return [] }
        let ns = new as NSString
        let starts = NPLineStarts(ns)
        var order: [String] = []
        var byKey: [String: Row] = [:]
        for h in hunks {
            let line = max(1, min(h.new.lowerBound + 1, starts.starts.count))
            let offset = min(starts.starts[line - 1], ns.length)
            var name = isNew ? "(new file)" : "(file level)"
            var kind: BreadcrumbSymbolKind?
            var key = "-"
            if let outline, !isNew {
                let chain = outline.chain(at: offset)
                let pick = chain.last(where: { outline.nodes.indices.contains($0) && outline.nodes[$0].kind != .tag })
                    ?? chain.first(where: { outline.nodes.indices.contains($0) })
                if let i = pick { name = outline.nodes[i].name; kind = outline.nodes[i].kind; key = String(i) }
            }
            var r = byKey[key] ?? Row(path: path, rel: rel, name: name, kind: kind, line: line, isNewFile: isNew)
            r.added += h.new.count
            r.removed += h.old.count
            r.line = min(r.line, line)
            if byKey[key] == nil { order.append(key) }
            byKey[key] = r
        }
        return order.compactMap { byKey[$0] }
    }

    static func items(_ rows: [Row], open: @escaping (String, Int) -> Void) -> [PickerItem] {
        rows.map { r in
            var it = PickerItem(title: r.name, detail: r.rel, symbol: "circle", key: r.name + " " + r.rel) { open(r.path, r.line) }
            if let k = r.kind, let ck = CodeSymbol.Kind(rawValue: k.rawValue) { it.symbol = ck.pickerIcon; it.tint = ck.pickerTint; it.strong = ck.rawValue == "class" }
            else if r.kind == .component { it.symbol = CodeSymbol.Kind.component.pickerIcon; it.tint = CodeSymbol.Kind.component.pickerTint }
            else { it.symbol = r.isNewFile ? "plus.square.fill" : "doc.text.fill"; it.tint = r.isNewFile ? .systemGreen : .systemGray }
            var bits: [String] = []
            if r.added > 0 { bits.append("+\(r.added)") }
            if r.removed > 0 { bits.append("−\(r.removed)") }
            it.marker = bits.joined(separator: " ")
            it.markerTint = r.removed == 0 ? .systemGreen : r.added == 0 ? .systemRed : .systemOrange
            return it
        }
    }
}

extension ProjectWindow {
    func showChangedSymbols() {
        guard let repo = gitRoot else { statusBar.flash("Not a git project"); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let changes = ((try? GitRepo(root: repo).statusAndBranch())?.changes ?? []).filter { !$0.isConflict }
            DispatchQueue.main.async { self?.collectChangedSymbols(repo: repo, changes: changes) }
        }
    }

    /// Main thread: buffers, review baselines and grammars (main-thread only) are gathered here, the heavy part runs in the background.
    private func collectChangedSymbols(repo: URL, changes: [GitChange]) {
        var jobs: [ChangedSymbols.FileJob] = []
        var languages: [String: [String: Language]] = [:]
        for c in changes.prefix(ChangedSymbols.maxFiles * 2) {
            let abs = repo.appendingPathComponent(c.path).standardizedFileURL.path
            let name = (c.path as NSString).lastPathComponent
            let key = Languages.key(forFileName: name)
            if let key, BreadcrumbOutlineBuilder.supports(key: key), languages[key] == nil { languages[key] = BreadcrumbOutlineBuilder.languages(for: key) }
            let open = editors.values.first { $0.url.standardizedFileURL.path == abs }
            jobs.append(ChangedSymbols.FileJob(path: abs, rel: c.path, key: key, buffer: open?.textView.string,
                                               baseline: changeReview?.pendingEntry(abs)?.baseline, isNew: c.isUntracked || c.index == "A"))
            if jobs.count >= ChangedSymbols.maxFiles { break }
        }
        let langs = languages
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let git = GitRepo(root: repo)
            var rows: [ChangedSymbols.Row] = []
            for j in jobs {
                guard let new = j.buffer ?? (try? String(contentsOfFile: j.path, encoding: .utf8)), new.utf8.count <= ChangedSymbols.maxFileBytes else { continue }
                let old = j.isNew ? "" : (j.baseline ?? ((try? git.headContent(of: j.rel)) ?? nil) ?? "")
                guard old.utf8.count <= ChangedSymbols.maxFileBytes else { continue }
                var outline: BreadcrumbOutline?
                if let key = j.key, BreadcrumbOutlineBuilder.supports(key: key), let l = langs[key] { outline = BreadcrumbOutlineBuilder.build(text: new, key: key, languages: l) }
                rows += ChangedSymbols.rows(path: j.path, rel: j.rel, old: old, new: new, outline: outline, isNew: j.isNew)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard !rows.isEmpty else { self.statusBar.flash("No changed symbols"); return }
                let items = ChangedSymbols.items(rows) { [weak self] path, line in self?.open(URL(fileURLWithPath: path), line: line) }
                QuickPicker.present(over: self.window, placeholder: "Changed symbols — \(rows.count) in \(Set(rows.map(\.path)).count) files", items: items)
            }
        }
    }
}
