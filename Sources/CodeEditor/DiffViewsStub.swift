import AppKit

// PLACEHOLDERS so dependents compile. The agent that owns diff/merge views deletes this file and
// provides real implementations with exactly this API.
final class SideBySideDiffView: NSView {
    /// Two panes (old left, new right), synchronized scrolling, line numbers, coloured added/removed/changed lines.
    func show(old: String, new: String, oldTitle: String, newTitle: String, fileExtension: String) {}
    func nextChange() {}
    func previousChange() {}
    var changeCount: Int { 0 }
}

final class MergeView: NSView {
    /// Called with the final merged text when the user presses Apply.
    var onResolved: ((String) -> Void)?
    /// Three panes: ours (left, read-only), result (centre, editable), theirs (right, read-only).
    func show(base: String?, ours: String, theirs: String, oursTitle: String, theirsTitle: String, fileExtension: String) {}
    func acceptAllOurs() {}
    func acceptAllTheirs() {}
}
