import AppKit
import SwiftTreeSitter

/// Turns what the user just accepted in Claude Changes into ledger rows.
enum LedgerRecorder {
    static func sessionID(_ s: ChangeReviewStore.Session) -> String { "\(s.id)-\(Int(s.started.timeIntervalSince1970))" }

    /// File row with the changed symbols; without rows (no baseline, too large, unsupported language) only the file-level counts.
    static func file(_ f: ChangeReviewStore.AcceptedFile, rows: [ChangedSymbols.Row]) -> LedgerFile {
        LedgerFile(rel: f.rel, added: f.added, removed: f.removed,
                   symbols: rows.map { LedgerSymbol(name: $0.name, kind: $0.kind?.rawValue, line: $0.line, added: $0.added, removed: $0.removed, isNewFile: $0.isNewFile) })
    }
}

extension ProjectWindow {
    /// Records accepted files in the ledger. Open buffers and grammars are gathered here (main thread); the symbol computation runs on a
    /// background queue and the ledger is updated on `deliverOn` (main by default), then `done` runs.
    func recordLedger(session: ChangeReviewStore.Session, files: [ChangeReviewStore.AcceptedFile], note: String,
                      deliverOn: DispatchQueue = .main, done: (() -> Void)? = nil) {
        guard let ledger = changeLedger else { done?(); return }
        let id = LedgerRecorder.sessionID(session), title = session.title, started = session.started
        var languages: [String: [String: Language]] = [:]
        var jobs: [(file: ChangeReviewStore.AcceptedFile, buffer: String?, key: String?)] = []
        for f in files {
            let key = Languages.key(forFileName: (f.rel as NSString).lastPathComponent)
            if let key, BreadcrumbOutlineBuilder.supports(key: key), languages[key] == nil { languages[key] = BreadcrumbOutlineBuilder.languages(for: key) }
            let abs = URL(fileURLWithPath: f.path).standardizedFileURL.path
            let open = editors.values.first { $0.url.standardizedFileURL.path == abs }
            jobs.append((f, open?.textView.string, key))
        }
        let langs = languages
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [LedgerFile] = []
            for j in jobs {
                var rows: [ChangedSymbols.Row] = []
                if let base = j.file.baseline, base.utf8.count <= ChangedSymbols.maxFileBytes,
                   let new = j.buffer ?? (try? String(contentsOfFile: j.file.path, encoding: .utf8)), new.utf8.count <= ChangedSymbols.maxFileBytes {
                    var outline: BreadcrumbOutline?
                    if let key = j.key, BreadcrumbOutlineBuilder.supports(key: key), let l = langs[key] { outline = BreadcrumbOutlineBuilder.build(text: new, key: key, languages: l) }
                    rows = ChangedSymbols.rows(path: j.file.path, rel: j.file.rel, old: base, new: new, outline: outline)
                }
                out.append(LedgerRecorder.file(j.file, rows: rows))
            }
            deliverOn.async {
                ledger.record(id: id, title: title, started: started, files: out, note: note, now: Date())
                done?()
            }
        }
    }
}
