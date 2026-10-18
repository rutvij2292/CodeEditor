import AppKit

/// Folding commands and the persistence surface of CodeTextView. All `@objc` actions travel the responder chain
/// (first responder = the focused editor), so menu items can use a nil target.
extension CodeTextView {
    /// Selectors the menu validation treats as fold commands.
    static let foldActions: [Selector] = [
        #selector(toggleFold(_:)), #selector(foldCurrent(_:)), #selector(unfoldCurrent(_:)), #selector(foldAll(_:)),
        #selector(unfoldAll(_:)), #selector(foldToLevel1(_:)), #selector(foldToLevel2(_:)), #selector(foldToLevel3(_:)),
        #selector(foldComments(_:)), #selector(foldImports(_:)), #selector(unfoldSelection(_:)),
    ]

    // MARK: Persistence

    /// Collapsed regions as 1-based half-open line ranges (`startLine..<endLine + 1`). Persist per file; assigning restores
    /// them (matched against the detected regions by their lines, applied after the first computation if it has not run yet).
    /// Assign even an empty array when restoring a session so "fold imports on open" does not fire for it.
    var foldedLineRanges: [Range<Int>] {
        get { folds.foldedLineRanges }
        set { folds.restore(lineRanges: newValue) }
    }

    // MARK: Commands

    /// Folds or unfolds the innermost region containing the caret.
    @objc func toggleFold(_ sender: Any?) {
        guard Prefs.foldingEnabled else { return }
        if let c = rowCollapsedRegion() { folds.expand(c); return }
        if let r = innermostRegion(expanded: true) { folds.collapse(r) }
    }

    /// Collapses the innermost expanded region around the caret (repeat to fold the parent).
    @objc func foldCurrent(_ sender: Any?) {
        guard Prefs.foldingEnabled, let r = innermostRegion(expanded: true) else { return }
        folds.collapse(r, recursive: NSEvent.modifierFlags.contains(.option))
    }

    /// Expands the collapsed region on the caret's row.
    @objc func unfoldCurrent(_ sender: Any?) {
        guard Prefs.foldingEnabled, let c = rowCollapsedRegion() else { return }
        folds.expand(c, recursive: NSEvent.modifierFlags.contains(.option))
    }

    @objc func foldAll(_ sender: Any?) {
        guard Prefs.foldingEnabled else { return }
        folds.setCollapsed(folds.regions)
    }

    @objc func unfoldAll(_ sender: Any?) { folds.unfoldAll() }

    @objc func foldToLevel1(_ sender: Any?) { fold(toLevel: 1) }
    @objc func foldToLevel2(_ sender: Any?) { fold(toLevel: 2) }
    @objc func foldToLevel3(_ sender: Any?) { fold(toLevel: 3) }

    func fold(toLevel n: Int) {
        guard Prefs.foldingEnabled else { return }
        folds.setCollapsed(folds.regions.filter { $0.level == n })
    }

    /// Collapses every comment region (keeps the other folds).
    @objc func foldComments(_ sender: Any?) { foldKind(.comment) }

    /// Collapses the imports (`use` / `import`) groups (keeps the other folds).
    @objc func foldImports(_ sender: Any?) { foldKind(.imports) }

    /// Expands every collapsed region touching the selection (or the caret's row).
    @objc func unfoldSelection(_ sender: Any?) {
        for v in selectedRanges {
            let r = v.rangeValue
            if r.length > 0 { folds.unfold(intersecting: r) }
            else if let c = rowCollapsedRegion(at: r.location) { folds.expand(c, recursive: true) }
        }
    }

    private func foldKind(_ kind: FoldKind) {
        guard Prefs.foldingEnabled else { return }
        folds.setCollapsed(folds.collapsed + folds.regions.filter { $0.kind == kind && !folds.collapsed.contains($0) })
    }

    /// First-open folding: the imports group and a license / header comment at the very top.
    func applyOpenFolds() {
        guard Prefs.foldingEnabled, Prefs.foldImportsOnOpen else { return }
        var set = folds.collapsed
        for r in folds.regions where r.kind == .imports && r.level == 1 { set.append(r) }
        if let header = folds.regions.first(where: { $0.kind == .comment && $0.level == 1 }), folds.lineNumber(at: header.start) <= 3 { set.append(header) }
        folds.setCollapsed(set)
    }

    // MARK: Gutter support

    /// State of the fold control for a 1-based line: nil when no region starts there.
    func foldControl(forLine line: Int) -> (collapsed: Bool, regions: Int)? {
        guard Prefs.foldingEnabled, folds.lineCount >= line else { return nil }
        let ce = contentEnd(ofLine: line)
        let rs = folds.regions(startingAt: ce)
        guard !rs.isEmpty else { return nil }
        return (rs.contains { folds.isCollapsed($0) }, rs.count)
    }

    /// Gutter chevron click: expands the outermost collapsed region starting on the line, else collapses the outermost one.
    func toggleFold(atLine line: Int, recursive: Bool) {
        guard Prefs.foldingEnabled else { return }
        let rs = folds.regions(startingAt: contentEnd(ofLine: line))
        if let c = rs.first(where: { folds.isCollapsed($0) }) { folds.expand(c, recursive: recursive) }
        else if let r = rs.first { folds.collapse(r, recursive: recursive) }
    }

    func contentEnd(ofLine line: Int) -> Int {
        let s = string as NSString
        let st = folds.lineStart(line)
        var a = 0, e = 0, ce = 0
        s.getLineStart(&a, end: &e, contentsEnd: &ce, for: NSRange(location: min(st, s.length), length: 0))
        return ce
    }

    // MARK: Helpers

    private func innermostRegion(expanded: Bool) -> FoldController.Region? {
        let caret = min(selectedRange().location, (string as NSString).length)
        let line = folds.lineNumber(at: caret)
        var found: FoldController.Region?
        for r in folds.regions where folds.lineNumber(at: r.start) <= line && line <= folds.lineNumber(at: r.end) {
            if folds.hidden.contains(where: { $0.start <= r.start && r.end <= $0.end && ($0.start != r.start || $0.end != r.end) }) { continue }
            if expanded && folds.isCollapsed(r) { continue }
            found = r
        }
        return found
    }

    /// The outermost collapsed region whose row contains `location` (default: the caret).
    private func rowCollapsedRegion(at location: Int? = nil) -> FoldController.Region? {
        let loc = min(location ?? selectedRange().location, (string as NSString).length)
        let line = folds.lineNumber(at: loc)
        return folds.hidden.first { folds.lineNumber(at: $0.start) == line || folds.lineNumber(at: $0.end) == line }
    }
}
