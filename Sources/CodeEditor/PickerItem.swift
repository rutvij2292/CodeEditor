import AppKit

/// One row in the QuickPicker popup (Go to File, Recent Files, Find Action, symbols, ...).
struct PickerItem {
    var title: String
    var detail: String
    var symbol: String          // SF Symbol name shown at the left
    var key: String             // text fuzzy-matched against the query (defaults to title)
    var run: () -> Void

    init(title: String, detail: String = "", symbol: String = "doc.text", key: String? = nil,
         run: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.key = key ?? title
        self.run = run
    }
}
