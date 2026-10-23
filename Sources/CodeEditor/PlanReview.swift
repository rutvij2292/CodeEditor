import AppKit
import CryptoKit

/// "Changes since last viewed" for plans: a compact (LZFSE) snapshot per plan file, a unified diff against it, and the
/// window that shows the diff. Snapshots are capped in count and size.
enum PlanReview {
    static var directory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/CodeEditor/plan-snapshots")
    static let maxSnapshots = 60, maxBytes = 300_000, maxTotalBytes = 6_000_000

    private static func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return directory.appendingPathComponent(digest.prefix(10).map { String(format: "%02x", $0) }.joined() + ".snap")
    }

    private static func normalize(_ s: String) -> String { s.contains("\r\n") ? s.replacingOccurrences(of: "\r\n", with: "\n") : s }

    static func baseline(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: file(for: url)),
              let raw = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return String(decoding: raw, as: UTF8.self)
    }

    /// Stores `text` as the last-viewed version of `url` (skipped when over the size cap).
    static func record(_ text: String, for url: URL) {
        let body = normalize(text)
        guard body.utf8.count <= maxBytes, let packed = try? (Data(body.utf8) as NSData).compressed(using: .lzfse) as Data else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? packed.write(to: file(for: url), options: .atomic)
        prune()
    }

    static func forget(_ url: URL) { try? FileManager.default.removeItem(at: file(for: url)) }

    private static func prune() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        var entries = urls.filter { $0.pathExtension == "snap" }.map { u -> (URL, Date, Int) in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (u, v?.contentModificationDate ?? .distantPast, v?.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var total = entries.reduce(0) { $0 + $1.2 }
        while entries.count > maxSnapshots || total > maxTotalBytes, let last = entries.popLast() {
            try? fm.removeItem(at: last.0); total -= last.2
        }
    }

    enum Status { case unseen, unchanged, changed }

    static func status(of url: URL, currentText: String) -> Status {
        guard let old = baseline(for: url) else { return .unseen }
        return old == normalize(currentText) ? .unchanged : .changed
    }

    // MARK: Unified diff

    struct DiffLine: Equatable {
        enum Kind { case header, context, added, removed }
        var kind: Kind
        var text: String
        var line: Int?          // 1-based line in the new text (added / context)
    }

    /// Unified diff old -> new with `context` lines around changes; hunk headers carry the enclosing section heading.
    static func unifiedDiff(old: String, new: String, context: Int = 2) -> [DiffLine] {
        let rows = DiffEngine.rows(old: normalize(old), new: normalize(new))
        guard rows.contains(where: { $0.kind != .equal }) else { return [] }
        let heads = PlanText.headings(normalize(new))
        func section(_ newLine: Int) -> String { PlanText.heading(atOrBefore: newLine - 1, in: heads)?.text ?? "" }
        var keep = [Bool](repeating: false, count: rows.count)
        for (i, r) in rows.enumerated() where r.kind != .equal {
            for j in max(0, i - context)...min(rows.count - 1, i + context) { keep[j] = true }
        }
        func clean(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")) }
        var out: [DiffLine] = []
        var lastNew = 1
        var i = 0
        while i < rows.count {
            guard keep[i] else { i += 1; continue }
            var firstNew = lastNew
            var k = i
            while k < rows.count, keep[k] { if let n = rows[k].rightLine { firstNew = n; break }; k += 1 }
            let sec = section(firstNew)
            out.append(DiffLine(kind: .header, text: "@@ line \(firstNew)" + (sec.isEmpty ? "" : "  ·  \(sec)"), line: firstNew))
            while i < rows.count, keep[i] {
                let r = rows[i]
                switch r.kind {
                case .equal: out.append(DiffLine(kind: .context, text: clean(r.right), line: r.rightLine))
                case .removed: out.append(DiffLine(kind: .removed, text: clean(r.left), line: nil))
                case .added: out.append(DiffLine(kind: .added, text: clean(r.right), line: r.rightLine))
                case .changed:
                    out.append(DiffLine(kind: .removed, text: clean(r.left), line: nil))
                    out.append(DiffLine(kind: .added, text: clean(r.right), line: r.rightLine))
                }
                if let n = r.rightLine { lastNew = n }
                i += 1
            }
        }
        return out
    }

    static func attributed(_ lines: [DiffLine]) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let out = NSMutableAttributedString()
        for l in lines {
            let prefix: String, bg: NSColor?, fg: NSColor
            switch l.kind {
            case .header: (prefix, bg, fg) = ("", Theme.palette.selection.withAlphaComponent(0.5), Theme.foreground)
            case .context: (prefix, bg, fg) = ("  ", nil, Theme.gutter)
            case .added: (prefix, bg, fg) = ("+ ", NSColor.systemGreen.withAlphaComponent(Theme.isDark ? 0.22 : 0.18), Theme.foreground)
            case .removed: (prefix, bg, fg) = ("- ", NSColor.systemRed.withAlphaComponent(Theme.isDark ? 0.22 : 0.16), Theme.foreground)
            }
            var attrs: [NSAttributedString.Key: Any] = [.font: l.kind == .header ? NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold) : mono, .foregroundColor: fg]
            if let bg { attrs[.backgroundColor] = bg }
            out.append(NSAttributedString(string: prefix + l.text + "\n", attributes: attrs))
        }
        return out
    }
}

/// A plain window with the unified diff (read-only, selectable).
final class PlanDiffWindow: NSObject {
    private static var open: [PlanDiffWindow] = []
    let window: NSWindow
    let textView = NSTextView()

    static var latest: PlanDiffWindow? { open.last }

    @discardableResult
    static func present(title: String, lines: [PlanReview.DiffLine]) -> PlanDiffWindow {
        let w = PlanDiffWindow(title: title, lines: lines)
        open.append(w)
        if !AppEnv.headless { w.window.center(); w.window.makeKeyAndOrderFront(nil) }
        return w
    }

    init(title: String, lines: [PlanReview.DiffLine]) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        DialogMemory.remember(window, as: "PlanReviewDiff")
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.backgroundColor = Theme.background
        textView.textStorage?.setAttributedString(lines.isEmpty
            ? NSAttributedString(string: "No changes since this plan was last viewed.", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.gutter])
            : PlanReview.attributed(lines))
        scroll.documentView = textView
        window.contentView!.addSubview(scroll)
        super.init()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            PlanDiffWindow.open.removeAll { $0 === self }
        }
    }
}
