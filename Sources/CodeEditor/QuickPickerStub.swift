import AppKit

// PLACEHOLDER so dependents compile. The agent that owns the quick picker deletes this file and
// provides the real QuickPicker.swift with exactly this API.
final class QuickPicker {
    /// - items: shown in order when the query is empty; fuzzy-filtered by `key` otherwise.
    /// - preselect: row selected initially (Recent Files uses 1).
    /// - provider: when set, called on every query change and its result replaces `items` entirely
    ///   (used by Search Everywhere to merge files, symbols and actions).
    static func present(over window: NSWindow, placeholder: String, items: [PickerItem],
                        preselect: Int = 0, initialQuery: String = "",
                        provider: ((String) -> [PickerItem])? = nil) {}
    /// Renders the currently presented picker's content view to a PNG (headless verification).
    static func snapshot(to path: String) {}
    static func dismiss() {}
}
