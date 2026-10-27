import AppKit

/// One clickable piece of the bar: a path component or an enclosing symbol.
struct BreadcrumbSegment: Equatable {
    enum Kind: Equatable { case root, folder, file, symbol(BreadcrumbSymbolKind) }
    var title: String
    var kind: Kind
    var url: URL?               // path segments
    var node: Int?              // symbol segments: index into the outline
    var isPath: Bool { if case .symbol = kind { return false }; return true }
}

enum BreadcrumbPath {
    /// The folder the project lives in: the integrator's root, else the nearest ancestor holding .git / composer.json / package.json.
    static func root(for url: URL, explicit: URL?) -> URL? {
        if let explicit {
            let r = explicit.standardizedFileURL.path
            if url.standardizedFileURL.path.hasPrefix(r == "/" ? "/" : r + "/") { return explicit.standardizedFileURL }
            return nil
        }
        let fm = FileManager.default
        var dir = url.deletingLastPathComponent().standardizedFileURL
        while dir.path != "/" {
            for marker in [".git", "composer.json", "package.json"]
            where fm.fileExists(atPath: dir.appendingPathComponent(marker).path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// `project › folder › sub › File.php`. A file outside the project shows its absolute path (home abbreviated to `~`).
    static func segments(for url: URL, root: URL?) -> [BreadcrumbSegment] {
        let file = url.standardizedFileURL
        var out: [BreadcrumbSegment] = []
        var base: URL
        var parts: [String]
        if let root {
            base = root
            out.append(BreadcrumbSegment(title: root.lastPathComponent.isEmpty ? "/" : root.lastPathComponent, kind: .root, url: root))
            let rel = String(file.path.dropFirst(root.path == "/" ? 1 : root.path.count + 1))
            parts = rel.split(separator: "/").map(String.init)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            if file.path.hasPrefix(home + "/") {
                base = URL(fileURLWithPath: home)
                out.append(BreadcrumbSegment(title: "~", kind: .root, url: base))
                parts = file.path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
            } else {
                base = URL(fileURLWithPath: "/")
                parts = file.path.split(separator: "/").map(String.init)
            }
        }
        for (i, p) in parts.enumerated() {
            base = base.appendingPathComponent(p)
            out.append(BreadcrumbSegment(title: p, kind: i == parts.count - 1 ? .file : .folder, url: base))
        }
        return out
    }
}

/// Which segments stay visible when the bar is too narrow: the middle collapses into one `…` entry.
enum BreadcrumbLayout {
    struct Result: Equatable {
        var visible: [Int]
        /// Hidden range; the `…` entry sits between the head and the tail.
        var collapsed: Range<Int>?
    }

    static func collapse(widths: [CGFloat], available: CGFloat, ellipsisWidth: CGFloat, separator: CGFloat) -> Result {
        let n = widths.count
        func total(_ idx: [Int]) -> CGFloat { idx.reduce(0) { $0 + widths[$1] } + separator * CGFloat(max(0, idx.count - 1)) }
        let all = Array(0..<n)
        if n == 0 || total(all) <= available { return Result(visible: all, collapsed: nil) }
        // Largest tail (counting from the end) that fits next to `head` items and the ellipsis.
        func bestTail(head: Int) -> Int {
            var k = 0
            while head + k + 1 < n {
                let idx = Array(0..<head) + Array((n - k - 1)..<n)
                if total(idx) + separator + ellipsisWidth > available { break }
                k += 1
            }
            return k
        }
        let k1 = n > 2 ? bestTail(head: 1) : 0, k0 = bestTail(head: 0)
        let head = (k1 >= 1 && k1 >= k0 - 1) ? 1 : 0
        let k = max(1, head == 1 ? k1 : k0)
        let tailStart = n - k
        guard head < tailStart else { return Result(visible: all, collapsed: nil) }
        return Result(visible: Array(0..<head) + Array(tailStart..<n), collapsed: head..<tailStart)
    }
}

/// Path + symbol chain strip above the editor. Draws itself (no per-segment views) so updates are cheap.
final class BreadcrumbBar: NSView, NSViewToolTipOwner {
    static let height: CGFloat = 24
    private static let separatorWidth: CGFloat = 14
    private static let maxSegmentWidth: CGFloat = 240

    private(set) var segments: [BreadcrumbSegment] = []
    /// Layout of the last draw/layout pass: segment index (or -1 for the `…` entry) -> frame.
    private(set) var hits: [(index: Int, frame: NSRect)] = []
    private(set) var layoutResult = BreadcrumbLayout.Result(visible: [], collapsed: nil)
    private var hovered: Int?
    private var focus: Int?                 // keyboard: segment index or -1 for the ellipsis

    /// Menu for a segment (nil = nothing to show); -1 asks for the collapsed `…` menu.
    var menuProvider: ((Int) -> NSMenu?)?
    /// Right-click menu for a segment.
    var contextMenuProvider: ((Int) -> NSMenu?)?
    /// Shows a menu (tests replace this; the default pops it up under the segment).
    var present: (NSMenu, NSPoint, NSView) -> Void = { menu, point, view in menu.popUp(positioning: nil, at: point, in: view) }
    var onEscape: (() -> Void)?
    /// Width kept free at the right edge for controls drawn over the bar (the viewer's Source / Split / Preview switch).
    var trailingReserve: CGFloat = 0 { didSet { if trailingReserve != oldValue { relayout() } } }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    private var textFont: NSFont { .systemFont(ofSize: 11.5) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Breadcrumbs")
        NotificationCenter.default.addObserver(self, selector: #selector(restyle), name: Theme.didChange, object: nil)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func restyle() { needsDisplay = true }

    func set(segments new: [BreadcrumbSegment]) {
        guard new != segments else { return }
        segments = new
        if let f = focus, f >= new.count { focus = nil }
        relayout()
    }

    override func layout() { super.layout(); relayout() }

    // MARK: Layout

    private func title(_ i: Int) -> NSAttributedString {
        NSAttributedString(string: segments[i].title, attributes: [.font: textFont])
    }

    private func width(of i: Int) -> CGFloat {
        let hasIcon = iconName(for: segments[i]) != nil
        return min(Self.maxSegmentWidth, ceil(title(i).size().width) + 8 + (hasIcon ? 18 : 0))
    }

    func iconName(for s: BreadcrumbSegment) -> String? {
        switch s.kind {
        case .root, .folder: return "folder"
        case .file: return FileIcon.symbol(forExtension: (s.title as NSString).pathExtension)
        case .symbol(let k): return k.iconName
        }
    }

    private func relayout() {
        let ellipsisWidth: CGFloat = 22
        let widths = segments.indices.map(width(of:))
        layoutResult = BreadcrumbLayout.collapse(widths: widths, available: max(0, bounds.width - 16 - trailingReserve),
                                                 ellipsisWidth: ellipsisWidth, separator: Self.separatorWidth)
        hits = []
        var x: CGFloat = 8
        let y = (Self.height - 18) / 2
        let visible = layoutResult.visible
        for (n, i) in visible.enumerated() {
            if n > 0 { x += Self.separatorWidth }
            if let c = layoutResult.collapsed, i == c.upperBound {
                hits.append((-1, NSRect(x: x, y: y, width: ellipsisWidth, height: 18)))
                x += ellipsisWidth + Self.separatorWidth
            }
            let w = min(widths[i], max(24, bounds.width - 8 - trailingReserve - x))
            hits.append((i, NSRect(x: x, y: y, width: w, height: 18)))
            x += w
        }
        removeAllToolTips()
        for h in hits { addToolTip(h.frame, owner: self, userData: UnsafeMutableRawPointer(bitPattern: h.index + 2)) }
        needsDisplay = true
    }

    func frame(ofSegment i: Int) -> NSRect? { hits.first { $0.index == i }?.frame }
    var collapsedIndices: [Int] { layoutResult.collapsed.map { Array($0) } ?? [] }

    // MARK: Tooltips

    func tooltip(forSegment i: Int) -> String {
        if i == -1 { return collapsedIndices.map { segments[$0].title }.joined(separator: " › ") }
        let s = segments[i]
        switch s.kind {
        case .symbol(let k): return "\(k.rawValue.capitalized) \(s.title)"
        default: return s.url?.path ?? s.title
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        let i = Int(bitPattern: data) - 2
        return i == -1 || segments.indices.contains(i) ? tooltip(forSegment: i) : ""
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let p = Theme.palette
        p.background.setFill()
        bounds.fill()
        p.foreground.withAlphaComponent(0.08).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        let focused = window?.firstResponder === self
        let lastIndex = segments.count - 1
        for (n, h) in hits.enumerated() {
            if n > 0 {
                let sx = h.frame.minX - Self.separatorWidth
                drawChevron(in: NSRect(x: sx, y: h.frame.minY, width: Self.separatorWidth, height: h.frame.height), color: p.gutter)
            }
            if h.index == hovered || (focused && h.index == focus) {
                (focused && h.index == focus ? NSColor.controlAccentColor.withAlphaComponent(0.25) : p.foreground.withAlphaComponent(0.08)).setFill()
                NSBezierPath(roundedRect: h.frame, xRadius: 4, yRadius: 4).fill()
            }
            if h.index == -1 {
                let a: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: p.foreground.withAlphaComponent(0.7)]
                ("…" as NSString).draw(at: NSPoint(x: h.frame.minX + 6, y: h.frame.minY + 1), withAttributes: a)
                continue
            }
            let s = segments[h.index]
            let isLast = h.index == lastIndex
            let color = isLast ? p.foreground : p.foreground.withAlphaComponent(0.68)
            var tx = h.frame.minX + 4
            if let icon = iconName(for: s), let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
                let tint: NSColor = { switch s.kind {
                    case .file: return FileIcon.tint(forExtension: (s.title as NSString).pathExtension)
                    case .symbol: return p.gutter
                    default: return p.gutter } }()
                let cfg = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .regular).applying(.init(paletteColors: [tint]))
                if let img = image.withSymbolConfiguration(cfg) {
                    let size = img.size
                    img.draw(in: NSRect(x: tx, y: h.frame.midY - size.height / 2, width: size.width, height: size.height))
                }
                tx += 18
            }
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            let a: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: color, .paragraphStyle: para]
            let rect = NSRect(x: tx, y: h.frame.minY + 1, width: max(0, h.frame.maxX - tx - 2), height: 16)
            (s.title as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: a)
        }
    }

    private func drawChevron(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        path.move(to: NSPoint(x: cx - 1.8, y: cy - 3.2)); path.line(to: NSPoint(x: cx + 1.6, y: cy)); path.line(to: NSPoint(x: cx - 1.8, y: cy + 3.2))
        path.lineWidth = 1.1
        color.withAlphaComponent(0.8).setStroke()
        path.stroke()
    }

    // MARK: Mouse

    private func hit(_ point: NSPoint) -> Int? { hits.first { $0.frame.insetBy(dx: -3, dy: -3).contains(point) }?.index }

    override func mouseMoved(with event: NSEvent) {
        let h = hit(convert(event.locationInWindow, from: nil))
        if h != hovered { hovered = h; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let i = hit(convert(event.locationInWindow, from: nil)) else { return }
        open(segment: i)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = hit(convert(event.locationInWindow, from: nil)) else { return nil }
        return contextMenuProvider?(i == -1 ? (collapsedIndices.first ?? 0) : i)
    }

    /// Pops the dropdown of a segment (`-1` = the collapsed `…` entry).
    func open(segment i: Int) {
        guard let menu = menuProvider?(i), let f = frame(ofSegment: i) else { return }
        present(menu, NSPoint(x: f.minX, y: bounds.height), self)
    }

    // MARK: Keyboard

    /// Shared by `focusBreadcrumbs()`: keyboard focus starts on the innermost segment.
    func focusLast() {
        focus = layoutResult.visible.last ?? (segments.isEmpty ? nil : segments.count - 1)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    var focusedSegment: Int? { focus }

    private func moveFocus(_ delta: Int) {
        let order: [Int] = hits.map(\.index)
        guard !order.isEmpty else { return }
        let at = focus.flatMap { order.firstIndex(of: $0) } ?? order.count - 1
        focus = order[min(order.count - 1, max(0, at + delta))]
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: moveFocus(-1)                           // left
        case 124: moveFocus(1)                            // right
        case 125, 36, 76, 49: if let f = focus { open(segment: f) }   // down / return / enter / space
        case 53: onEscape?()                              // escape
        default: super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
}
