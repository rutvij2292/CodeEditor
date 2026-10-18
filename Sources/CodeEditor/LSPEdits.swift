import AppKit

/// One LSP TextEdit (range kept raw until the target text is known).
struct LSPTextEdit {
    let range: [String: Any]
    let newText: String
}

struct LSPFileEdit {
    let url: URL
    var edits: [LSPTextEdit]
    let version: Int?
}

struct LSPApplyResult {
    var applied = false
    var failureReason: String?
    var files = 0
    var edits = 0
    /// Files that were written to disk (not open in a tab); callers may forward them as file events.
    var writtenURLs: [URL] = []
}

/// WorkspaceEdit parsing and application shared by rename, formatting and `workspace/applyEdit`.
/// Open tabs are edited through their text view (one undo group per file); closed files are rewritten atomically
/// after checking they did not change since they were read.
enum LSPEdits {
    // MARK: Parsing

    static func parseTextEdits(_ raw: Any?) -> [LSPTextEdit] {
        ((raw as? [[String: Any]]) ?? []).compactMap { d in
            guard let r = d["range"] as? [String: Any] else { return nil }
            return LSPTextEdit(range: r, newText: (d["newText"] as? String) ?? "")
        }
    }

    /// Returns the per-file edits, or an error string for unsupported content (create/rename/delete operations).
    static func parse(_ edit: Any?) -> (files: [LSPFileEdit], error: String?) {
        guard let e = edit as? [String: Any] else { return ([], "empty workspace edit") }
        var out: [LSPFileEdit] = []
        func add(_ uri: String, _ edits: [LSPTextEdit], _ version: Int?) {
            guard let url = URL(string: uri), url.isFileURL else { return }
            out.append(LSPFileEdit(url: url.standardizedFileURL, edits: edits, version: version))
        }
        if let dc = e["documentChanges"] as? [[String: Any]] {
            for item in dc {
                if item["kind"] is String { return ([], "file operations (create/rename/delete) are not supported") }
                guard let td = item["textDocument"] as? [String: Any], let uri = td["uri"] as? String else { continue }
                add(uri, parseTextEdits(item["edits"]), (td["version"] as? NSNumber)?.intValue)
            }
        } else if let changes = e["changes"] as? [String: Any] {
            for (uri, edits) in changes.sorted(by: { $0.key < $1.key }) { add(uri, parseTextEdits(edits), nil) }
        }
        // Merge duplicates of one file.
        var merged: [LSPFileEdit] = []
        for f in out {
            if let i = merged.firstIndex(where: { $0.url.path == f.url.path }) { merged[i].edits += f.edits }
            else { merged.append(f) }
        }
        return (merged, nil)
    }

    // MARK: Applying

    private struct Plan {
        let url: URL
        let ranges: [(range: NSRange, text: String)]      // sorted descending by location
        let tab: EditorTab?
        let newContent: String?                            // closed files only
        let diskSnapshot: (size: Int, date: Date?)?
    }

    private static func fileState(_ url: URL) -> (size: Int, date: Date?)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return ((a[.size] as? NSNumber)?.intValue ?? -1, a[.modificationDate] as? Date)
    }

    /// Applies the edits. All validation happens before anything is modified; failure leaves everything untouched.
    @discardableResult
    static func apply(_ files: [LSPFileEdit], label: String? = nil) -> LSPApplyResult {
        var result = LSPApplyResult()
        var plans: [Plan] = []
        for f in files where !f.edits.isEmpty {
            let session = LanguageServerManager.shared.session(forURL: f.url)
            let tab = session?.tab
            let text: String
            var snapshot: (size: Int, date: Date?)?
            if let session, let tab {
                session.flushChanges()
                if let v = f.version, v != session.version {
                    result.failureReason = "\(f.url.lastPathComponent) changed since the server computed the edit"
                    return result
                }
                text = tab.textView.string
            } else {
                guard let data = try? Data(contentsOf: f.url), let s = String(data: data, encoding: .utf8) else {
                    result.failureReason = "cannot read \(f.url.lastPathComponent)"
                    return result
                }
                text = s
                snapshot = fileState(f.url)
            }
            let ns = text as NSString
            let table = LSPLineTable(ns)
            var ranges: [(range: NSRange, text: String)] = []
            for e in f.edits {
                guard let r = table.range(fromLSP: e.range) else {
                    result.failureReason = "malformed edit range in \(f.url.lastPathComponent)"
                    return result
                }
                ranges.append((r, e.newText))
            }
            ranges.sort { ($0.range.location, $0.range.length) > ($1.range.location, $1.range.length) }
            for i in 1..<max(1, ranges.count) where NSMaxRange(ranges[i].range) > ranges[i - 1].range.location {
                result.failureReason = "overlapping edits in \(f.url.lastPathComponent)"
                return result
            }
            var newContent: String?
            if tab == nil {
                let m = NSMutableString(string: ns)
                for r in ranges { m.replaceCharacters(in: r.range, with: r.text) }
                newContent = m as String
            }
            plans.append(Plan(url: f.url, ranges: ranges, tab: tab, newContent: newContent, diskSnapshot: snapshot))
        }
        guard !plans.isEmpty else { result.applied = true; return result }

        // Re-verify closed files immediately before touching anything.
        for p in plans where p.tab == nil {
            let now = fileState(p.url)
            if now?.size != p.diskSnapshot?.size || now?.date != p.diskSnapshot?.date {
                result.failureReason = "\(p.url.lastPathComponent) changed on disk while the edit was prepared"
                return result
            }
        }
        // Buffers first (undoable), then disk.
        for p in plans {
            if let tab = p.tab { applyToBuffer(tab.textView, p.ranges, actionName: label ?? "Edit") }
        }
        for p in plans where p.tab == nil {
            do {
                try p.newContent!.write(to: p.url, atomically: true, encoding: .utf8)
                result.writtenURLs.append(p.url)
            } catch {
                result.failureReason = "cannot write \(p.url.lastPathComponent): \(error.localizedDescription)"
                if !result.writtenURLs.isEmpty { LanguageServers.fileEvents(result.writtenURLs.map { ($0, 2) }) }
                return result
            }
        }
        if !result.writtenURLs.isEmpty { LanguageServers.fileEvents(result.writtenURLs.map { ($0, 2) }) }
        result.applied = true
        result.files = plans.count
        result.edits = plans.reduce(0) { $0 + $1.ranges.count }
        return result
    }

    /// Edits (descending) go through shouldChangeText/replaceCharacters/didChangeText like CodeTextView does, wrapped in
    /// one undo group.
    static func applyToBuffer(_ tv: CodeTextView, _ ranges: [(range: NSRange, text: String)], actionName: String) {
        guard !ranges.isEmpty else { return }
        tv.breakUndoCoalescing()
        tv.undoManager?.beginUndoGrouping()
        for r in ranges {
            guard tv.shouldChangeText(in: r.range, replacementString: r.text) else { continue }
            tv.textStorage?.replaceCharacters(in: r.range, with: NSAttributedString(string: r.text, attributes: tv.typingAttributes))
            tv.didChangeText()
        }
        tv.undoManager?.setActionName(actionName)
        tv.undoManager?.endUndoGrouping()
    }

    // MARK: workspace/applyEdit (server -> client request, main thread)

    static func handleApplyEdit(_ params: Any?) -> [String: Any] {
        let p = params as? [String: Any]
        let label = p?["label"] as? String
        let parsed = parse(p?["edit"])
        if let err = parsed.error { return ["applied": false, "failureReason": err] }
        let r = apply(parsed.files, label: label)
        LSPLog.log("applyEdit \(label ?? "") -> \(r.applied) \(r.failureReason ?? "")")
        var out: [String: Any] = ["applied": r.applied]
        if let f = r.failureReason { out["failureReason"] = f }
        return out
    }

    // MARK: Minimal edits (formatting)

    /// Shrinks each edit to the changed region, and splits large replacements into line-level hunks.
    static func minimized(_ edits: [(range: NSRange, text: String)], in text: NSString) -> [(range: NSRange, text: String)] {
        var out: [(range: NSRange, text: String)] = []
        for e in edits {
            let old = text.substring(with: e.range) as NSString
            let new = e.text as NSString
            var p = 0
            let maxP = min(old.length, new.length)
            while p < maxP, old.character(at: p) == new.character(at: p) { p += 1 }
            var s = 0
            while s < maxP - p, old.character(at: old.length - 1 - s) == new.character(at: new.length - 1 - s) { s += 1 }
            // never split a surrogate pair
            func isHigh(_ c: unichar) -> Bool { (0xD800...0xDBFF).contains(c) }
            if p > 0, p < old.length, isHigh(old.character(at: p - 1)) { p -= 1 }
            if s > 0, old.length - s - 1 >= 0, isHigh(old.character(at: old.length - s - 1)) { s -= 1 }
            if p == old.length && p == new.length { continue }
            let oldMid = old.substring(with: NSRange(location: p, length: old.length - p - s)) as NSString
            let newMid = new.substring(with: NSRange(location: p, length: new.length - p - s)) as NSString
            let base = e.range.location + p
            if oldMid.length > 400 || newMid.length > 400 {
                let hunks = lineHunks(oldMid, newMid)
                if let hunks, hunks.count > 1 {
                    for h in hunks { out.append((NSRange(location: base + h.range.location, length: h.range.length), h.text)) }
                    continue
                }
            }
            out.append((NSRange(location: base, length: oldMid.length), newMid as String))
        }
        return out
    }

    private static func lines(_ s: NSString) -> [String] {
        var out: [String] = []
        var pos = 0
        while pos < s.length {
            let r = s.lineRange(for: NSRange(location: pos, length: 0))
            out.append(s.substring(with: r))
            pos = NSMaxRange(r)
        }
        return out
    }

    private static func lineHunks(_ old: NSString, _ new: NSString) -> [(range: NSRange, text: String)]? {
        let a = lines(old), b = lines(new)
        guard a.count <= 6000, b.count <= 6000 else { return nil }
        let diff = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for c in diff {
            switch c {
            case .remove(let o, _, _): removed.insert(o)
            case .insert(let o, _, _): inserted.insert(o)
            }
        }
        var offsets = [0]
        for l in a { offsets.append(offsets.last! + (l as NSString).length) }
        var hunks: [(range: NSRange, text: String)] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if (i < a.count && removed.contains(i)) || (j < b.count && inserted.contains(j)) {
                let i0 = i, j0 = j
                while i < a.count, removed.contains(i) { i += 1 }
                while j < b.count, inserted.contains(j) { j += 1 }
                hunks.append((NSRange(location: offsets[i0], length: offsets[i] - offsets[i0]), b[j0..<j].joined()))
            } else { i += 1; j += 1 }
        }
        return hunks
    }
}
