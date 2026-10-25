import AppKit

/// Cmd-hover link look for symbols (PhpStorm): while Cmd is held, the identifier under the pointer turns link-blue and
/// underlined, but only once the language server confirms it resolves to a definition.
extension LSPSession {
    /// Test hook: the headless harness cannot hold a real Cmd key.
    static var commandHeldOverride: Bool?
    static func commandHeld() -> Bool { commandHeldOverride ?? NSEvent.modifierFlags.contains(.command) }

    func updateLinkHighlight(flags: NSEvent.ModifierFlags, point: NSPoint?) {
        guard flags.contains(.command), !flags.contains(.shift), !flags.contains(.option), NativeEngines.allowsLinkHighlight(url), let tv = textView,
              let point, tv.visibleRect.contains(point), let off = offsetUnderPoint(point),
              instance(supporting: "definitionProvider") != nil || NativeEngines.handles(url) else { clearLinkHighlight(); return }
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
        let applyRange: (NSRange) -> Void = { [weak self] range in
            guard let self, token == self.linkToken, let tv = self.textView, let lm = tv.layoutManager,
                  NSMaxRange(range) <= (tv.string as NSString).length, Self.commandHeld() else { return }
            lm.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor.linkColor,
                                       .foregroundColor: NSColor.linkColor], forCharacterRange: range)
            self.linkRange = range
            NSCursor.pointingHand.set()
        }
        let applyLink: () -> Void = { applyRange(word) }
        let ownPath = url.standardizedFileURL.path
        // Native engines first, in registry order; a language server confirms only when none has a target elsewhere.
        NativeEngines.lookup(url: url, text: text as NSString, offset: off, stale: { [weak self] in self?.linkToken != token },
                             accept: { hit, _ in hit.targets.contains { !($0.path == ownPath && NSLocationInRange($0.offset, hit.range)) } }) { [weak self] hit, engine in
            guard let self, token == self.linkToken else { return }
            if let hit, let engine { if engine.underlinesHitRange { applyRange(hit.range) } else { applyLink() }; return }
            if self.instance(supporting: "definitionProvider") != nil { self.lspLinkCheck(off: off, token: token, apply: applyLink) }
        }
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
