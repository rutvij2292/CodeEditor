import AppKit

/// PhpStorm-style "speed search" for table and outline views: type while the list has focus and a small field appears over it,
/// jumping to the best fuzzy match among the rows that are currently loaded (expanded). Up / Down step through matches only,
/// Return opens, Escape closes the field and leaves the list focused. Nothing exists while idle: the overlay and the match list
/// are created on the first keystroke and dropped when the search ends (no timers, no polling).
final class SpeedSearch: NSObject, NSTextFieldDelegate {
    /// Rows scored per keystroke at most; larger lists fall back to the first rows only.
    private static let maxRows = 20_000

    private weak var table: NSTableView?
    private var rowText: (Int) -> String? = { _ in nil }
    /// Return pressed with a match selected (the owner opens the row).
    var onReturn: (() -> Void)?
    /// Return pressed while nothing matches: the owner may widen the search (the tree hands the query to Go to File).
    var onSearchEverywhere: ((String) -> Void)?

    private var container: NSView?
    private var field: NSTextField?
    private var hint: NSTextField?
    private(set) var isActive = false
    private var queryChars: [Character] = []
    private(set) var matches: [Int] = []

    /// Wire to a list: `rowText` gives the searchable text of a row (nil = not searchable, e.g. a group header).
    func attach(to table: NSTableView, rowText: @escaping (Int) -> String?) {
        self.table = table
        self.rowText = rowText
    }

    var query: String { field?.stringValue ?? "" }

    /// The character a key press would start a search with, or nil for navigation / shortcut / whitespace keys.
    static func seed(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock])
        guard flags.isEmpty, let chars = event.characters, chars.count == 1, let scalar = chars.unicodeScalars.first else { return nil }
        guard scalar.value >= 0x21, scalar.value < 0xF700, scalar.value != 0x7F else { return nil }
        return chars
    }

    /// Call from the list's `keyDown`; returns true when the event started a search.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isActive, let seed = Self.seed(from: event) else { return false }
        begin(seed: seed)
        return true
    }

    func begin(seed: String) {
        guard let table, let scroll = table.enclosingScrollView, let window = table.window else { return }
        isActive = true
        let box = NSView(frame: .zero)
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 0.5
        box.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        box.layer?.borderColor = NSColor.separatorColor.cgColor

        let f = NSTextField(string: seed)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 13)
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.delegate = self
        let h = NSTextField(labelWithString: "")
        h.font = .systemFont(ofSize: 11)
        h.textColor = .secondaryLabelColor
        h.alignment = .right
        h.lineBreakMode = .byTruncatingHead

        let height: CGFloat = 24
        box.frame = NSRect(x: 8, y: scroll.bounds.height - height - 6, width: max(80, scroll.bounds.width - 16), height: height)
        box.autoresizingMask = [.width, .minYMargin]
        f.frame = NSRect(x: 8, y: 3, width: box.bounds.width - 16, height: 18)
        f.autoresizingMask = [.width]
        h.frame = NSRect(x: box.bounds.width * 0.45, y: 4, width: box.bounds.width * 0.55 - 8, height: 16)
        h.autoresizingMask = [.minXMargin]
        box.addSubview(f)
        box.addSubview(h)
        scroll.addSubview(box)
        container = box; field = f; hint = h

        window.makeFirstResponder(f)
        (f.currentEditor() as? NSTextView)?.selectedRange = NSRange(location: seed.utf16.count, length: 0)
        update()
    }

    /// Closes the field; `refocus` hands first responder back to the list (false when focus already went elsewhere).
    func end(refocus: Bool = true) {
        guard isActive else { return }
        isActive = false
        container?.removeFromSuperview()
        container = nil; field = nil; hint = nil
        queryChars = []; matches = []
        if let table {
            reloadVisible(table)
            if refocus { table.window?.makeFirstResponder(table) }
        }
    }

    /// Bold accent letters for the characters of `text` the active query matched (empty when no search is open).
    func matchedIndices(in text: String) -> Set<Int> {
        guard isActive, !queryChars.isEmpty else { return [] }
        return QuickPicker.matchIndices(queryChars, in: text)
    }

    // MARK: matching

    private func update() {
        guard let table, let field else { return }
        let q = field.stringValue
        queryChars = Array(q.lowercased().filter { !$0.isWhitespace })
        matches = []
        var best: (row: Int, score: Int)?
        for row in 0..<min(table.numberOfRows, Self.maxRows) {
            guard let text = rowText(row), let s = Fuzzy.score(query: q, in: text) else { continue }
            matches.append(row)
            if best == nil || s > best!.score { best = (row, s) }
        }
        if let best {
            table.selectRowIndexes(IndexSet(integer: best.row), byExtendingSelection: false)
            table.scrollRowToVisible(best.row)
            hint?.stringValue = matches.count > 1 ? "\(matches.count) matches" : ""
            field.textColor = .labelColor
        } else {
            hint?.stringValue = onSearchEverywhere != nil && q.count >= 2 ? "No match · ↩ searches all files" : "No match"
            field.textColor = .systemRed
        }
        reloadVisible(table)
    }

    private func reloadVisible(_ table: NSTableView) {
        let visible = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                         columnIndexes: IndexSet(integer: 0))
    }

    /// Moves the selection to the next / previous match (wrapping).
    private func step(_ delta: Int) {
        guard let table, !matches.isEmpty else { return }
        let current = table.selectedRow
        let next: Int
        if delta > 0 { next = matches.first { $0 > current } ?? matches[0] }
        else { next = matches.last { $0 < current } ?? matches[matches.count - 1] }
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard isActive else { return }
        if (field?.stringValue ?? "").isEmpty { end(); return }
        update()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Clicking elsewhere ends the search without stealing focus back.
        if isActive { end(refocus: false) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveDownAndModifySelection(_:)): step(1); return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveUpAndModifySelection(_:)): step(-1); return true
        case #selector(NSResponder.insertNewline(_:)):
            let q = query
            if matches.isEmpty {
                end()
                if q.count >= 2 { onSearchEverywhere?(q) }
            } else {
                end()
                onReturn?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)): end(); return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): return true
        default: return false
        }
    }

    // MARK: test hooks (headless harness)

    func testType(_ s: String) {
        guard let field else { return }
        field.stringValue = s
        update()
    }
    func testBegin(_ s: String) { begin(seed: s) }
    func testStep(_ d: Int) { step(d) }
}

/// Plain table whose typing starts a speed search (TODO, Bookmarks, Tests, Claude Changes).
final class SpeedTableView: NSTableView {
    var speedSearch: SpeedSearch?
    /// Return / Enter on the selected row (lists that have an "open" action).
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), let onReturn { onReturn(); return }
        if speedSearch?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }
}
