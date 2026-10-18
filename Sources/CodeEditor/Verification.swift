import AppKit

/// Headless verification hooks: CE_SNAPSHOT renders the window (and optionally a picker) to PNGs, then quits.
enum Verification {
    static func render(_ view: NSView, to path: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func scheduleIfRequested(app: AppDelegate) {
        guard AppEnv.value("CE_SNAPSHOT") != nil else { return }
        let shot = AppEnv.value("CE_SNAPSHOT_PATH") ?? "/tmp/ce_snap.png"
        let picker = AppEnv.value("CE_PICKER")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let w = app.active else { return }
            switch picker {
            case "files": w.showGoToFile()
            case "recent": w.showRecentFiles()
            case "actions": w.showFindAction()
            case "everywhere": w.showSearchEverywhere()
            case "projects": app.showRecentProjects(nil)
            case "git": w.toggleGitPanel()
            case "completion":
                if let tv = w.current?.textView {
                    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
                    tv.triggerCompletion(nil)
                }
            default: break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (picker == "git" ? 3.5 : picker == "completion" ? 2.2 : 1.6)) {
            if let w = app.active?.window.contentView { render(w, to: shot) }
            if picker == "completion", let w = app.active, let tab = w.current {
                let popupPath = shot.replacingOccurrences(of: ".png", with: "_popup.png")
                CompletionPopup.shared.snapshot(to: popupPath)
                composeCompletion(window: w.window, tab: tab, baseShot: shot, popupShot: popupPath)
            }
            if picker != nil, picker != "git", picker != "completion" { QuickPicker.snapshot(to: shot.replacingOccurrences(of: ".png", with: "_picker.png")) }
            fputs("snapshot done\n", stderr)
            NSApp.terminate(nil)
        }
    }

    /// Draws the popup snapshot onto the editor render just below the caret, like it appears on screen.
    private static func composeCompletion(window: NSWindow, tab: EditorTab, baseShot: String, popupShot: String) {
        guard let base = NSImage(contentsOfFile: baseShot), let popup = NSImage(contentsOfFile: popupShot),
              let content = window.contentView else { return }
        let length = (tab.textView.string as NSString).length
        let screen = tab.textView.firstRect(forCharacterRange: NSRange(location: length, length: 0), actualRange: nil)
        let caret = content.convert(window.convertFromScreen(screen), from: nil)
        let scale = base.size.width / content.bounds.width
        let margin: CGFloat = 6 * scale
        let pw = popup.size.width - margin * 2, ph = popup.size.height - margin * 2
        let x = caret.minX * scale - 4 * scale
        let y = caret.minY * scale - ph - 3 * scale        // below the caret line (AppKit origin is bottom-left)
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
        popup.draw(in: NSRect(x: x, y: y, width: pw, height: ph),
                   from: NSRect(x: margin, y: margin, width: pw, height: ph), operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: baseShot.replacingOccurrences(of: ".png", with: "_composite.png")))
    }
}
