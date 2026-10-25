import AppKit

/// Cmd-hover link look for symbols (PhpStorm): while Cmd is held, the identifier under the pointer turns link-blue and
/// underlined, but only once the language server confirms it resolves to a definition.
extension LSPSession {
    /// Test hook: the headless harness cannot hold a real Cmd key.
    static var commandHeldOverride: Bool?
    static func commandHeld() -> Bool { commandHeldOverride ?? NSEvent.modifierFlags.contains(.command) }

    func updateLinkHighlight(flags: NSEvent.ModifierFlags, point: NSPoint?) {
        guard flags.contains(.command), !flags.contains(.shift), !flags.contains(.option), let tv = textView,
              let point, tv.visibleRect.contains(point), let off = offsetUnderPoint(point),
              instance(supporting: "definitionProvider") != nil || NativeLang.handles(url) || NativeWeb.handles(url) || NativeJS.handles(url) else { clearLinkHighlight(); return }
        if tab.map({ LanguageServers.suppressHoverUnderline?($0, off) == true }) == true { clearLinkHighlight(); return }
        let word = wordRange(at: off)
        guard word.length > 0 else { clearLinkHighlight(); return }
        if linkRange == word || linkPending == word { return }   // restarting on every mouseMoved would discard each answer as stale
        clearLinkHighlight()
        linkToken += 1
        linkPending = word
        linkRequests += 1
        let token = linkToken
        flushChanges()
        let applyLink: () -> Void = { [weak self] in
            guard let self, token == self.linkToken, let tv = self.textView, let lm = tv.layoutManager,
                  NSMaxRange(word) <= (tv.string as NSString).length, Self.commandHeld() else { return }
            lm.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor.linkColor,
                                       .foregroundColor: NSColor.linkColor], forCharacterRange: word)
            self.linkRange = word
            NSCursor.pointingHand.set()
        }
        if NativeLang.handles(url) {            // native engine first (PHP, Python); a language server confirms only when native has no target
            NativeLang.lookupAsync(url: url, text: text as NSString, offset: off) { [weak self] hit in
                guard let self, token == self.linkToken else { return }
                if let hit, hit.targets.contains(where: { !($0.path == self.url.standardizedFileURL.path && NSLocationInRange($0.offset, hit.range)) }) { applyLink(); return }
                if NativeWeb.handles(self.url) {
                    NativeWeb.lookupAsync(url: self.url, text: self.text as NSString, offset: off) { [weak self] web in
                        guard let self, token == self.linkToken else { return }
                        if let web, web.targets.contains(where: { !($0.path == self.url.standardizedFileURL.path && NSLocationInRange($0.offset, web.range)) }) { applyLink(); return }
                        if self.instance(supporting: "definitionProvider") != nil { self.lspLinkCheck(off: off, token: token, apply: applyLink) }
                    }
                    return
                }
                if self.instance(supporting: "definitionProvider") != nil { self.lspLinkCheck(off: off, token: token, apply: applyLink) }
            }
            return
        }
        if NativeWeb.handles(url) {            // native CSS / HTML first; the CSS / HTML server confirms only when native has no target
            NativeWeb.lookupAsync(url: url, text: text as NSString, offset: off) { [weak self] hit in
                guard let self, token == self.linkToken else { return }
                if let hit, hit.targets.contains(where: { !($0.path == self.url.standardizedFileURL.path && NSLocationInRange($0.offset, hit.range)) }) { applyLink(); return }
                if self.instance(supporting: "definitionProvider") != nil { self.lspLinkCheck(off: off, token: token, apply: applyLink) }
            }
            return
        }
        if NativeJS.handles(url) {             // native JS / TS first; the TypeScript server confirms only when native has no target
            NativeJS.lookupAsync(url: url, text: text as NSString, offset: off) { [weak self] hit in
                guard let self, token == self.linkToken else { return }
                if let hit, hit.targets.contains(where: { !($0.path == self.url.standardizedFileURL.path && NSLocationInRange($0.offset, hit.range)) }) { applyLink(); return }
                if self.instance(supporting: "definitionProvider") != nil { self.lspLinkCheck(off: off, token: token, apply: applyLink) }
            }
            return
        }
        lspLinkCheck(off: off, token: token, apply: applyLink)
    }

    private func lspLinkCheck(off: Int, token: Int, apply: @escaping () -> Void) {
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": LSPLineTable(text as NSString).lspPosition(off)]
        requestChain("definitionProvider", "textDocument/definition", params, timeout: 3) { [weak self] result, _ in
            guard let self, token == self.linkToken, !LSPUIParse.locations(from: (try? result.get()) ?? nil).isEmpty else { return }
            apply()    // re-checks the modifier is still down and the pointer still over the word
        }
    }

    func clearLinkHighlight() {
        linkToken += 1
        linkPending = nil
        guard let r = linkRange else { return }
        linkRange = nil
        if let tv = textView, let lm = tv.layoutManager {
            let clamped = NSIntersectionRange(r, NSRange(location: 0, length: (tv.string as NSString).length))
            if clamped.length > 0 {
                for k in [NSAttributedString.Key.underlineStyle, .underlineColor, .foregroundColor] {
                    lm.removeTemporaryAttribute(k, forCharacterRange: clamped)
                }
            }
        }
        NSCursor.iBeam.set()
    }
}
