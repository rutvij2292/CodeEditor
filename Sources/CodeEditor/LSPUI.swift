import AppKit

// MARK: - Markdown (small subset: code spans/blocks, bold, italic, links, headings, bullets)

enum LSPMarkdown {
    static func render(_ markdown: String, fontSize: CGFloat = 12) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: fontSize)
        let bold = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize - 0.5, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: fontSize - 0.5, weight: .bold)
        let fg = Theme.foreground
        let codeBG = Theme.isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.06)
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 3
        para.lineBreakMode = .byWordWrapping
        let codePara = NSMutableParagraphStyle()
        codePara.lineBreakMode = .byWordWrapping
        codePara.paragraphSpacing = 4

        func entity(_ s: String) -> String {
            s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
        }

        func inline(_ line: String, base: NSFont, boldFont: NSFont) {
            let chars = Array(entity(line))
            var i = 0
            var isBold = false, isItalic = false
            var run = ""
            func flush() {
                guard !run.isEmpty else { return }
                let f = isBold ? boldFont : (isItalic ? italic : base)
                out.append(NSAttributedString(string: run, attributes: [.font: f, .foregroundColor: fg, .paragraphStyle: para]))
                run = ""
            }
            while i < chars.count {
                let c = chars[i]
                if c == "`" {
                    var j = i + 1
                    while j < chars.count, chars[j] != "`" { j += 1 }
                    if j < chars.count {
                        flush()
                        out.append(NSAttributedString(string: String(chars[(i + 1)..<j]),
                            attributes: [.font: mono, .foregroundColor: fg, .backgroundColor: codeBG, .paragraphStyle: para]))
                        i = j + 1; continue
                    }
                } else if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                    flush(); isBold.toggle(); i += 2; continue
                } else if c == "*", i + 1 < chars.count, chars[i + 1] != " ", !isItalic || true {
                    // single * emphasis only when it closes later on the line
                    if isItalic { flush(); isItalic = false; i += 1; continue }
                    if chars[(i + 1)...].contains("*") { flush(); isItalic = true; i += 1; continue }
                } else if c == "_", i + 1 < chars.count, chars[i + 1] == "_",
                          isBold || i == 0 || !chars[i - 1].isLetter && !chars[i - 1].isNumber {
                    flush(); isBold.toggle(); i += 2; continue
                } else if c == "_", i + 1 < chars.count, chars[i + 1] != " ", chars[i + 1] != "_",
                          i == 0 || !chars[i - 1].isLetter && !chars[i - 1].isNumber {
                    var j = i + 1
                    while j < chars.count, !(chars[j] == "_" && chars[j - 1] != " "
                                              && (j + 1 == chars.count || !(chars[j + 1].isLetter || chars[j + 1].isNumber))) { j += 1 }
                    if j < chars.count {
                        flush(); isItalic = true
                        let inner = String(chars[(i + 1)..<j])
                        let f = isBold ? boldFont : italic
                        out.append(NSAttributedString(string: inner, attributes: [.font: f, .foregroundColor: fg, .paragraphStyle: para]))
                        isItalic = false; i = j + 1; continue
                    }
                } else if c == "[" {
                    var j = i + 1
                    while j < chars.count, chars[j] != "]" { j += 1 }
                    if j + 1 < chars.count, chars[j + 1] == "(" {
                        var k = j + 2
                        while k < chars.count, chars[k] != ")" { k += 1 }
                        if k < chars.count {
                            flush()
                            let title = String(chars[(i + 1)..<j]), target = String(chars[(j + 2)..<k])
                            var attrs: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: NSColor.linkColor,
                                                                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                                                                        .paragraphStyle: para]
                            if let u = URL(string: target) { attrs[.link] = u }
                            out.append(NSAttributedString(string: title, attributes: attrs))
                            i = k + 1; continue
                        }
                    }
                } else if c == "\\", i + 1 < chars.count, "\\`*_{}[]()#+-.!$<>|".contains(chars[i + 1]) {
                    run.append(chars[i + 1]); i += 2; continue
                }
                run.append(c); i += 1
            }
            flush()
        }

        var inCode = false
        var codeLines: [String] = []
        func endCode() {
            var lines = codeLines
            if lines.first?.trimmingCharacters(in: .whitespaces) == "<?php" { lines.removeFirst() }
            while lines.last?.isEmpty == true { lines.removeLast() }
            if !lines.isEmpty {
                out.append(NSAttributedString(string: lines.joined(separator: "\n") + "\n",
                    attributes: [.font: mono, .foregroundColor: fg, .backgroundColor: codeBG, .paragraphStyle: codePara]))
            }
            codeLines = []
        }
        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if raw.hasPrefix("```") {
                if inCode { endCode() }
                inCode.toggle(); continue
            }
            if inCode { codeLines.append(raw); continue }
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { if out.length > 0, !out.string.hasSuffix("\n\n") { out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4)])) }; continue }
            if t == "---" || t == "***" { continue }
            if t.hasPrefix("#") {
                inline(String(t.drop(while: { $0 == "#" || $0 == " " })), base: bold, boldFont: bold)
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                inline("•  " + t.dropFirst(2), base: body, boldFont: bold)
            } else {
                inline(t, base: body, boldFont: bold)
            }
            out.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        }
        if inCode { endCode() }
        while out.string.hasSuffix("\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        _ = monoBold
        return out
    }
}

// MARK: - Popup window

/// Borderless, non-activating, mouse-transparent panel used for hover and signature help.
final class LSPPopup {
    let panel: NSPanel
    private let box = NSView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private(set) weak var owner: LSPSession?
    static let maxWidth: CGFloat = 560

    var contentView: NSView { box }
    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        label.isSelectable = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.drawsBackground = false
        box.addSubview(label)
        panel.contentView = box
    }

    /// Lays out the content and returns its size (also usable headless for snapshots).
    @discardableResult
    func setContent(_ text: NSAttributedString) -> NSSize {
        let dark = Theme.isDark
        box.layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
                                           : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)).cgColor
        box.layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.18)).cgColor
        box.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        label.attributedStringValue = text
        let pad: CGFloat = 8
        let bounds = text.boundingRect(with: NSSize(width: Self.maxWidth - 2 * pad, height: 10_000),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let w = min(Self.maxWidth, ceil(bounds.width) + 2 * pad + 4)
        label.preferredMaxLayoutWidth = w - 2 * pad
        let fit = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: w - 2 * pad, height: 10_000)) ?? bounds.size
        let h = min(420, ceil(max(fit.height, bounds.height)) + 2 * pad)
        label.frame = NSRect(x: pad, y: pad, width: w - 2 * pad, height: h - 2 * pad)
        box.frame = NSRect(x: 0, y: 0, width: w, height: h)
        return NSSize(width: w, height: h)
    }

    func show(for session: LSPSession, anchor: NSRect) {
        owner = session
        guard let parent = session.textView?.window, parent.isVisible else { return }
        let size = box.frame.size
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 3)
        let screen = parent.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 4000, height: 3000)
        if origin.y < screen.minY { origin.y = anchor.maxY + 3 }
        origin.x = max(screen.minX, min(origin.x, screen.maxX - size.width))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== parent { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)   // non-activating: never takes focus
    }

    func hide() {
        owner = nil
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Renders the popup's content to a PNG (headless verification).
    func snapshot(to path: String) {
        let v = box
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

enum LSPPopups {
    static let hover = LSPPopup()
    static let signature = LSPPopup()
    static func hideAll(for session: LSPSession) {
        if hover.owner === session { hover.hide() }
        if signature.owner === session { signature.hide() }
    }
    static func hideHover() { hover.hide() }
}

// MARK: - Session UI

extension LSPSession {
    func installUI() {
        guard let tv = textView else { return }
        let previousDef = tv.onGoToDefinition
        tv.onGoToDefinition = { [weak self] in
            guard let self, let tv = self.textView else { return }
            if let tab = self.tab, LanguageServers.beforeDefinition?(tab, tv.selectedRange().location) == true { return }
            self.goToDefinition(at: tv.selectedRange().location, fallback: previousDef)
        }
        tv.onQuickDocumentation = { [weak self] in
            guard let self, let tv = self.textView else { return }
            self.showHover(at: tv.selectedRange().location, forceVisible: true)
        }
        tv.onParameterInfo = { [weak self] in self?.showSignature(manual: true, trigger: nil) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        tv.addTrackingArea(area)
        trackingArea = area
        LSPEvents.installMonitor(manager: manager)
    }

    // MARK: Geometry helpers

    private static let identChars: Set<unichar> = {
        var s = Set<unichar>()
        for u in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$\\".utf16 { s.insert(u) }
        return s
    }()

    func wordRange(at offset: Int) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        func isIdent(_ i: Int) -> Bool { i >= 0 && i < ns.length && Self.identChars.contains(ns.character(at: i)) }
        var o = min(offset, ns.length)
        if !isIdent(o), o > 0, isIdent(o - 1) { o -= 1 }
        guard isIdent(o) else { return NSRange(location: o, length: 0) }
        var s = o, e = o
        while isIdent(s - 1) { s -= 1 }
        while isIdent(e) { e += 1 }
        return NSRange(location: s, length: e - s)
    }

    func screenRect(forCharacterRange r: NSRange) -> NSRect {
        textView?.firstRect(forCharacterRange: NSRange(location: r.location, length: max(1, r.length)), actualRange: nil) ?? .zero
    }

    /// Character offset under a point in the text view, only if the point is really over a glyph.
    func offsetUnderPoint(_ p: NSPoint) -> Int? {
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

    // MARK: Mouse (tracking-area owner)

    override func mouseMoved(with event: NSEvent) {
        guard let tv = textView else { return }
        let p = tv.convert(event.locationInWindow, from: nil)
        let off = offsetUnderPoint(p)
        updateLinkHighlight(flags: event.modifierFlags, point: p)
        if let anchor = hoverAnchor, let off, NSLocationInRange(off, anchor) { return }   // still over the same word
        hoverTimer?.invalidate()
        hoverToken += 1
        LSPPopups.hideHover()
        hoverAnchor = nil
        guard let off else { return }
        var cmd = event.modifierFlags.contains(.command)
        if cmd, let tab, LanguageServers.suppressHoverUnderline?(tab, off) == true { cmd = false }   // a navigator owns this token
        let hasDiag = !diagnostics(at: off).isEmpty
        guard cmd || hasDiag else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.showHover(at: off, forceVisible: false, docs: cmd)
        }
    }

    override func mouseExited(with event: NSEvent) {
        clearLinkHighlight()
        hoverTimer?.invalidate()
        hoverAnchor = nil
        LSPPopups.hideHover()
    }

    // MARK: Hover

    func showHover(at offset: Int, forceVisible: Bool, docs: Bool = true) {
        flushChanges()
        hoverToken += 1
        let token = hoverToken
        let word = wordRange(at: offset)
        let diagMessages = diagnostics(at: offset)
        let present: (String?) -> Void = { [weak self] md in
            guard let self, token == self.hoverToken else { return }
            var parts: [String] = []
            for d in diagMessages {
                let label = ["", "error", "warning", "info", "hint"][min(max(d.severity, 1), 4)]
                parts.append("**\(label)**\(d.source.map { " (\($0))" } ?? ""): \(d.message)")
            }
            if let md, !md.isEmpty { parts.append(md) }
            guard !parts.isEmpty else { return }
            let anchorRange = word.length > 0 ? word : NSRange(location: offset, length: 1)
            self.hoverAnchor = anchorRange
            let popup = LSPPopups.hover
            popup.setContent(LSPMarkdown.render(parts.joined(separator: "\n\n")))
            popup.show(for: self, anchor: self.screenRect(forCharacterRange: anchorRange))
        }
        if docs, NativeJS.handles(url) {           // native JS / TS first, the TypeScript server only when it has no answer
            NativeJS.lookupAsync(url: url, text: text as NSString, offset: offset) { [weak self] hit in
                guard let self, token == self.hoverToken else { return }
                if let md = hit?.markdown, !md.isEmpty { present(md) } else { self.lspHover(at: offset, docs: docs, present: present) }
            }
            return
        }
        if docs, NativePHP.handles(url) {          // native PHP first, Intelephense only when it has no answer
            NativePHP.lookupAsync(url: url, text: text as NSString, offset: offset) { [weak self] hit in
                guard let self, token == self.hoverToken else { return }
                if let md = hit?.markdown { present(md) } else { self.lspHover(at: offset, docs: docs, present: present) }
            }
            return
        }
        lspHover(at: offset, docs: docs, present: present)
    }

    private func lspHover(at offset: Int, docs: Bool, present: @escaping (String?) -> Void) {
        let hoverers = instances(supporting: "hoverProvider")
        guard docs, !hoverers.isEmpty else { present(nil); return }
        let table = LSPLineTable(text as NSString)
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": table.lspPosition(offset)]
        // Every server of the file contributes (e.g. HTML + Tailwind: element docs and the generated CSS).
        var answers = [String?](repeating: nil, count: hoverers.count)
        var pending = hoverers.count
        for (i, inst) in hoverers.enumerated() {
            guard let client = inst.client else { pending -= 1; continue }
            client.request("textDocument/hover", params, timeout: 5) { result in
                if case .success(let v) = result, let dict = v as? [String: Any] { answers[i] = LSPUIParse.markdown(from: dict["contents"]) }
                pending -= 1
                if pending == 0 {
                    var seen = Set<String>()
                    let parts = answers.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted }
                    present(parts.isEmpty ? nil : parts.joined(separator: "\n\n---\n\n"))
                }
            }
        }
        if pending == 0 { present(nil) }
    }

    // MARK: Signature help

    func scheduleSignatureCheck() {
        signatureWork?.cancel()
        let inst = instance(supporting: "signatureHelpProvider")
        guard let tv = textView, inst != nil || NativePHP.handles(url) else { return }
        let ns = tv.string as NSString
        let caret = tv.selectedRange().location
        var trigger: String?
        if caret > 0, caret <= ns.length {
            let c = ns.substring(with: NSRange(location: caret - 1, length: 1))
            let sig = inst?.capabilities["signatureHelpProvider"] as? [String: Any]
            let triggers = ((sig?["triggerCharacters"] as? [String]) ?? ["(", ","])
            if triggers.contains(c) { trigger = c }
        }
        if trigger == nil, !LSPPopups.signature.isVisible || LSPPopups.signature.owner !== self { return }
        let work = DispatchWorkItem { [weak self] in self?.showSignature(manual: false, trigger: trigger) }
        signatureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    @objc func selectionChanged(_ n: Notification) {
        guard LSPPopups.signature.isVisible, LSPPopups.signature.owner === self else { return }
        signatureWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showSignature(manual: false, trigger: nil) }
        signatureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// Native PHP answers first (Parameter Info / `(` / `,`); Intelephense is asked only when native cannot resolve the callee.
    func showSignature(manual: Bool, trigger: String?) {
        guard let tv = textView else { return }
        guard NativePHP.handles(url) else { lspSignature(manual: manual, trigger: trigger); return }
        let caret = tv.selectedRange().location
        NativePHP.signatureHelpAsync(url: url, text: tv.string as NSString, caret: caret) { [weak self] outcome in
            guard let self, let tv = self.textView, tv.selectedRange().location == caret else { return }
            switch outcome {
            case .help(let help):
                guard let attributed = LSPUIParse.signature(help.lspPayload) else { LSPPopups.signature.hide(); return }
                let popup = LSPPopups.signature
                popup.setContent(attributed)
                popup.show(for: self, anchor: self.screenRect(forCharacterRange: NSRange(location: max(0, caret - 1), length: 1)))
            case .notInCall: LSPPopups.signature.hide()
            case .unknown: self.lspSignature(manual: manual, trigger: trigger)
            }
        }
    }

    private func lspSignature(manual: Bool, trigger: String?) {
        guard let tv = textView, instance(supporting: "signatureHelpProvider") != nil else { LSPPopups.signature.hide(); return }
        flushChanges()
        let caret = tv.selectedRange().location
        let table = LSPLineTable(tv.string as NSString)
        var context: [String: Any] = ["triggerKind": manual ? 1 : (trigger != nil ? 2 : 3),
                                      "isRetrigger": LSPPopups.signature.isVisible]
        if let trigger { context["triggerCharacter"] = trigger }
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": table.lspPosition(caret), "context": context]
        requestChain("signatureHelpProvider", "textDocument/signatureHelp", params, timeout: 5, accept: { v in
            ((v as? [String: Any])?["signatures"] as? [Any])?.isEmpty == false
        }) { [weak self] result, _ in
            guard let self else { return }
            guard case .success(let v) = result, let dict = v as? [String: Any],
                  let attributed = LSPUIParse.signature(dict) else {
                LSPPopups.signature.hide(); return
            }
            let popup = LSPPopups.signature
            popup.setContent(attributed)
            let line = NSRange(location: max(0, caret - 1), length: 1)
            popup.show(for: self, anchor: self.screenRect(forCharacterRange: line))
        }
    }

    // MARK: Definition

    func goToDefinition(at offset: Int, fallback: (() -> Void)?) {
        guard instance(supporting: "definitionProvider") != nil else { fallback?(); return }
        flushChanges()
        let table = LSPLineTable(text as NSString)
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": table.lspPosition(offset)]
        requestChain("definitionProvider", "textDocument/definition", params, timeout: 8) { [weak self] result, _ in
            guard let self else { return }
            let locations = LSPUIParse.locations(from: (try? result.get()) ?? nil)
            switch locations.count {
            case 0: fallback?()
            case 1: self.open(locations[0])
            default: self.presentLocations(locations)
            }
        }
    }

    private func open(_ loc: LSPLocation) {
        if let handler = LanguageServers.openLocation { handler(loc.url, loc.line + 1, loc.character + 1); return }
        if loc.url.standardizedFileURL == url.standardizedFileURL { textView?.goToLine(loc.line + 1, column: loc.character + 1) }
    }

    private func presentLocations(_ locs: [LSPLocation]) {
        guard let window = textView?.window else { return }
        let root = instances.first?.root.path ?? ""
        let items = locs.prefix(50).map { loc -> PickerItem in
            var rel = loc.url.path
            if rel.hasPrefix(root + "/") { rel = String(rel.dropFirst(root.count + 1)) }
            return PickerItem(title: "\(loc.url.lastPathComponent):\(loc.line + 1)", detail: rel, symbol: "doc.text") { [weak self] in
                self?.open(loc)
            }
        }
        QuickPicker.present(over: window, placeholder: "Go to definition", items: Array(items))
    }
}

// MARK: - Response parsing

struct LSPLocation { let url: URL; let line: Int; let character: Int }

enum LSPUIParse {
    static func locations(from value: Any?) -> [LSPLocation] {
        let items: [[String: Any]]
        if let a = value as? [[String: Any]] { items = a } else if let d = value as? [String: Any] { items = [d] } else { return [] }
        return items.compactMap { d in
            if let uri = d["uri"] as? String, let r = d["range"] as? [String: Any] { return make(uri, r) }
            if let uri = d["targetUri"] as? String,
               let r = (d["targetSelectionRange"] ?? d["targetRange"]) as? [String: Any] { return make(uri, r) }
            return nil
        }
    }

    private static func make(_ uri: String, _ range: [String: Any]) -> LSPLocation? {
        guard let url = URL(string: uri), url.isFileURL, let s = range["start"] as? [String: Any],
              let l = (s["line"] as? NSNumber)?.intValue, let c = (s["character"] as? NSNumber)?.intValue else { return nil }
        return LSPLocation(url: url, line: l, character: c)
    }

    /// MarkupContent | MarkedString | [MarkedString] -> markdown.
    static func markdown(from contents: Any?) -> String? {
        func one(_ v: Any) -> String? {
            if let s = v as? String { return s }
            if let d = v as? [String: Any] {
                guard let value = d["value"] as? String else { return nil }
                if let lang = d["language"] as? String { return "```\(lang)\n\(value)\n```" }
                return d["kind"] as? String == "plaintext" ? value.replacingOccurrences(of: "\n", with: "  \n") : value
            }
            return nil
        }
        if let arr = contents as? [Any] { return arr.compactMap(one).joined(separator: "\n\n") }
        return contents.flatMap(one)
    }

    static func documentation(_ v: Any?) -> String { markdown(from: v) ?? "" }

    /// Signature help -> attributed popup text with the active parameter emphasised.
    static func signature(_ help: [String: Any]) -> NSAttributedString? {
        guard let sigs = help["signatures"] as? [[String: Any]], !sigs.isEmpty else { return nil }
        let activeSig = min(max((help["activeSignature"] as? NSNumber)?.intValue ?? 0, 0), sigs.count - 1)
        let sig = sigs[activeSig]
        guard let label = sig["label"] as? String else { return nil }
        let params = (sig["parameters"] as? [[String: Any]]) ?? []
        let activeParam = (sig["activeParameter"] as? NSNumber)?.intValue ?? (help["activeParameter"] as? NSNumber)?.intValue ?? 0
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let monoBold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let out = NSMutableAttributedString(string: label, attributes: [.font: mono, .foregroundColor: Theme.foreground])
        var paramDoc = ""
        if activeParam >= 0, activeParam < params.count {
            let p = params[activeParam]
            var range: NSRange?
            if let s = p["label"] as? String {
                let r = (label as NSString).range(of: s)
                if r.location != NSNotFound { range = r }
            } else if let a = p["label"] as? [NSNumber], a.count == 2 {
                range = NSRange(location: a[0].intValue, length: max(0, a[1].intValue - a[0].intValue))
            }
            if let range, NSMaxRange(range) <= out.length {
                out.addAttributes([.font: monoBold, .foregroundColor: NSColor.controlAccentColor,
                                   .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.15)], range: range)
            }
            paramDoc = documentation(p["documentation"])
        }
        let doc = documentation(sig["documentation"])
        for extra in [paramDoc, doc] where !extra.isEmpty {
            out.append(NSAttributedString(string: "\n"))
            out.append(LSPMarkdown.render(extra, fontSize: 11.5))
        }
        return out
    }
}

// MARK: - Event monitor (Cmd-click, dismissal)

enum LSPEvents {
    private static var monitor: Any?

    static func installMonitor(manager: LanguageServerManager) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown, .scrollWheel, .flagsChanged]) { event in
            func session() -> LSPSession? {
                guard let view = event.window?.contentView?.hitTest(event.locationInWindow) else { return nil }
                var v: NSView? = view
                while let cur = v, !(cur is CodeTextView) { v = cur.superview }
                guard let tv = v as? CodeTextView else { return nil }
                return manager.sessions.values.first { $0.tab?.textView === tv }
            }
            switch event.type {
            case .flagsChanged:
                for s in manager.sessions.values {
                    guard let tv = s.textView, let w = tv.window, event.window === w else { continue }
                    s.updateLinkHighlight(flags: event.modifierFlags, point: tv.convert(w.mouseLocationOutsideOfEventStream, from: nil))
                }
            case .leftMouseDown:
                for s in manager.sessions.values { s.clearLinkHighlight() }
                LSPPopups.hover.hide()
                if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift),
                   let s = session(), let tv = s.textView,
                   let off = s.offsetUnderPoint(tv.convert(event.locationInWindow, from: nil)) {
                    if let tab = s.tab, LanguageServers.beforeDefinition?(tab, off) == true { return nil }
                    if s.instance(supporting: "definitionProvider") != nil {
                        s.goToDefinition(at: off, fallback: nil)
                        return nil
                    }
                }
            case .scrollWheel:
                LSPPopups.hover.hide(); LSPPopups.signature.hide()
            case .keyDown:
                for s in manager.sessions.values { s.clearLinkHighlight() }
                LSPPopups.hover.hide()
                if event.keyCode == 53 { LSPPopups.signature.hide() }   // Escape
            default: break
            }
            return event
        }
    }
}
