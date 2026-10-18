import AppKit

/// Editor lifecycle hooks so independent features (completion, LSP, bracket colouring, ...) can attach to
/// tabs without editing EditorTab. Hooks run on the main thread. Observe `NSText.didChangeNotification`
/// on `tab.textView` for edits and `NSView.boundsDidChangeNotification` on `tab.scrollView.contentView` for scrolling.
enum EditorEvents {
    private static var openHooks: [(EditorTab) -> Void] = []
    private static var closeHooks: [(EditorTab) -> Void] = []
    private static var saveHooks: [(EditorTab) -> Void] = []

    static func onOpen(_ hook: @escaping (EditorTab) -> Void) { openHooks.append(hook) }
    static func onClose(_ hook: @escaping (EditorTab) -> Void) { closeHooks.append(hook) }
    static func onSave(_ hook: @escaping (EditorTab) -> Void) { saveHooks.append(hook) }

    static func notifyOpened(_ tab: EditorTab) { openHooks.forEach { $0(tab) } }
    static func notifyClosed(_ tab: EditorTab) { closeHooks.forEach { $0(tab) } }
    static func notifySaved(_ tab: EditorTab) { saveHooks.forEach { $0(tab) } }
}
