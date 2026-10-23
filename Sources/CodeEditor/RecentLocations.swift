import AppKit
import ObjectiveC

/// Newest-first list of places the caret was left (PhpStorm "Recent Locations"). Pure value type: capped, deduped per file + line.
struct LocationLog {
    struct Entry: Equatable {
        var url: URL
        var line: Int
        var snippet: String
        var changed: Bool
    }

    static let cap = 50
    private(set) var entries: [Entry] = []

    mutating func add(url: URL, line: Int, snippet: String, changed: Bool) {
        var changed = changed
        if let i = entries.firstIndex(where: { $0.url == url && $0.line == line }) {
            changed = changed || entries[i].changed
            entries.remove(at: i)
        }
        entries.insert(Entry(url: url, line: line, snippet: snippet, changed: changed), at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
    }

    func visible(changedOnly: Bool) -> [Entry] { changedOnly ? entries.filter(\.changed) : entries }

    /// 1-based line and trimmed text of the line holding `offset`.
    static func lineInfo(in text: NSString, offset: Int) -> (line: Int, snippet: String) {
        let loc = max(0, min(offset, text.length))
        var line = 1, i = 0
        while i < loc {
            let r = text.range(of: "\n", range: NSRange(location: i, length: loc - i))
            if r.location == NSNotFound { break }
            line += 1; i = r.upperBound
        }
        let lr = text.lineRange(for: NSRange(location: loc, length: 0))
        var s = text.substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > 200 { s = String(s.prefix(200)) }
        return (line, s)
    }
}

/// Watches one project window's editors. Selection / edit notifications only: no timers, O(1) per keystroke; line numbers are
/// computed only when the caret jumps away or the tab changes.
final class LocationTracker {
    private(set) var log = LocationLog()
    var changedOnly = false
    static let jumpDistance = 300

    private weak var project: ProjectWindow?
    private weak var lastTV: CodeTextView?
    private var lastOffset = 0
    private weak var editTV: CodeTextView?
    private var editOffset = 0
    private var observers: [NSObjectProtocol] = []

    init(project: ProjectWindow) {
        self.project = project
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSTextView.didChangeSelectionNotification, object: nil, queue: .main) { [weak self] n in
            if let tv = n.object as? CodeTextView { self?.selectionChanged(tv) }
        })
        observers.append(nc.addObserver(forName: NSText.didChangeNotification, object: nil, queue: .main) { [weak self] n in
            if let tv = n.object as? CodeTextView { self?.edited(tv) }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func owns(_ tv: CodeTextView) -> Bool { tv.window != nil && tv.window === project?.window }

    func selectionChanged(_ tv: CodeTextView) {
        guard owns(tv) else { return }
        let off = tv.selectedRange().location
        if tv !== lastTV {
            flushEdit()
            if let old = lastTV { record(old, lastOffset, changed: false) }
            lastTV = tv; lastOffset = off
            return
        }
        if abs(off - lastOffset) > Self.jumpDistance {
            flushEdit()
            record(tv, lastOffset, changed: false)
        }
        lastOffset = off
    }

    func edited(_ tv: CodeTextView) {
        guard owns(tv) else { return }
        if let e = editTV, e !== tv { flushEdit() }
        editTV = tv
        editOffset = tv.selectedRange().location
    }

    /// Turns the pending edit position into a "changed" entry.
    func flushEdit() {
        guard let tv = editTV else { return }
        editTV = nil
        record(tv, editOffset, changed: true)
    }

    private func record(_ tv: CodeTextView, _ offset: Int, changed: Bool) {
        guard let project, let url = project.editors.values.first(where: { $0.textView === tv })?.url else { return }
        let info = LocationLog.lineInfo(in: tv.string as NSString, offset: offset)
        log.add(url: url.standardizedFileURL, line: info.line, snippet: info.snippet, changed: changed)
    }
}

private var trackerKey: UInt8 = 0

extension ProjectWindow {
    /// Starts recording locations for this window (idempotent).
    func installRecentLocations() { _ = locationTracker }

    var locationTracker: LocationTracker {
        if let t = objc_getAssociatedObject(self, &trackerKey) as? LocationTracker { return t }
        let t = LocationTracker(project: self)
        objc_setAssociatedObject(self, &trackerKey, t, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return t
    }

    /// Shift-Cmd-E; pressed again while the popup is open it cycles "changed locations only".
    func showRecentLocations() {
        let t = locationTracker
        t.flushEdit()
        if QuickPicker.isOpen, RecentLocationsSupport.shared.shownFor === self { t.changedOnly.toggle() } else { t.changedOnly = false }
        RecentLocationsSupport.shared.shownFor = self
        let rows = t.log.visible(changedOnly: t.changedOnly)
        let items = rows.map { e -> PickerItem in
            let rel = FileOperations.relativePath(e.url, to: root)
            return PickerItem(title: e.snippet.isEmpty ? "(empty line)" : e.snippet, detail: "\(rel):\(e.line)",
                              symbol: e.changed ? "pencil" : FileIcon.symbol(forExtension: e.url.pathExtension),
                              key: e.snippet + " " + rel) { [weak self] in
                self?.open(e.url, line: e.line)
                self?.current?.textView.goToLine(e.line)
            }
        }
        let shown = items.isEmpty
            ? [PickerItem(title: t.changedOnly ? "No changed locations yet" : "No recent locations yet",
                          detail: "Shift-Cmd-E cycles changed only", symbol: "clock") {}]
            : items
        QuickPicker.present(over: window, placeholder: t.changedOnly ? "Recently changed locations…" : "Recent locations…", items: shown)
    }
}

/// Menu target for Navigate > Recent Locations.
final class RecentLocationsSupport: NSObject {
    static let shared = RecentLocationsSupport()
    weak var shownFor: ProjectWindow?
    @objc func show(_ sender: Any?) { (NSApp.delegate as? AppDelegate)?.active?.showRecentLocations() }
}

extension LocationTracker {
    /// CE_PICKER=locations: sample rows from the first lines of `url` (never shown outside snapshots).
    func seedForSnapshot(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\n")
        for (i, l) in lines.enumerated().prefix(40) where i % 7 == 3 && !l.trimmingCharacters(in: .whitespaces).isEmpty {
            seed(url: url, line: i + 1, snippet: l.trimmingCharacters(in: .whitespaces), changed: i % 14 == 3)
        }
    }
    fileprivate func seed(url: URL, line: Int, snippet: String, changed: Bool) { log.add(url: url, line: line, snippet: snippet, changed: changed) }
}
