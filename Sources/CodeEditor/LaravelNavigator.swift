import AppKit

/// Laravel-aware Cmd-click / Go to Declaration (views, routes, config, lang, components, controllers, ...).
///
/// Wiring (integrator): call `LaravelNavigator.start()` once at launch, set `LaravelNavigator.openLocation`, call
/// `LaravelNavigator.goToDeclaration(...)` from Cmd-B before asking the LSP, and `invalidate(root:)` on file changes.
enum LaravelNavigator {
    /// Opens a file at a 1-based line/column. Set by the integrator (ProjectWindow.open(url,line:) + goToLine).
    static var openLocation: ((URL, Int, Int) -> Void)?

    private static var started = false
    fileprivate static var states: [ObjectIdentifier: LaravelTabState] = [:]
    private static var monitor: Any?

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in attach(tab) }
        EditorEvents.onClose { tab in detach(tab) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .flagsChanged, .keyDown]) { event in
            switch event.type {
            case .flagsChanged:
                for s in states.values { s.flagsChanged(event) }
            case .keyDown:
                for s in states.values { s.clear() }
            case .leftMouseDown:
                guard event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift),
                      let view = event.window?.contentView?.hitTest(event.locationInWindow) else { break }
                var v: NSView? = view
                while let cur = v, !(cur is CodeTextView) { v = cur.superview }
                guard let tv = v as? CodeTextView, let state = states[ObjectIdentifier(tv)], let open = openLocation else { break }
                let pt = tv.convert(event.locationInWindow, from: nil)
                guard let off = state.offset(at: pt), let tab = state.tab else { break }
                let targets = Self.targets(in: tab, at: off)
                guard !targets.isEmpty else { break }
                state.clear()
                present(targets, open: open, over: event.window)
                return nil
            default: break
            }
            return event
        }
    }

    static func invalidate(root: URL) { LaravelProject.invalidate(root: root) }

    // MARK: Resolution

    /// Everything the token at `utf16Offset` refers to (empty when it is not a resolvable Laravel reference).
    static func targets(in tab: EditorTab, at utf16Offset: Int) -> [LaravelTarget] {
        reference(in: tab, at: utf16Offset)?.targets ?? []
    }

    /// Highlight range + targets for the token at the offset.
    static func reference(in tab: EditorTab, at utf16Offset: Int) -> LaravelRef? {
        guard let project = LaravelProject.find(for: tab.url) else { return nil }
        return LaravelResolver.resolve(text: tab.textView.string as NSString, offset: utf16Offset, file: tab.url, project: project)
    }

    /// Cmd-B entry point (run before the LSP). Returns false when nothing Laravel-specific applies at the caret.
    static func goToDeclaration(in tab: EditorTab, openLocation: @escaping (URL, Int, Int) -> Void, over window: NSWindow?) -> Bool {
        let caret = tab.textView.selectedRange().location
        var targets = Self.targets(in: tab, at: caret)
        if targets.isEmpty, caret > 0 { targets = Self.targets(in: tab, at: caret - 1) }
        guard !targets.isEmpty else { return false }
        present(targets, open: openLocation, over: window)
        return true
    }

    private static func present(_ targets: [LaravelTarget], open: @escaping (URL, Int, Int) -> Void, over window: NSWindow?) {
        if targets.count == 1 || window == nil {
            let t = targets[0]
            open(t.url, t.line, t.column)
            return
        }
        let items = targets.map { t in
            PickerItem(title: t.title, detail: t.line > 1 ? ":\(t.line)" : "", symbol: icon(for: t.url)) { open(t.url, t.line, t.column) }
        }
        QuickPicker.present(over: window!, placeholder: "Go to declaration", items: items)
    }

    private static func icon(for url: URL) -> String {
        let n = url.lastPathComponent
        if n.hasSuffix(".blade.php") { return "doc.richtext" }
        if n.hasSuffix(".vue") || n.hasSuffix(".js") || n.hasSuffix(".jsx") || n.hasSuffix(".tsx") { return "curlybraces" }
        return "doc.text"
    }

    // MARK: Tab attachment

    private static func attach(_ tab: EditorTab) {
        guard LaravelResolver.fileKind(tab.url) != nil, LaravelProject.find(for: tab.url) != nil else { return }
        let id = ObjectIdentifier(tab.textView)
        guard states[id] == nil else { return }
        states[id] = LaravelTabState(tab: tab)
    }

    private static func detach(_ tab: EditorTab) {
        let id = ObjectIdentifier(tab.textView)
        states[id]?.teardown()
        states[id] = nil
    }

    // Test hooks (headless harness).
    static func attachForTesting(_ tab: EditorTab) { attach(tab) }
    static func state(for tab: EditorTab) -> LaravelTabState? { states[ObjectIdentifier(tab.textView)] }
}

/// Per-tab Cmd-hover state: tracking area, temporary underline, pointing-hand cursor.
final class LaravelTabState: NSObject {
    weak var tab: EditorTab?
    private weak var textView: CodeTextView?
    private var tracking: NSTrackingArea?
    private(set) var underlined: NSRange?
    private var cursorSet = false
    private var observers: [NSObjectProtocol] = []

    init(tab: EditorTab) {
        self.tab = tab
        textView = tab.textView
        super.init()
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        tab.textView.addTrackingArea(area)
        tracking = area
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: tab.scrollView.contentView, queue: .main) { [weak self] _ in
            self?.clear()
        })
        observers.append(nc.addObserver(forName: NSText.didChangeNotification, object: tab.textView, queue: .main) { [weak self] _ in
            self?.clear()
        })
        tab.scrollView.contentView.postsBoundsChangedNotifications = true
    }

    func teardown() {
        clear()
        if let tracking, let tv = textView { tv.removeTrackingArea(tracking) }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    func offset(at p: NSPoint) -> Int? {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let origin = tv.textContainerOrigin
        let pt = NSPoint(x: p.x - origin.x, y: p.y - origin.y)
        var fraction: CGFloat = 0
        let glyph = lm.glyphIndex(for: pt, in: tc, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < lm.numberOfGlyphs else { return nil }
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        guard rect.contains(pt) else { return nil }
        return lm.characterIndexForGlyph(at: glyph)
    }

    @objc func mouseMoved(with event: NSEvent) {
        guard let tv = textView else { return }
        update(flags: event.modifierFlags, point: tv.convert(event.locationInWindow, from: nil))
    }

    @objc func mouseExited(with event: NSEvent) { clear() }

    func flagsChanged(_ event: NSEvent) {
        guard let tv = textView, let w = tv.window, event.window === w else { return }
        let p = tv.convert(w.mouseLocationOutsideOfEventStream, from: nil)
        update(flags: event.modifierFlags, point: p)
    }

    /// Recomputes the underline for the pointer position (also driven by the headless harness).
    func update(flags: NSEvent.ModifierFlags, point: NSPoint) {
        guard let tv = textView, let tab else { return }
        guard flags.contains(.command), !flags.contains(.shift), !flags.contains(.option), tv.visibleRect.contains(point),
              let off = offset(at: point), let ref = LaravelNavigator.reference(in: tab, at: off) else {
            clear(); return
        }
        if underlined == ref.range { return }
        clear()
        guard let lm = tv.layoutManager, NSMaxRange(ref.range) <= (tv.string as NSString).length else { return }
        lm.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor.linkColor],
                                  forCharacterRange: ref.range)
        underlined = ref.range
        NSCursor.pointingHand.set()
        cursorSet = true
    }

    func clear() {
        if let r = underlined, let lm = textView?.layoutManager {
            let len = (textView?.string as NSString?)?.length ?? 0
            let clamped = NSIntersectionRange(r, NSRange(location: 0, length: len))
            if clamped.length > 0 {
                lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: clamped)
                lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: clamped)
            }
        }
        underlined = nil
        if cursorSet { NSCursor.iBeam.set(); cursorSet = false }
    }
}
