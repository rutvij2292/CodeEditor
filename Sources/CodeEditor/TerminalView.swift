import AppKit
import SwiftTerm

enum TerminalCursor: String, CaseIterable {
    case block, beam, underline
    var style: CursorStyle {
        switch self {
        case .block: return .steadyBlock
        case .beam: return .steadyBar
        case .underline: return .steadyUnderline
        }
    }
}

/// ANSI palettes + colours for the terminal (light = PhpStorm Light Lite, dark = Theme.dark).
enum TerminalPalette {
    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    private static func term(_ v: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(red8: UInt16((v >> 16) & 0xFF), green8: UInt16((v >> 8) & 0xFF), blue8: UInt16(v & 0xFF))
    }
    static let lightANSI: [UInt32] = [
        0x222222, 0xC62828, 0x2E7D32, 0xA86400, 0x1565C0, 0x8E24AA, 0x00838F, 0x9E9E9E,
        0x666666, 0xE53935, 0x43A047, 0xC77D00, 0x1E88E5, 0xAB47BC, 0x00ACC1, 0xBDBDBD,
    ]
    static let darkANSI: [UInt32] = [
        0x3F4451, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF,
        0x5C6370, 0xE88991, 0xA9D18E, 0xEBCB8B, 0x7DBDF2, 0xD28DE5, 0x6EC6D0, 0xFFFFFF,
    ]

    static func apply(to view: TerminalView, dark: Bool) {
        let p = dark ? Theme.dark : Theme.light
        view.installColors((dark ? darkANSI : lightANSI).map(term))
        view.nativeBackgroundColor = dark ? Theme.dark.background : hex(0xFFFFFF)
        view.nativeForegroundColor = dark ? Theme.dark.foreground : hex(0x222222)
        view.selectedTextBackgroundColor = dark ? NSColor(srgbRed: 0.27, green: 0.35, blue: 0.50, alpha: 0.75)
                                                : NSColor(srgbRed: 0.72, green: 0.80, blue: 0.95, alpha: 0.8)
        view.caretColor = dark ? hex(0xCCCCCC) : hex(0x222222)
        _ = p
    }
}

/// SwiftTerm view with editor-friendly keys, link handling and activity hooks.
final class CETerminalView: LocalProcessTerminalView {
    var onData: (() -> Void)?
    var onLink: ((String) -> Void)?
    var onRestartKey: (() -> Void)?
    /// Terminal-tab keys (Cmd-T new, Cmd-W close, Shift-Cmd-[ / ] previous / next) while the terminal has focus.
    var onNewTab: (() -> Void)?
    var onCloseTab: (() -> Void)?
    var onCycleTab: ((Int) -> Void)?
    /// BEL received (agents such as Claude Code ring it when they need attention). No sound is played.
    var onBell: (() -> Void)?
    /// Files dropped on the terminal (from the file tree or Finder).
    var onFileDrop: (([URL]) -> Void)?
    var dead = false

    override func bell(source: Terminal) { onBell?() }

    /// Inserts text as a paste (bracketed when the running program asked for it). Never sends Return.
    func pasteText(_ text: String) {
        send(TerminalBridge.pasteBytes(text, bracketed: terminal.bracketedPasteMode))
    }

    func enableFileDrops() { registerForDraggedTypes([.fileURL]) }

    private func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { droppedFiles(sender).isEmpty ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { droppedFiles(sender).isEmpty ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFiles(sender)
        guard !urls.isEmpty, let h = onFileDrop else { return false }
        h(urls)
        return true
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onData?()
    }

    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let h = onLink { h(link) } else { super.requestOpenLink(source: source, link: link, params: params) }
    }

    // Option-drag selects even while an app (tmux, vim, claude) has mouse reporting on.
    override func mouseDown(with event: NSEvent) {
        allowMouseReporting = !event.modifierFlags.contains(.option)
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        allowMouseReporting = true
    }

    /// Terminal-local keys only. Everything else (Cmd-K, Cmd-L, Cmd-W, ...) falls through to the menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else { return false }
        let f = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if dead && !f.contains(.command) { onRestartKey?(); return true }
        guard f.contains(.command), !f.contains(.control), !f.contains(.option) else { return false }
        let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if f == .command {
            switch (ch, event.keyCode) {
            case ("c", _): if selection.active { copy(self) }; return true
            case ("v", _): paste(self); return true
            case ("a", _): selectAll(self); return true
            case (_, 123): send(txt: "\u{01}"); return true      // Cmd-Left: line start
            case (_, 124): send(txt: "\u{05}"); return true      // Cmd-Right: line end
            case (_, 51): send(txt: "\u{15}"); return true       // Cmd-Backspace: kill line
            case ("t", _): if let f = onNewTab { f(); return true }; return false
            case ("w", _): if let f = onCloseTab { f(); return true }; return false
            default: return false
            }
        }
        if f == [.command, .shift], let cycle = onCycleTab {
            if ch == "[" || ch == "{" { cycle(-1); return true }
            if ch == "]" || ch == "}" { cycle(1); return true }
        }
        return false
    }

    /// Whole buffer (scrollback + screen) as text; used for verification.
    func bufferText() -> String {
        String(decoding: terminal.getBufferAsData(), as: UTF8.self)
    }

    var scrollbackLineCount: Int { max(0, bufferText().split(separator: "\n", omittingEmptySubsequences: false).count - terminal.rows) }
}
