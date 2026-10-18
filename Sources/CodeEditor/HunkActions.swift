import AppKit

/// Pure hunk operations for Claude change review. Hunks come from `GitGutter.hunks` (one DiffEngine, no second diff);
/// every operation re-diffs the live text first so a stale hunk can never touch unrelated lines.
enum HunkActions {
    /// Line terminator used when text is inserted into `text` (CRLF when the file is predominantly CRLF).
    static func eol(of text: String) -> String { EditorTab.detectLineEnding(text) == .crlf ? "\r\n" : "\n" }

    /// Lines added / removed going from `baseline` to `current`.
    static func counts(baseline: String, current: String) -> (added: Int, removed: Int) {
        if baseline == current { return (0, 0) }
        let hunks = GitGutter.hunks(old: baseline, new: current)
        return (hunks.reduce(0) { $0 + $1.new.count }, hunks.reduce(0) { $0 + $1.old.count })
    }

    /// `current` with the hunk whose baseline range is `old` restored to the baseline lines (the buffer's own line endings,
    /// no-final-newline preserved). Nil when no such hunk exists any more.
    static func rejecting(old: Range<Int>, baseline: String, current: String) -> String? {
        guard let hunk = GitGutter.hunks(old: baseline, new: current).first(where: { $0.old == old }) else { return nil }
        let ns = current as NSString
        let edit = GitGutter.revertText(hunk: hunk, head: baseline, buffer: ns, eol: eol(of: current))
        return ns.replacingCharacters(in: edit.range, with: edit.text)
    }

    /// The baseline advanced over one hunk (the hunk now counts as reviewed). Nil when no such hunk exists any more.
    static func accepting(old: Range<Int>, baseline: String, current: String) -> String? {
        guard let hunk = GitGutter.hunks(old: baseline, new: current).first(where: { $0.old == old }) else { return nil }
        var lines = DiffEngine.splitLines(baseline)
        let replacement = Array(DiffEngine.splitLines(current)[hunk.new])
        lines.replaceSubrange(hunk.old, with: replacement)
        return lines.joined()
    }

    // MARK: disk

    /// Text and encoding of a file as the editor would read it (nil when unreadable / not text).
    static func readDisk(_ url: URL) -> LoadedFile? {
        if case .success(let loaded) = EditorTab.read(url, options: OpenOptions()) { return loaded }
        return nil
    }

    /// Writes `text` to the real target of `url` keeping the file's encoding and BOM (UTF-8 for a missing file). The previous
    /// content goes to Local History first. Symlink-safe through `FileIO.write`.
    @discardableResult
    static func writeDisk(_ text: String, to url: URL) -> Bool {
        let existing = FileIO.kind(url) == .file ? readDisk(url) : nil
        if existing?.lossy == true { return false }
        let encoding = existing?.encoding ?? .utf8
        guard let body = text.data(using: encoding) else { return false }
        let data = existing?.bom == true ? Data(TextEncodings.bomBytes(for: encoding)) + body : body
        if existing != nil { LocalHistory.snapshotDisk(of: url) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileIO.write(data, to: url)
            return true
        } catch { return false }
    }

    /// Rejects one hunk of a file that is not open in an editor.
    @discardableResult
    static func rejectOnDisk(old: Range<Int>, baseline: String, url: URL) -> Bool {
        guard let current = readDisk(url)?.text, let text = rejecting(old: old, baseline: baseline, current: current) else { return false }
        return writeDisk(text, to: url)
    }
}
