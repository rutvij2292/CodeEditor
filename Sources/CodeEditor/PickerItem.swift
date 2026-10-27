import AppKit

/// One row in the QuickPicker popup (Go to File, Recent Files, Find Action, symbols, ...).
struct PickerItem {
    var title: String
    var detail: String
    var symbol: String          // SF Symbol name shown at the left
    var key: String             // text fuzzy-matched against the query (defaults to title)
    var run: () -> Void
    /// Search Everywhere: the full path shown in the footer, and the alternative for Shift-Return ("Open In Right Split").
    var footer = ""
    var runSplit: (() -> Void)?
    /// Icon colour (nil = the muted gutter colour) and a semibold title, e.g. File Structure types.
    var tint: NSColor?
    var strong = false

    init(title: String, detail: String = "", symbol: String = "doc.text", key: String? = nil,
         run: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.key = key ?? title
        self.run = run
    }
}

/// One tab of the tabbed picker (Search Everywhere): its rows for a query; the flag is "Include non-project items".
struct PickerTab {
    let title: String
    let provider: (_ query: String, _ includeNonProject: Bool) -> [PickerItem]
}
