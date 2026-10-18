import AppKit

// PLACEHOLDER until the symbols agent's Symbols*.swift files are merged (then delete this file).
struct CodeSymbol { let name: String; let line: Int }
final class SymbolIndex {
    init(root: URL, files: @escaping () -> [String]) {}
    func rebuild(completion: (() -> Void)? = nil) { completion?() }
    func update(file relativePath: String) {}
}
enum FileStructure {
    static func present(over window: NSWindow, text: String, fileExtension: String, currentLine: Int,
                        goTo: @escaping (Int) -> Void) {}
}
enum GoToSymbol {
    static func present(over window: NSWindow, index: SymbolIndex, typesOnly: Bool,
                        open: @escaping (URL, Int) -> Void) {}
}
