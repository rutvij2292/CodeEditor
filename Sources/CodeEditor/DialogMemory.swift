import AppKit

/// Remembers the size a resizable dialog / sheet was left at (and the divider positions of its split views, via
/// `NSSplitView.autosaveName`), so it opens the same way next time. Size is saved only when a live resize ends.
enum DialogMemory {
    private static func key(_ name: String) -> String { "dialogSize." + name }

    /// Restores the saved content size (never smaller than the window's minimum) and starts saving future resizes.
    static func remember(_ window: NSWindow, as name: String) {
        guard !AppEnv.headless else { return }
        if let s = UserDefaults.standard.string(forKey: key(name)) {
            let size = NSSizeFromString(s)
            if size.width >= 200, size.height >= 150 {
                let min = window.contentMinSize
                window.setContentSize(NSSize(width: max(size.width, min.width), height: max(size.height, min.height)))
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak window] _ in
            guard let window, let size = window.contentView?.frame.size else { return }
            UserDefaults.standard.set(NSStringFromSize(size), forKey: key(name))
        }
    }
}
