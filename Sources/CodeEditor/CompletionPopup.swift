import AppKit

struct PopupRow {
    let label: String
    let detail: String
    let kind: CompletionKind
    let deprecated: Bool
    let matches: [Int]          // UTF-16 offsets in `label` to emphasise
}

private final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum PopupStyle {
    static var background: NSColor { Theme.background.blended(withFraction: Theme.isDark ? 0.07 : 0.03, of: Theme.foreground) ?? Theme.background }
    static var border: NSColor { Theme.foreground.withAlphaComponent(0.18) }
    static var dim: NSColor { Theme.gutter }
    static var accent: NSColor { Theme.color(for: "function") ?? .controlAccentColor }

    static func badge(_ k: CompletionKind) -> (String, NSColor) {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        switch k {
        case .class: return ("c", c(0.90, 0.58, 0.18))
        case .struct: return ("s", c(0.90, 0.58, 0.18))
        case .interface: return ("i", c(0.30, 0.65, 0.55))
        case .enum, .enumMember: return ("e", c(0.55, 0.45, 0.85))
        case .function, .constructor: return ("f", c(0.25, 0.55, 0.90))
        case .method: return ("m", c(0.45, 0.50, 0.90))
        case .variable: return ("v", c(0.20, 0.65, 0.70))
        case .property, .field: return ("p", c(0.85, 0.40, 0.45))
        case .keyword, .operator: return ("k", c(0.70, 0.40, 0.80))
        case .constant, .value: return ("c", c(0.80, 0.50, 0.25))
        case .snippet: return ("s", c(0.35, 0.70, 0.40))
        case .template: return ("⌘", c(0.95, 0.65, 0.20))
        case .module, .namespace: return ("n", c(0.50, 0.55, 0.60))
        case .color: return ("#", c(0.85, 0.35, 0.65))
        case .file, .folder: return ("f", c(0.55, 0.60, 0.65))
        case .typeParameter: return ("t", c(0.60, 0.50, 0.80))
        case .text: return ("a", c(0.55, 0.58, 0.62))
        }
    }
}

final class CompletionListView: NSView {
    static let rowHeight: CGFloat = 22
    static let visibleRows = 10
    static let pad: CGFloat = 4

    var rows: [PopupRow] = [] { didSet { top = 0; needsDisplay = true } }
    var selected = 0 { didSet { ensureVisible(); needsDisplay = true } }
    var onClick: ((Int) -> Void)?
    private(set) var top = 0

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var visibleCount: Int { min(rows.count, Self.visibleRows) }

    private func ensureVisible() {
        if selected < top { top = selected }
        else if selected >= top + Self.visibleRows { top = selected - Self.visibleRows + 1 }
        top = max(0, min(top, max(0, rows.count - Self.visibleRows)))
    }

    override func scrollWheel(with event: NSEvent) {
        let d = event.scrollingDeltaY
        guard d != 0, rows.count > Self.visibleRows else { return }
        top = max(0, min(top + (d > 0 ? -1 : 1), rows.count - Self.visibleRows))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y - Self.pad
        let idx = top + Int(max(0, y) / Self.rowHeight)
        if idx < rows.count { selected = idx; onClick?(idx) }
    }

    private func attributed(_ row: PopupRow) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: 13), bold = NSFont.systemFont(ofSize: 13, weight: .bold)
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: Theme.foreground, .paragraphStyle: para]
        if row.deprecated {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.foregroundColor] = PopupStyle.dim
        }
        let s = NSMutableAttributedString(string: row.label, attributes: attrs)
        let len = s.length
        for m in row.matches where m < len {
            s.addAttributes([.font: bold, .foregroundColor: PopupStyle.accent], range: NSRange(location: m, length: 1))
        }
        return s
    }

    /// Natural content width for the current rows (capped by the caller).
    func naturalWidth() -> CGFloat {
        var maxLabel: CGFloat = 0, maxDetail: CGFloat = 0
        let font = NSFont.systemFont(ofSize: 13), dfont = NSFont.systemFont(ofSize: 12)
        for r in rows.prefix(80) {
            maxLabel = max(maxLabel, (r.label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width)
            maxDetail = max(maxDetail, (r.detail as NSString).size(withAttributes: [.font: dfont]).width)
            _ = font
        }
        return 8 + 22 + maxLabel + (maxDetail > 0 ? 24 + min(maxDetail, 260) : 0) + 14
    }

    override func draw(_ dirtyRect: NSRect) {
        PopupStyle.background.setFill()
        bounds.fill()
        let dfont = NSFont.systemFont(ofSize: 12)
        let dpara = NSMutableParagraphStyle(); dpara.lineBreakMode = .byTruncatingHead; dpara.alignment = .right
        let h = Self.rowHeight
        let end = min(rows.count, top + Self.visibleRows)
        guard top < end else { return }
        for idx in top..<end {
            let y = Self.pad + CGFloat(idx - top) * h
            let rowRect = NSRect(x: 0, y: y, width: bounds.width, height: h)
            if idx == selected {
                NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.40 : 0.24).setFill()
                NSBezierPath(roundedRect: rowRect.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
            }
            let row = rows[idx]
            let (letter, color) = PopupStyle.badge(row.kind)
            let badge = NSRect(x: 10, y: y + (h - 16) / 2, width: 16, height: 16)
            color.withAlphaComponent(row.deprecated ? 0.45 : 0.9).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
            let l = NSAttributedString(string: letter, attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white])
            let ls = l.size()
            l.draw(at: NSPoint(x: badge.midX - ls.width / 2, y: badge.midY - ls.height / 2))

            let detailW: CGFloat = row.detail.isEmpty ? 0 : min((row.detail as NSString).size(withAttributes: [.font: dfont]).width + 2, bounds.width * 0.42)
            let labelX: CGFloat = 34
            let labelW = bounds.width - labelX - 12 - (detailW > 0 ? detailW + 12 : 0)
            let a = attributed(row)
            a.draw(in: NSRect(x: labelX, y: y + (h - 17) / 2, width: max(20, labelW), height: 17))
            if detailW > 0 {
                NSAttributedString(string: row.detail, attributes: [.font: dfont, .foregroundColor: PopupStyle.dim, .paragraphStyle: dpara])
                    .draw(in: NSRect(x: bounds.width - 12 - detailW, y: y + (h - 16) / 2, width: detailW, height: 16))
            }
        }
        if rows.count > Self.visibleRows {          // slim scroll indicator
            let trackH = CGFloat(Self.visibleRows) * h
            let thumbH = max(18, trackH * CGFloat(Self.visibleRows) / CGFloat(rows.count))
            let ty = Self.pad + (trackH - thumbH) * CGFloat(top) / CGFloat(rows.count - Self.visibleRows)
            Theme.foreground.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 5, y: ty, width: 3, height: thumbH), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

final class CompletionDocView: NSView {
    private(set) var text = NSAttributedString()
    override var isFlipped: Bool { true }
    static let width: CGFloat = 340
    static let maxHeight: CGFloat = 260

    func set(markdown: String) {
        text = Self.render(markdown)
        needsDisplay = true
    }

    func neededHeight() -> CGFloat {
        let r = text.boundingRect(with: NSSize(width: Self.width - 24, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return min(Self.maxHeight, ceil(r.height) + 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        PopupStyle.background.setFill()
        bounds.fill()
        text.draw(with: NSRect(x: 12, y: 10, width: bounds.width - 24, height: bounds.height - 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Minimal markdown: fenced code, headings, **bold**, *italic*, `code`, links; everything else plain.
    static func render(_ md: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 12), mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let fg = Theme.foreground
        var inFence = false
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (n, line) in lines.enumerated() {
            let nl = n < lines.count - 1 ? "\n" : ""
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence {
                out.append(NSAttributedString(string: line + nl, attributes: [.font: mono, .foregroundColor: fg]))
                continue
            }
            if line.hasPrefix("#") {
                let t = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                out.append(NSAttributedString(string: t + nl, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: fg]))
                continue
            }
            if let a = try? NSMutableAttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let full = NSRange(location: 0, length: a.length)
                a.addAttributes([.font: body, .foregroundColor: fg], range: full)
                a.enumerateAttribute(.inlinePresentationIntent, in: full) { v, r, _ in
                    guard let raw = (v as? NSNumber)?.uintValue else { return }
                    let intent = InlinePresentationIntent(rawValue: raw)
                    if intent.contains(.code) { a.addAttribute(.font, value: mono, range: r) }
                    else if intent.contains(.stronglyEmphasized) { a.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .bold), range: r) }
                    else if intent.contains(.emphasized) {
                        a.addAttribute(.font, value: NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask), range: r)
                    }
                }
                a.removeAttribute(.link, range: full)
                out.append(a)
                out.append(NSAttributedString(string: nl, attributes: [.font: body]))
            } else {
                out.append(NSAttributedString(string: line + nl, attributes: [.font: body, .foregroundColor: fg]))
            }
        }
        return out
    }
}

/// One shared borderless panel (plus an optional documentation panel). Never becomes key, never activates the app.
final class CompletionPopup {
    static let shared = CompletionPopup()

    let list = CompletionListView()
    let doc = CompletionDocView()
    private var panel: NSPanel?
    private var docPanel: NSPanel?
    private weak var parent: NSWindow?
    private(set) var isShown = false
    private var theme: NSObjectProtocol?

    private init() {
        theme = NotificationCenter.default.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.list.needsDisplay = true
            self?.doc.needsDisplay = true
        }
    }

    private func makePanel(_ view: NSView) -> NSPanel {
        let p = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.level = .floating
        p.isReleasedWhenClosed = false
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.masksToBounds = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = PopupStyle.border.cgColor
        view.autoresizingMask = [.width, .height]
        view.frame = box.bounds
        box.addSubview(view)
        p.contentView = box
        return p
    }

    var listSize: NSSize {
        let w = max(300, min(640, list.naturalWidth()))
        let h = CGFloat(list.visibleCount) * CompletionListView.rowHeight + 2 * CompletionListView.pad
        return NSSize(width: w, height: h)
    }

    /// `anchor` = screen rect of the line containing the prefix start (x = prefix start).
    func present(rows: [PopupRow], selected: Int, anchor: NSRect, window: NSWindow?) {
        list.rows = rows
        list.selected = selected
        isShown = true
        let size = listSize
        list.frame = NSRect(origin: .zero, size: size)
        guard !AppEnv.headless, window != nil else { return }
        if panel == nil { panel = makePanel(list) }
        guard let panel else { return }
        panel.contentView?.layer?.borderColor = PopupStyle.border.cgColor
        let screen = window?.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 4000, height: 4000)
        var x = anchor.minX - 34
        x = max(vis.minX + 4, min(x, vis.maxX - size.width - 4))
        var y = anchor.minY - size.height - 2
        if y < vis.minY { y = anchor.maxY + 2 }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if parent !== window {
            if let p = parent { p.removeChildWindow(panel) }
            window?.addChildWindow(panel, ordered: .above)
            parent = window
        }
        panel.orderFront(nil)
        layoutDoc()
    }

    func update(selected: Int) {
        list.selected = selected
    }

    func setDocumentation(_ md: String?) {
        if let md, !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            doc.set(markdown: md)
            layoutDoc()
        } else {
            doc.set(markdown: "")
            docPanel?.orderOut(nil)
        }
    }

    private func layoutDoc() {
        guard isShown, doc.text.length > 0 else { return }
        let h = doc.neededHeight()
        doc.frame = NSRect(x: 0, y: 0, width: CompletionDocView.width, height: h)
        guard !AppEnv.headless, let panel, let parent else { return }
        if docPanel == nil { docPanel = makePanel(doc) }
        guard let dp = docPanel else { return }
        dp.contentView?.layer?.borderColor = PopupStyle.border.cgColor
        let vis = (parent.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 4000, height: 4000)
        let pf = panel.frame
        var x = pf.maxX + 4
        if x + CompletionDocView.width > vis.maxX { x = pf.minX - CompletionDocView.width - 4 }
        var y = pf.maxY - h
        y = max(vis.minY + 4, y)
        dp.setFrame(NSRect(x: x, y: y, width: CompletionDocView.width, height: h), display: true)
        if dp.parent == nil { parent.addChildWindow(dp, ordered: .above) }
        dp.orderFront(nil)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        for p in [panel, docPanel] {
            guard let p else { continue }
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        }
        parent = nil
    }

    // MARK: Headless rendering

    func snapshot(to path: String, includeDoc: Bool = true) {
        let size = listSize
        list.frame = NSRect(origin: .zero, size: size)
        var dsize = NSSize.zero
        if includeDoc, doc.text.length > 0 {
            dsize = NSSize(width: CompletionDocView.width, height: doc.neededHeight())
            doc.frame = NSRect(origin: .zero, size: dsize)
        }
        let gap: CGFloat = 6
        let total = NSSize(width: size.width + (dsize.width > 0 ? dsize.width + gap : 0) + 24, height: max(size.height, dsize.height) + 24)
        let canvas = NSView(frame: NSRect(origin: .zero, size: total))
        canvas.wantsLayer = true
        let bg = Theme.background
        let img = NSImage(size: total, flipped: true) { rect in
            bg.setFill(); rect.fill()
            func draw(_ v: NSView, at p: NSPoint) {
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.cacheDisplay(in: v.bounds, to: rep)
                NSGraphicsContext.saveGraphicsState()
                let r = NSRect(origin: p, size: v.bounds.size)
                let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
                NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor.black.withAlphaComponent(0.35).cgColor)
                PopupStyle.background.setFill(); path.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                rep.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                PopupStyle.border.setStroke(); path.lineWidth = 1; path.stroke()
            }
            draw(self.list, at: NSPoint(x: 12, y: 12))
            if dsize.width > 0 { draw(self.doc, at: NSPoint(x: 12 + size.width + gap, y: 12)) }
            return true
        }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
