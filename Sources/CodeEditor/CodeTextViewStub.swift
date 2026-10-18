import AppKit

// PLACEHOLDER until the editor-actions agent's CodeTextView.swift is merged (then delete this file).
final class CodeTextView: NSTextView {
    enum CommentStyle { case line(String), block(String, String), none }
    var commentStyle: CommentStyle = .line("//")
    var indentUnit = "    "
    func goToLine(_ line: Int, column: Int = 1) {}
    var lineAndColumn: (line: Int, column: Int) { (1, 1) }
    static func commentStyle(forExtension ext: String) -> CommentStyle { .line("//") }
}
