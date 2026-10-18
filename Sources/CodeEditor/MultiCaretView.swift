import AppKit

/// Mutable multi-caret bookkeeping owned by a CodeTextView. No timer exists unless 2+ carets are showing in the key window.
final class MultiCaretState {
    var sels: [MultiCaret.Sel] = []        // directional model; trusted only while it matches the view's selectedRanges
    var lastAdded: NSRange?                // the caret Esc collapses to
    var shadow: [NSRange] = []             // AppKit's selectedRanges when `sels` was set; a mismatch means the model is stale
    var setting = false                    // true while setMultiSels drives AppKit (its selection hooks must not drop the model)
    var editing = false                    // true while applyMulti edits (didChangeText must not drop the model)
    var blinkOn = true
    var cachedRects: [NSRect] = []         // visible extra-caret rects at the last change (invalidated on the next one)
    var timer: Timer?
    var observing = false
    deinit { timer?.invalidate() }
}

/// View side of multi-caret editing (model rules live in MultiCaret.swift). NSTextView keeps `selectedRanges` for us and draws
/// non-empty ranges; we draw the carets (AppKit only draws one) and route typing / delete / paste / movement across all ranges.
extension CodeTextView {
    /// AppKit cannot hold several empty ranges, so extra carets live in `multi.sels`; AppKit keeps the non-empty ranges
    /// (or the primary caret). The model is trusted only while AppKit's selection still equals the shadow we stored.
    private var multiModelValid: Bool { !multi.sels.isEmpty && selectedRanges.map { $0.rangeValue } == multi.shadow }

    /// Every selection / caret of the editor (model-aware replacement for `selectedRanges`).
    var effectiveRanges: [NSRange] { multiModelValid ? multi.sels.map(\.range) : selectedRanges.map { $0.rangeValue } }

    var multiCaretActive: Bool { !hasMarkedText() && effectiveRanges.count > 1 }

    // MARK: Model sync

    /// Directional selections matching the view (forward selections when the view changed behind our back).
    func multiSels() -> [MultiCaret.Sel] { multiModelValid ? multi.sels : selectedRanges.map { MultiCaret.Sel($0.rangeValue) } }

    func setMultiSels(_ sels: [MultiCaret.Sel], reveal head: Bool = true) {
        let n = MultiCaret.normalize(sels)
        let was = userNavigating
        userNavigating = true
        defer { userNavigating = was }
        guard n.count > 1, let primary = n.last else {
            multi.sels = []
            if let only = n.first { setSelectedRange(only.range) }
            return
        }
        let nonEmpty = n.filter { !$0.isEmpty }.map { NSValue(range: $0.range) }
        multi.setting = true
        setSelectedRanges(nonEmpty.isEmpty ? [NSValue(range: NSRange(location: primary.head, length: 0))] : nonEmpty,
                          affinity: .downstream, stillSelecting: false)
        multi.setting = false
        multi.sels = n
        multi.shadow = selectedRanges.map { $0.rangeValue }
        refreshMultiCarets()
        if head { scrollRangeToVisible(NSRange(location: primary.head, length: 0)) }
    }

    /// Selection hook (setSelectedRange(s)): a change we did not make drops the model.
    func multiSelectionDidChange() {
        if !multi.setting { multi.sels = [] }
        refreshMultiCarets()
    }

    func multiTextDidChange() { if !multi.editing { multi.sels = [] } }

    // MARK: Caret drawing and blink

    /// Called after every selection change: refreshes caret rects, the blink timer and its window observers.
    func refreshMultiCarets() {
        let active = multiCaretActive
        if !active && multi.cachedRects.isEmpty && multi.timer == nil && !multi.observing { return }
        for r in multi.cachedRects { setNeedsDisplay(r) }
        multi.blinkOn = true
        if active {
            multi.cachedRects = visibleCaretRects(in: visibleRect)
            for r in multi.cachedRects { setNeedsDisplay(r) }
            observeKeyState(true)
        } else {
            multi.cachedRects = []
            observeKeyState(false)
            multi.lastAdded = nil
        }
        updateBlinkTimer()
    }

    private func observeKeyState(_ on: Bool) {
        guard on != multi.observing else { return }
        multi.observing = on
        let nc = NotificationCenter.default
        if on {
            nc.addObserver(self, selector: #selector(multiKeyStateChanged), name: NSWindow.didBecomeKeyNotification, object: nil)
            nc.addObserver(self, selector: #selector(multiKeyStateChanged), name: NSWindow.didResignKeyNotification, object: nil)
        } else {
            nc.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            nc.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        }
    }

    @objc private func multiKeyStateChanged(_ note: Notification) {
        guard (note.object as? NSWindow) === window else { return }
        multi.blinkOn = true
        updateBlinkTimer()
        for r in multi.cachedRects { setNeedsDisplay(r) }
    }

    func updateBlinkTimer() {
        let want = multiCaretActive && window?.isKeyWindow == true && window?.firstResponder === self
        if !want { multi.timer?.invalidate(); multi.timer = nil; multi.blinkOn = true; return }
        guard multi.timer == nil else { return }
        let t = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            guard let self, self.multiCaretActive else { return }
            guard self.window?.isKeyWindow == true, self.window?.firstResponder === self else { self.updateBlinkTimer(); return }
            self.multi.blinkOn.toggle()
            self.multi.cachedRects = self.visibleCaretRects(in: self.visibleRect)
            for r in self.multi.cachedRects { self.setNeedsDisplay(r) }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        multi.timer = t
    }

    /// Rect of a caret at `loc` in view coordinates (nil when the glyph is hidden, e.g. inside a fold).
    func caretRect(at loc: Int) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let s = ns
        let origin = textContainerOrigin
        var r: NSRect
        if loc >= s.length {
            if s.length == 0 || s.character(at: s.length - 1) == 10 {
                r = lm.extraLineFragmentRect
                if r.height == 0 { return nil }
                r.size.width = 0
            } else {
                let g = lm.glyphIndexForCharacter(at: s.length - 1)
                r = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
                r.origin.x = r.maxX
            }
        } else {
            let g = lm.glyphIndexForCharacter(at: loc)
            r = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
        }
        guard r.height > 0 else { return nil }
        return NSRect(x: r.minX + origin.x, y: r.minY + origin.y, width: 2, height: r.height)
    }

    /// Rects of the empty carets inside `rect` (binary search over the sorted ranges: cheap with thousands of carets).
    func visibleCaretRects(in rect: NSRect) -> [NSRect] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        let ranges = currentRanges
        let origin = textContainerOrigin
        let local = rect.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: 0, dy: -4)
        let g = lm.glyphRange(forBoundingRect: local, in: tc)
        let chars = lm.characterRange(forGlyphRange: g, actualGlyphRange: nil)
        var lo = 0, hi = ranges.count
        while lo < hi { let mid = (lo + hi) / 2; if ranges[mid].upperBound < chars.location { lo = mid + 1 } else { hi = mid } }
        var out: [NSRect] = []
        var i = lo
        while i < ranges.count, ranges[i].location <= chars.upperBound {
            if ranges[i].length == 0, let r = caretRect(at: ranges[i].location), r.intersects(rect) { out.append(r) }
            i += 1
        }
        return out
    }

    func drawExtraCarets(in rect: NSRect) {
        guard multiCaretActive, multi.blinkOn || window?.isKeyWindow != true else { return }
        insertionPointColor.setFill()
        for r in visibleCaretRects(in: rect) { r.fill() }
    }

    // MARK: Commands (routed from doCommand)

    private static let moveKinds: [String: (kind: Int, collapse: Int)] = {
        // kind: 0 left, 1 right, 2 up, 3 down, 4 word left, 5 word right, 6 line start, 7 line end, 8 doc start, 9 doc end
        var t: [String: (Int, Int)] = [:]
        let base: [(String, Int, Int)] = [
            ("moveLeft", 0, -1), ("moveBackward", 0, -1), ("moveRight", 1, 1), ("moveForward", 1, 1),
            ("moveUp", 2, 0), ("moveDown", 3, 0),
            ("moveWordLeft", 4, 0), ("moveWordBackward", 4, 0), ("moveWordRight", 5, 0), ("moveWordForward", 5, 0),
            ("moveToBeginningOfLine", 6, 0), ("moveToLeftEndOfLine", 6, 0), ("moveToEndOfLine", 7, 0), ("moveToRightEndOfLine", 7, 0),
            ("moveToBeginningOfDocument", 8, 0), ("moveToEndOfDocument", 9, 0),
        ]
        for (n, k, c) in base { t[n + ":"] = (k, c); t[n + "AndModifySelection:"] = (k, 0) }
        return t
    }()

    /// Handles a text-system command for all carets. Returns false to let AppKit process it (single caret, unknown command).
    func handleMultiCommand(_ selector: Selector) -> Bool {
        guard multiCaretActive else { return false }
        let name = NSStringFromSelector(selector)
        switch name {
        case "cancelOperation:":
            collapseToOneCaret(); return true
        case "deleteBackward:": multiDelete(.backward); return true
        case "deleteForward:": multiDelete(.forward); return true
        case "deleteWordBackward:": multiDelete(.wordBackward); return true
        default: break
        }
        guard let m = Self.moveKinds[name] else { return false }
        let extend = name.hasSuffix("AndModifySelection:")
        let s = ns
        let sels = multiSels()
        let out = MultiCaret.move(sels, extend: extend, collapse: m.collapse) { sel in
            let h = sel.head
            switch m.kind {
            case 0: return (MultiCaret.step(s, from: h, forward: false), nil)
            case 1: return (MultiCaret.step(s, from: h, forward: true), nil)
            case 2, 3:
                let v = MultiCaret.vertical(s, from: h, up: m.kind == 2, goal: sel.goal)
                return (v.loc, v.goal)
            case 4: return (self.wordStop(from: h, forward: false), nil)
            case 5: return (self.wordStop(from: h, forward: true), nil)
            case 6: return (self.smartHome(from: h), nil)
            case 7: return (self.rowBounds(containing: h).end, nil)
            case 8: return (0, nil)
            default: return (s.length, nil)
            }
        }
        setMultiSels(out)
        return true
    }

    func collapseToOneCaret() {
        let ranges = currentRanges
        guard let first = ranges.first else { return }
        let keep = multi.lastAdded.flatMap { a in ranges.first { $0.location == a.location } } ?? ranges.last ?? first
        multi.lastAdded = nil
        setSelectedRange(NSRange(location: keep.location, length: 0))
        scrollRangeToVisible(selectedRange())
    }

    private func multiDelete(_ kind: MultiCaret.DeleteKind) {
        guard !hasMarkedText() else { return }
        let ranges = currentRanges.sorted { $0.location < $1.location }
        let edits = MultiCaret.deleteEdits(ranges, in: ns, kind: kind,
                                           smartBackspace: { [unowned self] in self.smartIndentDeletion(at: $0) },
                                           wordStop: { [unowned self] in self.wordStop(from: $0, forward: false) })
        applyMulti(edits)
    }

    /// Applies ascending edits as one undo step with one caret per edit.
    func applyMulti(_ edits: [MultiCaret.Edit]) {
        guard !edits.isEmpty else { return }
        multi.editing = true
        replaceRanges(edits.map { ($0.range, $0.text, $0.caret) })
        multi.editing = false
    }

    /// Typing over all carets with the same auto-pairing / skip-over rules as the single-caret path.
    func multiType(_ text: String) {
        let ranges = currentRanges.sorted { $0.location < $1.location }
        let s = ns
        let u = Array(text.utf16)
        var edits: [MultiCaret.Edit] = []
        for r in ranges {
            guard u.count == 1, r.length == 0 else { edits.append(MultiCaret.Edit(r, text)); continue }
            let c = u[0]
            let next: unichar? = r.location < s.length ? s.character(at: r.location) : nil
            let isQuote = c == 34 || c == 39 || c == 96
            if (c == 41 || c == 93 || c == 125 || isQuote), next == c {
                edits.append(MultiCaret.Edit(NSRange(location: r.location, length: 1), text)); continue    // type over the closer
            }
            guard let close = Self.pairs[c], !(c == 41 || c == 93 || c == 125) else { edits.append(MultiCaret.Edit(r, text)); continue }
            let prev: unichar? = r.location > 0 ? s.character(at: r.location - 1) : nil
            if isQuote, let pv = prev, (pv < 128 && (pv == 95 || (pv >= 48 && pv <= 57) || (pv >= 65 && pv <= 90) || (pv >= 97 && pv <= 122))) || pv == 92 || pv == c {
                edits.append(MultiCaret.Edit(r, text)); continue
            }
            let nextOK = next == nil || [32, 9, 10, 13, 41, 93, 125, 44, 59, 62].contains(next!)
            edits.append(nextOK ? MultiCaret.Edit(r, text + String(utf16CodeUnits: [close], count: 1), caret: 1) : MultiCaret.Edit(r, text))
        }
        applyMulti(edits)
    }

    // MARK: Clipboard

    func multiPaste() -> Bool {
        guard multiCaretActive, let clip = NSPasteboard.general.string(forType: .string) else { return false }
        let ranges = currentRanges.sorted { $0.location < $1.location }
        if let lines = MultiCaret.distribute(clip, count: ranges.count) {
            applyMulti(zip(ranges, lines).map { MultiCaret.Edit($0, $1) })
        } else {
            applyMulti(MultiCaret.insertEdits(ranges, clip))
        }
        return true
    }

    func multiCopy() -> Bool {
        let parts = currentRanges.sorted { $0.location < $1.location }.filter { $0.length > 0 }.map { ns.substring(with: $0) }
        guard multiCaretActive, !parts.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: "\n"), forType: .string)
        return true
    }

    func multiCut() -> Bool {
        guard multiCopy() else { return false }
        applyMulti(currentRanges.sorted { $0.location < $1.location }.filter { $0.length > 0 }.map { MultiCaret.Edit($0, "", caret: 0) })
        return true
    }

    // MARK: Occurrence / caret commands

    @objc func addCaretAbove(_ sender: Any?) { setMultiSels(MultiCaret.addCarets(multiSels(), in: ns, up: true)) }
    @objc func addCaretBelow(_ sender: Any?) { setMultiSels(MultiCaret.addCarets(multiSels(), in: ns, up: false)) }

    // MARK: Mouse

    private func viewColumn(atX x: CGFloat) -> Int {
        let pad = (textContainer?.lineFragmentPadding ?? 0) + textContainerOrigin.x
        return max(0, Int(((x - pad) / max(1, charWidth)).rounded()))
    }

    /// Option-drag / Shift+Option-drag rectangle between two view points, merged over `base` when `keepBase`.
    func columnSelection(from a: NSPoint, to b: NSPoint) -> [NSRange] {
        MultiCaret.columnRanges(in: ns, anchorLoc: characterIndexForInsertion(at: a), anchorCol: viewColumn(atX: a.x),
                                headLoc: characterIndexForInsertion(at: b), headCol: viewColumn(atX: b.x))
    }

    /// Toggles a caret at `loc` (adds one, or removes it when a caret is already there and others remain).
    func toggleCaret(at loc: Int, base: [NSRange]) {
        var sels = base.map(MultiCaret.Sel.init)
        if sels.count > 1, let i = sels.firstIndex(where: { $0.isEmpty && $0.head == loc }) {
            sels.remove(at: i)
        } else {
            sels.append(MultiCaret.Sel(caret: loc))
            multi.lastAdded = NSRange(location: loc, length: 0)
        }
        setMultiSels(sels, reveal: false)
    }

    /// Option-click adds a caret, Option-drag (with or without Shift) selects a column. Runs its own tracking loop.
    func handleOptionMouseDown(_ event: NSEvent) -> Bool {
        let f = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard f.contains(.option), !f.contains(.command), !f.contains(.control), let win = window else { return false }
        win.makeFirstResponder(self)
        let start = convert(event.locationInWindow, from: nil)
        let base = currentRanges
        var dragged = false
        while let e = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            let p = convert(e.locationInWindow, from: nil)
            if e.type == .leftMouseUp {
                if !dragged { toggleCaret(at: characterIndexForInsertion(at: start), base: base) }
                break
            }
            if !dragged, hypot(p.x - start.x, p.y - start.y) < 3 { continue }
            dragged = true
            autoscroll(with: e)
            let ranges = columnSelection(from: start, to: p)
            multi.lastAdded = ranges.last
            setMultiSels(ranges.map(MultiCaret.Sel.init), reveal: false)
        }
        return true
    }
}
