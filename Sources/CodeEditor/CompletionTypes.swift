import AppKit

enum CompletionKind: String {
    case text, keyword, variable, function, method, property, `class`, interface, `enum`, enumMember, namespace,
         constant, snippet, template, file, field, constructor, value, module, `struct`, typeParameter, color, folder, `operator`
}

struct CompletionItem {
    var label: String                 // shown in the popup and fuzzy-matched
    var insertText: String            // text inserted; if `isSnippet`, LSP snippet syntax ($1, ${2:name}, $0)
    var kind: CompletionKind
    var detail: String = ""           // signature / type, shown right-aligned
    var documentation: String = ""    // plain or markdown, shown in the side panel
    var sortText: String?
    /// Provider tier for ranking among equally good matches (lower = earlier); -1 = derive from `sortText` (see CompletionRanker.tier).
    var priority = -1
    var filterText: String?
    var replaceRange: NSRange?        // UTF-16 range to replace; nil = the identifier prefix before the caret
    var additionalEdits: [(range: NSRange, text: String)] = []   // e.g. auto-added `use` imports (ranges in the ORIGINAL text)
    var isSnippet = false
    var deprecated = false
    /// Providers may fill in documentation/edits lazily (LSP completionItem/resolve); controller calls it once on selection.
    var resolve: ((@escaping (CompletionItem) -> Void) -> Void)?
}

struct CompletionContext {
    let text: String                  // snapshot of the whole document
    let caret: Int                    // UTF-16 offset of the insertion point
    let fileURL: URL
    let fileExtension: String
    let triggerCharacter: String?     // set when auto-triggered by one of the provider's trigger characters
    let isManual: Bool                // Ctrl-Space
    let prefixRange: NSRange          // identifier prefix before the caret (may be empty)
    var prefix: String { (text as NSString).substring(with: prefixRange) }
}

protocol CompletionProvider: AnyObject {
    /// Characters that should auto-open the popup when typed, e.g. ["$", ">", ":", "\\", "@", "<", "."].
    var triggerCharacters: [String] { get }
    /// Called on the main thread. Call `deliver` (any thread) one or more times; each call REPLACES this provider's
    /// previous contribution. `isIncomplete` = ask again as the user keeps typing.
    func complete(_ context: CompletionContext, deliver: @escaping (_ items: [CompletionItem], _ isIncomplete: Bool) -> Void)
    func cancel()
}

/// Providers by file extension; the completion controller merges all providers registered for the file.
enum CompletionRegistry {
    private static var entries: [(extensions: Set<String>?, provider: CompletionProvider)] = []

    /// `extensions` nil = every file type. Lowercased extensions without the dot.
    static func register(_ provider: CompletionProvider, forExtensions extensions: [String]? = nil) {
        entries.append((extensions.map { Set($0.map { $0.lowercased() }) }, provider))
    }

    static func providers(forExtension ext: String) -> [CompletionProvider] {
        let e = ext.lowercased()
        return entries.filter { $0.extensions == nil || $0.extensions!.contains(e) }.map(\.provider)
    }
}
