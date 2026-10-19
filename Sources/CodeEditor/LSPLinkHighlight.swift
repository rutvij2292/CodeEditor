import AppKit

/// Cmd-hover link look for symbols (PhpStorm): while Cmd is held, the identifier under the pointer turns link-blue and
/// underlined, but only once the language server confirms it resolves to a definition.
extension LSPSession {
    func updateLinkHighlight(flags: NSEvent.ModifierFlags, point: NSPoint?) {
        guard flags.contains(.command), !flags.contains(.shift), !flags.contains(.option), let tv = textView,
              let point, tv.visibleRect.contains(point), let off = offsetUnderPoint(point),
              instance(supporting: "definitionProvider") != nil else { clearLinkHighlight(); return }
        if tab.map({ LanguageServers.suppressHoverUnderline?($0, off) == true }) == true { clearLinkHighlight(); return }
        let word = wordRange(at: off)
        guard word.length > 0 else { clearLinkHighlight(); return }
        if linkRange == word { return }
        clearLinkHighlight()
        linkToken += 1
        let token = linkToken
        flushChanges()
        let params: [String: Any] = ["textDocument": ["uri": uri], "position": LSPLineTable(text as NSString).lspPosition(off)]
        requestChain("definitionProvider", "textDocument/definition", params, timeout: 3) { [weak self] result, _ in
            guard let self, token == self.linkToken, let tv = self.textView, let lm = tv.layoutManager,
                  !LSPUIParse.locations(from: (try? result.get()) ?? nil).isEmpty,
                  NSMaxRange(word) <= (tv.string as NSString).length else { return }
            // Re-check the modifier is still down and the pointer still over the word.
            guard NSEvent.modifierFlags.contains(.command) else { return }
            lm.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor.linkColor,
                                       .foregroundColor: NSColor.linkColor], forCharacterRange: word)
            self.linkRange = word
            NSCursor.pointingHand.set()
        }
    }

    func clearLinkHighlight() {
        linkToken += 1
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
