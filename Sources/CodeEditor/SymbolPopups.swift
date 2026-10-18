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

    /// Picker rows for vendor hits (kind icon, "vendor · package version · namespace" detail).
    static func vendorItems(_ entries: [VendorEntry], vendor: VendorIndex, open: @escaping (URL, Int) -> Void) -> [PickerItem] {
        entries.map { e in
            let title = e.shortName
            let key = e.member != nil ? "\(e.fqn)::\(title)" : e.fqn
            return PickerItem(title: title, detail: e.detail, symbol: e.kind.iconName, key: key) {
                open(URL(fileURLWithPath: e.path), vendor.declarationLine(of: e))
            }
        }
    }

    static func present(over window: NSWindow, index: SymbolIndex, typesOnly: Bool,
                        open: @escaping (URL, Int) -> Void) {
        let useVendor = VendorIndex.enabled || ProjectIndex.includeVendor
        let vendor = useVendor ? VendorIndex.shared(for: index.root) : nil
        vendor?.refreshIfNeeded()
        let placeholder = typesOnly ? "Go to class" : "Go to symbol"
        let show = {
            let items = items(entries: index.entries, typesOnly: typesOnly) { e in
                open(index.root.appendingPathComponent(e.relativePath), e.symbol.line)
            }
            guard let vendor else { QuickPicker.present(over: window, placeholder: placeholder, items: items); return }
            // Project results first, vendor results (compact on-disk index, searched on demand) after them.
            QuickPicker.present(over: window, placeholder: placeholder, items: [], provider: { text in
                let q = Array(text.lowercased().filter { !$0.isWhitespace })
                let project = q.isEmpty ? Array(items.prefix(200)) : QuickPicker.filter(items, query: q)
                guard q.count >= 2 else { return project }
                let hits = vendor.search(text, limit: 60, typesOnly: typesOnly)
                return Array(project.prefix(140)) + vendorItems(hits, vendor: vendor, open: open)
            })
        }
        if index.entries.isEmpty { index.rebuild(completion: show) } else { show(); index.rebuild() }
    }
}
