import AppKit
import SwiftTreeSitter

/// Incremental tree-sitter highlighter. Colours are applied as temporary attributes on the
/// layout manager, so the text storage itself stays untouched (no undo noise, less memory).
final class Highlighter {
    private let parser = Parser()
    private let query: Query?
    private var tree: MutableTree?
    private weak var textView: NSTextView?

    init?(textView: NSTextView, extension ext: String) {
        guard let config = Languages.configuration(forExtension: ext) else { return nil }
        self.textView = textView
        query = config.queries[.highlights]
        do { try parser.setLanguage(config.language) } catch { return nil }
        reparse()
    }

    func reparse() {
        guard let textView else { return }
        tree = parser.parse(textView.string)
        apply()
    }

    func apply() {
        guard let textView, let layout = textView.layoutManager, let tree, let query else { return }
        let text = textView.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        let context = SwiftTreeSitter.Predicate.Context(string: text)
        let ranges = query.execute(in: tree).resolve(with: context).highlights()
        for named in ranges {
            guard let color = Theme.color(for: named.name),
                  NSMaxRange(named.range) <= full.length else { continue }
            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: named.range)
        }
    }
}
