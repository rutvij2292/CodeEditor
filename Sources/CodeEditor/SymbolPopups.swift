import AppKit

extension CodeSymbol.Kind {
    var iconName: String {
        switch self {
        case .namespace: return "square.stack.3d.up"
        case .class: return "c.square"
        case .interface: return "i.square"
        case .trait: return "t.square"
        case .enum: return "e.square"
        case .function: return "f.square"
        case .method: return "m.square"
        case .property: return "p.square"
        case .constant: return "k.square"
        case .variable: return "v.square"
        }
    }
}

enum FileStructure {
    /// Items in source order; the row of the symbol enclosing `currentLine` is preselected.
    static func items(text: String, fileExtension: String, currentLine: Int,
                      goTo: @escaping (Int) -> Void) -> (items: [PickerItem], preselect: Int) {
        let symbols = SymbolExtractor.symbols(in: text, fileExtension: fileExtension)
            .enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }.map(\.element)
        var preselect = 0
        var items: [PickerItem] = []
        for (i, s) in symbols.enumerated() {
            if s.line <= currentLine && s.kind != .namespace { preselect = i }
            let line = s.line
            items.append(PickerItem(title: s.name, detail: s.container ?? "", symbol: s.kind.iconName,
                                    key: s.name) { goTo(line) })
        }
        return (items, preselect)
    }

    static func present(over window: NSWindow, text: String, fileExtension: String, currentLine: Int,
                        goTo: @escaping (Int) -> Void) {
        let r = items(text: text, fileExtension: fileExtension, currentLine: currentLine, goTo: goTo)
        QuickPicker.present(over: window, placeholder: "File structure", items: r.items, preselect: r.preselect)
    }
}

enum GoToSymbol {
    static func items(entries: [SymbolIndex.Entry], typesOnly: Bool, open: @escaping (SymbolIndex.Entry) -> Void) -> [PickerItem] {
        var types: [PickerItem] = [], others: [PickerItem] = []
        for e in entries {
            let s = e.symbol
            if s.kind == .namespace || (typesOnly && !s.isType) { continue }
            let key: String
            if let c = s.container { key = s.isType ? "\(c)\\\(s.name)" : "\(c)::\(s.name)" } else { key = s.name }
            let detail = [s.container, e.relativePath].compactMap { $0 }.joined(separator: "  ")
            let item = PickerItem(title: s.name, detail: detail, symbol: s.kind.iconName, key: key) { open(e) }
            if s.isType { types.append(item) } else { others.append(item) }
        }
        return types + others
    }

    static func present(over window: NSWindow, index: SymbolIndex, typesOnly: Bool,
                        open: @escaping (URL, Int) -> Void) {
        let show = {
            let items = items(entries: index.entries, typesOnly: typesOnly) { e in
                open(index.root.appendingPathComponent(e.relativePath), e.symbol.line)
            }
            QuickPicker.present(over: window, placeholder: typesOnly ? "Go to class" : "Go to symbol", items: items)
        }
        if index.entries.isEmpty { index.rebuild(completion: show) } else { show(); index.rebuild() }
    }
}
