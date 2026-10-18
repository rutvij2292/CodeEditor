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
            default: break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if let w = app.active?.window.contentView { render(w, to: shot) }
            if picker != nil { QuickPicker.snapshot(to: shot.replacingOccurrences(of: ".png", with: "_picker.png")) }
            fputs("snapshot done\n", stderr)
            NSApp.terminate(nil)
        }
    }
}
