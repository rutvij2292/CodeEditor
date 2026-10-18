import AppKit
import ImageIO
import SwiftTreeSitter

/// Syntax colours for a code snippet using the editor's own grammars and palette (no editor view needed).
/// Main thread only (the grammar parsers are shared with the editors' highlighters).
enum OfflineHighlight {
    private static let fullRange = TSRange(points: Point(row: 0, column: 0)..<Point(row: UInt32.max, column: UInt32.max), bytes: 0..<UInt32.max)

    static func apply(to attributed: NSMutableAttributedString, range: NSRange, code: String, lang: String) {
        guard var key = Languages.key(forInjectionName: lang), code.utf16.count < 20_000 else { return }
        if key == "php", !code.contains("<?") { key = "php_only" }
        guard let g = Languages.grammar(forKey: key), let parser = g.parser, let query = g.highlights else { return }
        parser.includedRanges = [fullRange]
        guard let tree = parser.parse(code) else { return }
        let ns = code as NSString
        let ctx = SwiftTreeSitter.Predicate.Context(textProvider: { r, _ in
            guard r.location >= 0, NSMaxRange(r) <= ns.length else { return nil }
            return ns.substring(with: r)
        })
        var items: [(len: Int, comps: Int, pattern: Int, range: NSRange, name: String)] = []
        for match in query.execute(in: tree) where match.allowed(in: ctx) {
            for c in match.captures {
                let comps = c.nameComponents
                guard let first = comps.first, !first.hasPrefix("_") else { continue }
                items.append((c.range.length, comps.count, match.patternIndex, c.range, comps.joined(separator: ".")))
            }
        }
        items.sort { $0.len != $1.len ? $0.len > $1.len : ($0.comps != $1.comps ? $0.comps < $1.comps : $0.pattern < $1.pattern) }
        for it in items {
            guard let st = Theme.style(for: it.name), NSMaxRange(it.range) <= range.length else { continue }
            let r = NSRange(location: range.location + it.range.location, length: it.range.length)
            attributed.addAttribute(.foregroundColor, value: st.color, range: r)
            if st.italic { attributed.addAttribute(.obliqueness, value: 0.2, range: r) }
        }
    }
}

struct MDStyle {
    let fg: NSColor, dim: NSColor, link: NSColor, codeBG: NSColor, border: NSColor, quoteBar: NSColor, headerBG: NSColor
    let body: NSFont, mono: NSFont

    init() {
        let p = Theme.palette
        fg = p.foreground
        dim = p.foreground.withAlphaComponent(0.65)
        link = p.isDark ? Theme.hex(0x6CB6FF) : Theme.hex(0x0969DA)
        codeBG = p.foreground.withAlphaComponent(p.isDark ? 0.08 : 0.06)
        border = p.foreground.withAlphaComponent(0.22)
        quoteBar = p.foreground.withAlphaComponent(0.35)
        headerBG = p.foreground.withAlphaComponent(p.isDark ? 0.10 : 0.07)
        body = .systemFont(ofSize: CGFloat(max(13, Prefs.editorFontSize + 1)))
        mono = Theme.font.withSize(max(11, CGFloat(Prefs.editorFontSize) - 0.5))
    }

    func heading(_ level: Int) -> NSFont {
        let scale: [CGFloat] = [2.0, 1.6, 1.3, 1.15, 1.0, 0.9]
        return .systemFont(ofSize: body.pointSize * scale[min(5, max(0, level - 1))], weight: level <= 2 ? .bold : .semibold)
    }
}

/// Block tree -> attributed string for a read-only NSTextView (TextKit 1: tables, code panels and quote bars are NSTextBlocks).
final class MarkdownRenderer {
    struct Output {
        var text = NSAttributedString()
        var lineMap: [(line: Int, loc: Int)] = []
        var anchors: [String: Int] = [:]
        var images = 0
    }

    private struct Ctx {
        var indent: CGFloat = 0
        var blocks: [NSTextBlock] = []
        var color: NSColor
    }

    let style: MDStyle
    let baseURL: URL?
    var highlightBudget: Int
    var imageBudget = 30
    private let out = NSMutableAttributedString()
    private var lineMap: [(line: Int, loc: Int)] = []
    private var anchors: [String: Int] = [:]
    private var slugCount: [String: Int] = [:]
    private var images = 0

    init(style: MDStyle, baseURL: URL?, highlight: Bool) {
        self.style = style
        self.baseURL = baseURL
        highlightBudget = highlight ? 40_000 : 0
    }

    func render(_ blocks: [MDBlock]) -> Output {
        emit(blocks, Ctx(color: style.fg), lastSpacing: 8)
        return Output(text: out, lineMap: lineMap, anchors: anchors, images: images)
    }

    // MARK: Helpers

    private func note(_ line: Int) {
        if let last = lineMap.last, last.line >= line { return }
        lineMap.append((line, out.length))
    }

    private func pstyle(_ ctx: Ctx, first: CGFloat = 0, head: CGFloat = 0, spacing: CGFloat = 8, before: CGFloat = 0,
                        align: NSTextAlignment = .natural, extra: [NSTextBlock] = [], lineMult: CGFloat = 1.22) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = ctx.indent + first
        p.headIndent = ctx.indent + head
        p.paragraphSpacing = spacing
        p.paragraphSpacingBefore = before
        p.alignment = align
        p.lineHeightMultiple = lineMult
        p.textBlocks = ctx.blocks + extra
        p.tabStops = []
        if head > 0 { p.tabStops = [NSTextTab(textAlignment: .left, location: ctx.indent + head)] }
        return p
    }

    private func append(_ s: NSAttributedString, _ p: NSParagraphStyle) {
        let m = NSMutableAttributedString(attributedString: s)
        m.append(NSAttributedString(string: "\n", attributes: [.font: style.body, .foregroundColor: style.fg]))
        m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
        out.append(m)
    }

    private func tableBlock(cols: Int = 1, row: Int = 0, col: Int = 0, table: NSTextTable? = nil) -> NSTextTableBlock {
        let t = table ?? { let t = NSTextTable(); t.numberOfColumns = cols; t.layoutAlgorithm = .automaticLayoutAlgorithm; return t }()
        return NSTextTableBlock(table: t, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)
    }

    private func slug(_ text: String) -> String {
        var s = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { s.append(ch) } else if ch == " " { s.append("-") }
        }
        let n = slugCount[s, default: 0]
        slugCount[s] = n + 1
        return n == 0 ? s : "\(s)-\(n)"
    }

    // MARK: Blocks

    private func emit(_ blocks: [MDBlock], _ ctx: Ctx, lastSpacing: CGFloat) {
        for (i, b) in blocks.enumerated() {
            let spacing: CGFloat = i == blocks.count - 1 ? lastSpacing : 8
            note(b.line)
            switch b {
            case .heading(let level, let text, _):
                let font = style.heading(level)
                let s = inline(text, font: font, color: ctx.color)
                let id = slug(s.string)
                anchors[id] = out.length
                var extra: [NSTextBlock] = []
                if level <= 2 {
                    let blk = tableBlock()
                    blk.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
                    blk.setBorderColor(style.border, for: .maxY)
                    blk.setWidth(4, type: .absoluteValueType, for: .padding, edge: .maxY)
                    blk.setWidth(level == 1 ? 6 : 4, type: .absoluteValueType, for: .margin, edge: .maxY)
                    extra = [blk]
                }
                append(s, pstyle(ctx, spacing: extra.isEmpty ? 6 : 2, before: out.length == 0 ? 0 : (level <= 2 ? 14 : 10), extra: extra, lineMult: 1.1))
            case .paragraph(let text, _):
                append(inline(text, font: style.body, color: ctx.color), pstyle(ctx, spacing: spacing))
            case .code(let lang, let text, _):
                code(lang: lang, text: text, ctx: ctx)
            case .quote(let inner, _):
                let blk = tableBlock()
                blk.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
                blk.setBorderColor(style.quoteBar, for: .minX)
                blk.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
                blk.setWidth(2, type: .absoluteValueType, for: .padding, edge: .minY)
                blk.setWidth(2, type: .absoluteValueType, for: .padding, edge: .maxY)
                blk.setWidth(spacing, type: .absoluteValueType, for: .margin, edge: .maxY)
                var c = ctx
                c.blocks.append(blk)
                c.color = style.dim
                emit(inner, c, lastSpacing: 2)
            case .list(let ordered, let start, let items, _):
                list(ordered: ordered, start: start, items: items, ctx: ctx, lastSpacing: spacing)
            case .table(let header, let align, let rows, _):
                table(header: header, align: align, rows: rows, ctx: ctx, spacing: spacing)
            case .rule:
                let blk = tableBlock()
                blk.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
                blk.setBorderColor(style.border, for: .maxY)
                blk.setWidth(10, type: .absoluteValueType, for: .margin, edge: .minY)
                blk.setWidth(10, type: .absoluteValueType, for: .margin, edge: .maxY)
                append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 2)]), pstyle(ctx, spacing: 0, extra: [blk]))
            case .html(let text, _):
                html(text, ctx: ctx, spacing: spacing)
            }
        }
    }

    private func code(lang: String, text: String, ctx: Ctx) {
        let blk = tableBlock()
        blk.backgroundColor = style.codeBG
        blk.setWidth(1, type: .absoluteValueType, for: .border)
        blk.setBorderColor(style.border)
        blk.setWidth(8, type: .absoluteValueType, for: .padding)
        blk.setWidth(8, type: .absoluteValueType, for: .margin, edge: .maxY)
        let body = NSMutableAttributedString(string: text.isEmpty ? " " : text,
                                             attributes: [.font: style.mono, .foregroundColor: style.fg])
        if highlightBudget > 0, !lang.isEmpty {
            highlightBudget -= text.utf16.count
            OfflineHighlight.apply(to: body, range: NSRange(location: 0, length: body.length), code: text, lang: lang)
        }
        let p = pstyle(ctx, spacing: 0, extra: [blk], lineMult: 1.15)
        p.lineBreakMode = .byWordWrapping
        append(body, p)
    }

    private func list(ordered: Bool, start: Int, items: [MDItem], ctx: Ctx, lastSpacing: CGFloat) {
        let depth = Int(ctx.indent / 22)
        for (n, item) in items.enumerated() {
            note(item.line)
            let isLast = n == items.count - 1
            let bullet = ["•", "◦", "▪"][depth % 3]
            var marker = ordered ? "\(start + n)." : bullet
            var markerColor = style.dim
            if let task = item.task { marker = task ? "☑" : "☐"; markerColor = task ? style.link : style.dim }
            let spacing: CGFloat = isLast ? lastSpacing : 3
            var rest = item.blocks[...]
            if case .paragraph(let text, _)? = rest.first {
                let s = NSMutableAttributedString(string: marker + "\t", attributes: [.font: style.body, .foregroundColor: markerColor])
                let content = NSMutableAttributedString(attributedString: inline(text, font: style.body, color: ctx.color))
                if item.task == true { content.addAttributes([.foregroundColor: style.dim, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: NSRange(location: 0, length: content.length)) }
                s.append(content)
                append(s, pstyle(ctx, first: 0, head: 22, spacing: item.blocks.count > 1 ? 3 : spacing, lineMult: 1.2))
                rest = rest.dropFirst()
            } else {
                append(NSAttributedString(string: marker, attributes: [.font: style.body, .foregroundColor: markerColor]), pstyle(ctx, spacing: 3))
            }
            var inner = ctx
            inner.indent += 22
            emit(Array(rest), inner, lastSpacing: spacing)
        }
    }

    private func table(header: [String], align: [Int], rows: [[String]], ctx: Ctx, spacing: CGFloat) {
        let t = NSTextTable()
        t.numberOfColumns = header.count
        t.layoutAlgorithm = .automaticLayoutAlgorithm
        t.collapsesBorders = true
        let all = [header] + rows
        for (r, row) in all.enumerated() {
            for (c, cell) in row.enumerated() {
                let blk = NSTextTableBlock(table: t, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                blk.setWidth(1, type: .absoluteValueType, for: .border)
                blk.setBorderColor(style.border)
                blk.setWidth(5, type: .absoluteValueType, for: .padding)
                if r == 0 { blk.backgroundColor = style.headerBG }
                else if r % 2 == 0 { blk.backgroundColor = style.codeBG.withAlphaComponent(0.04) }
                blk.setContentWidth(100.0 / CGFloat(header.count), type: .percentageValueType)
                let font: NSFont = r == 0 ? .systemFont(ofSize: style.body.pointSize, weight: .semibold) : style.body
                let a: NSTextAlignment = align[c] == 1 ? .center : (align[c] == 2 ? .right : .left)
                let p = pstyle(ctx, spacing: 0, align: a, extra: [blk], lineMult: 1.1)
                append(inline(cell, font: font, color: ctx.color), p)
            }
        }
        // spacing after the table
        append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 4)]), pstyle(ctx, spacing: spacing - 4))
    }

    private func html(_ raw: String, ctx: Ctx, spacing: CGFloat) {
        var s = raw
        let centered = s.range(of: #"align\s*=\s*["']?center"#, options: [.regularExpression, .caseInsensitive]) != nil
        var level = 0
        if let m = s.range(of: #"<h([1-6])"#, options: [.regularExpression, .caseInsensitive]) { level = Int(s[m].dropFirst(2)) ?? 0 }
        s = s.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<img\b[^>]*>"#, with: "\u{1}$0\u{1}", options: [.regularExpression, .caseInsensitive])
        // images -> markdown image syntax
        var parts: [String] = []
        for (i, seg) in s.components(separatedBy: "\u{1}").enumerated() {
            if i % 2 == 1 {
                let src = attr("src", in: seg) ?? "", alt = attr("alt", in: seg) ?? "image"
                parts.append("![\(alt)](\(src.replacingOccurrences(of: " ", with: "%20")))")
            } else {
                var t = seg.replacingOccurrences(of: #"<br\s*/?>"#, with: "\u{2028}", options: [.regularExpression, .caseInsensitive])
                t = t.replacingOccurrences(of: #"</?[A-Za-z][^>]*>"#, with: "", options: .regularExpression)
                for (a, b) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&amp;", "&")] { t = t.replacingOccurrences(of: a, with: b) }
                parts.append(t)
            }
        }
        let text = parts.joined().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard !text.isEmpty else { return }
        let font = level > 0 ? style.heading(level) : style.body
        append(inline(text, font: font, color: ctx.color), pstyle(ctx, spacing: spacing, align: centered ? .center : .natural))
    }

    private func attr(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: name + #"\s*=\s*("[^"]*"|'[^']*')"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let m = String(tag[r])
        guard let q = m.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        return String(m[m.index(after: q)...].dropLast())
    }

    // MARK: Inline

    func inline(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let src = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\u{2028}", options: [.regularExpression, .caseInsensitive])
        let opts = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                           failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: src, options: opts) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        let result = NSMutableAttributedString()
        let fm = NSFontManager.shared
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            if let img = run.imageURL {
                result.append(imageAttachment(img, alt: piece, font: font))
                continue
            }
            var f = font
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                f = style.mono.withSize(font.pointSize * 0.92)
                attrs[.backgroundColor] = style.codeBG
            } else {
                if intent.contains(.stronglyEmphasized) { f = fm.convert(f, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { f = fm.convert(f, toHaveTrait: .italicFontMask) }
            }
            if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attrs[.link] = link }
            attrs[.font] = f
            result.append(NSAttributedString(string: piece, attributes: attrs))
        }
        return result
    }

    private func imageAttachment(_ url: URL, alt: String, font: NSFont) -> NSAttributedString {
        let placeholder = { (why: String) -> NSAttributedString in
            NSAttributedString(string: "[\(alt.isEmpty ? why : alt)]", attributes: [.font: font, .foregroundColor: self.style.dim, .obliqueness: 0.15])
        }
        guard url.scheme == nil || url.scheme == "file" else { return placeholder("remote image") }
        guard imageBudget > 0, let file = MarkdownLinks.resolve(url, base: baseURL), let img = MarkdownImages.load(file, maxWidth: 500) else {
            return placeholder("image")
        }
        imageBudget -= 1
        images += 1
        let att = NSTextAttachment()
        att.image = img
        att.bounds = NSRect(x: 0, y: -2, width: img.size.width, height: img.size.height)
        return NSAttributedString(attachment: att)
    }
}

enum MarkdownLinks {
    /// A relative / file link or image path resolved against the Markdown file's folder (fragment and query dropped).
    static func resolve(_ url: URL, base: URL?) -> URL? {
        if url.isFileURL { return url }
        guard url.scheme == nil else { return nil }
        var path = url.path.removingPercentEncoding ?? url.path
        if path.isEmpty { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("./") { path.removeFirst(2) }
        guard let dir = base?.deletingLastPathComponent() else { return nil }
        return dir.appendingPathComponent(path).standardizedFileURL
    }
}

enum MarkdownImages {
    /// Local image downscaled to `maxWidth` points (decoded at no more than 2x that width), nil when unreadable or huge.
    static func load(_ url: URL, maxWidth: CGFloat) -> NSImage? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), (attrs[.size] as? Int ?? 0) < 25_000_000 else { return nil }
        if url.pathExtension.lowercased() == "svg" {
            guard let img = NSImage(contentsOf: url), img.size.width > 0 else { return nil }
            let w = min(maxWidth, img.size.width), h = img.size.height * w / img.size.width
            img.size = NSSize(width: w, height: min(h, 500))
            return img
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? CGFloat, let ph = props[kCGImagePropertyPixelHeight] as? CGFloat, pw > 0 else { return nil }
        let w = min(maxWidth, pw)
        var h = ph * w / pw
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: Int(min(max(pw, ph), max(w * 2, h * 2)))]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        var width = w
        if h > 520 { width = width * 520 / h; h = 520 }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: h))
    }
}

/// The preview pane: a read-only TextKit 1 text view in a scroll view.
final class MarkdownPreviewView: NSView, NSTextViewDelegate {
    let scroll = NSScrollView()
    let textView: NSTextView
    var fileURL: URL?
    /// Relative links to other files (Markdown or any text file) open here.
    var onOpenFile: ((URL) -> Void)?
    private(set) var lineMap: [(line: Int, loc: Int)] = []
    private(set) var anchors: [String: Int] = [:]
    private(set) var lastRenderMs = 0.0
    private(set) var imageCount = 0

    override init(frame: NSRect) {
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        storage.addLayoutManager(lm)
        lm.addTextContainer(tc)
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: tc)
        super.init(frame: frame)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 26, height: 20)
        textView.delegate = self
        textView.allowsUndo = false
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor)])
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func restyle() {
        let s = MDStyle()
        textView.backgroundColor = Theme.background
        scroll.backgroundColor = Theme.background
        textView.linkTextAttributes = [.foregroundColor: s.link, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        textView.selectedTextAttributes = [.backgroundColor: Theme.palette.selection]
    }

    /// Renders on the calling (main) thread; `blocks` come from MarkdownParser (any queue).
    func show(blocks: [MDBlock]) {
        let t0 = CFAbsoluteTimeGetCurrent()
        restyle()
        let r = MarkdownRenderer(style: MDStyle(), baseURL: fileURL, highlight: !PowerState.shared.saver)
        let result = r.render(blocks)
        lineMap = result.lineMap
        anchors = result.anchors
        imageCount = result.images
        textView.textStorage?.setAttributedString(result.text)
        lastRenderMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    func showMessage(_ message: String) {
        restyle()
        lineMap = []; anchors = [:]
        textView.textStorage?.setAttributedString(NSAttributedString(string: message, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.gutter]))
    }

    /// Scrolls so the block at (fractional) source line `line` is at the top, interpolating between rendered blocks.
    func scroll(toSourceLine line: Double) {
        guard let lm = textView.layoutManager, let tc = textView.textContainer, !lineMap.isEmpty else { return }
        func y(_ loc: Int) -> CGFloat {
            let len = textView.textStorage?.length ?? 0
            let g = lm.glyphRange(forCharacterRange: NSRange(location: min(loc, max(0, len - 1)), length: 1), actualCharacterRange: nil)
            return lm.boundingRect(forGlyphRange: g, in: tc).minY + textView.textContainerOrigin.y
        }
        var lo = 0, hi = lineMap.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if Double(lineMap[mid].line) <= line { lo = mid } else { hi = mid - 1 } }
        let a = lineMap[lo]
        var target = y(a.loc)
        if lo + 1 < lineMap.count {
            let b = lineMap[lo + 1]
            let span = Double(b.line - a.line)
            if span > 0 { target += CGFloat(min(1, max(0, (line - Double(a.line)) / span))) * (y(b.loc) - target) }
        } else if line > Double(a.line) {
            target += CGFloat(line - Double(a.line)) * 6
        }
        let maxY = max(0, textView.frame.height - scroll.contentView.bounds.height)
        let clamp = line <= 0 ? 0 : min(max(0, target - 4), maxY)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: clamp))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    var scrollY: CGFloat { scroll.contentView.bounds.origin.y }

    // MARK: Links

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = (link as? URL) ?? (link as? String).flatMap({ URL(string: $0) }) else { return false }
        return open(link: url)
    }

    @discardableResult
    func open(link url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased(), scheme != "file" {
            NSWorkspace.shared.open(url)
            return true
        }
        let fragment = url.fragment
        if url.path.isEmpty, let fragment {            // "#heading"
            if let loc = anchors[fragment.lowercased()] { scrollTo(location: loc) }
            return true
        }
        guard let file = MarkdownLinks.resolve(url, base: fileURL), FileManager.default.fileExists(atPath: file.path) else { NSSound.beep(); return true }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
        if isDir.boolValue { NSWorkspace.shared.activateFileViewerSelecting([file]); return true }
        onOpenFile?(file)
        return true
    }

    func scrollTo(location: Int) {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        let g = lm.glyphRange(forCharacterRange: NSRange(location: location, length: 1), actualCharacterRange: nil)
        let y = lm.boundingRect(forGlyphRange: g, in: tc).minY + textView.textContainerOrigin.y
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y - 8)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
