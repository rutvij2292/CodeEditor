import AppKit

/// Editor lifecycle hooks so independent features (completion, LSP, bracket colouring, ...) can attach to
/// tabs without editing EditorTab. Hooks run on the main thread. Observe `NSText.didChangeNotification`
/// on `tab.textView` for edits and `NSView.boundsDidChangeNotification` on `tab.scrollView.contentView` for scrolling.
enum EditorEvents {
    private static var openHooks: [(EditorTab) -> Void] = []
    private static var closeHooks: [(EditorTab) -> Void] = []
    private static var saveHooks: [(EditorTab) -> Void] = []
    private static var willSaveHooks: [(EditorTab, @escaping () -> Void) -> Void] = []

    static func onOpen(_ hook: @escaping (EditorTab) -> Void) { openHooks.append(hook) }
    static func onClose(_ hook: @escaping (EditorTab) -> Void) { closeHooks.append(hook) }
    static func onSave(_ hook: @escaping (EditorTab) -> Void) { saveHooks.append(hook) }

    /// Runs before a save writes to disk. A hook may transform the buffer (format on save) and MUST call `proceed` exactly once
    /// (possibly asynchronously); the next hook, then the write, run after it.
    static func onWillSave(_ hook: @escaping (EditorTab, @escaping () -> Void) -> Void) { willSaveHooks.append(hook) }

    /// Chains the will-save hooks and then calls `write`. EditorTab.save() must route its disk write through this.
    static func notifyWillSave(_ tab: EditorTab, then write: @escaping () -> Void) {
        var remaining = willSaveHooks[...]
        func next() {
            guard let hook = remaining.popFirst() else { write(); return }
            hook(tab, next)
        }
        next()
    }

    static func notifyOpened(_ tab: EditorTab) { openHooks.forEach { $0(tab) } }
    static func notifyClosed(_ tab: EditorTab) { closeHooks.forEach { $0(tab) } }
    static func notifySaved(_ tab: EditorTab) { saveHooks.forEach { $0(tab) } }
}
