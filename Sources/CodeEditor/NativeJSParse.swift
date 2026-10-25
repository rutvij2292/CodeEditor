import Foundation
import SwiftTreeSitter
import TreeSitterJavaScript
import TreeSitterTypeScript
import TreeSitterTSX

/// Parsing for the native JS/TS service. Uses the vendored tree-sitter grammars; trees are short lived (only the last parsed
/// live buffer is kept), everything that outlives a request is the compact `NJSSummary` extracted from a tree.
enum NJSLang: Int { case js, ts, tsx }

enum NJSParsers {
    static func lang(forExtension e: String, vueScriptIsTS: Bool = false) -> NJSLang? {
        switch e {
        case "ts", "mts", "cts": return .ts
        case "tsx": return .tsx
        case "js", "jsx", "mjs", "cjs": return .js
        case "vue": return vueScriptIsTS ? .ts : .js
        default: return nil
        }
    }

    /// Parses `ns` with a throwaway parser inside a private malloc zone (see NJSAlloc); the zone belongs to the returned tree.
    static func parse(_ ns: NSString, lang: NJSLang) -> (MutableTree, NJSZone)? {
        let (tree, zone): (MutableTree?, NJSZone) = NJSAlloc.parse {
            let p = Parser()
            let l: OpaquePointer
            switch lang {
            case .js: l = tree_sitter_javascript()
            case .ts: l = tree_sitter_typescript()
            case .tsx: l = tree_sitter_tsx()
            }
            try? p.setLanguage(l)
            return p.parse(tree: nil as MutableTree?, readBlock: { byteOffset, _ in
                let index = byteOffset / 2
                let length = ns.length
                guard index < length else { return nil }
                var n = min(8192, length - index)
                if index + n < length, UTF16.isLeadSurrogate(ns.character(at: index + n - 1)) { n += 1 }
                var data = Data(count: n * 2)
                data.withUnsafeMutableBytes { raw in
                    if let base = raw.baseAddress?.assumingMemoryBound(to: unichar.self) { ns.getCharacters(base, range: NSRange(location: index, length: n)) }
                }
                return data
            })
        }
        guard let t = tree else { NJSAlloc.destroy(zone); return nil }
        return (t, zone)
    }

    static func drop() {}
}

extension Node {
    var kind: String { nodeType ?? "" }
    func field(_ n: String) -> Node? { child(byFieldName: n) }
    var kids: [Node] {
        var out: [Node] = []
        let c = namedChildCount
        out.reserveCapacity(c)
        for i in 0..<c { if let n = namedChild(at: i) { out.append(n) } }
        return out
    }
    var allKids: [Node] {
        var out: [Node] = []
        for i in 0..<childCount { if let n = child(at: i) { out.append(n) } }
        return out
    }
    func text(_ ns: NSString) -> String {
        let r = range
        guard r.location >= 0, NSMaxRange(r) <= ns.length else { return "" }
        return ns.substring(with: r)
    }
    var start: Int { range.location }
    var end: Int { NSMaxRange(range) }
}

/// A parsed buffer. `parseText` equals `text` except for .vue files, where everything outside `<script>` is blanked
/// (same length, newlines kept) so offsets stay valid.
final class NJSDoc {
    let path: String
    let text: NSString
    private var _tree: MutableTree?
    private var _root: Node?
    private let zone: NJSZone               // every block of the tree lives here; destroyed with the document
    var tree: MutableTree { _tree! }
    var root: Node { _root! }
    let lang: NJSLang
    let isVue: Bool
    let scriptRanges: [NSRange]          // vue: ranges of script content
    private var _summary: NJSSummary?
    private let summaryLock = NSLock()      // the live document is shared by the project queue and the find-usages queue
    var summary: NJSSummary {
        summaryLock.lock(); defer { summaryLock.unlock() }
        if let s = _summary { return s }
        let s = NJSExtractor(doc: self).extract()
        _summary = s
        return s
    }

    /// Bundled / minified code (very long lines): a tree of it costs megabytes and navigating in it is pointless.
    static func looksMinified(_ t: NSString) -> Bool {
        let n = min(t.length, 100_000)
        guard n >= 20_000 else { return false }
        var buf = [unichar](repeating: 0, count: n)
        t.getCharacters(&buf, range: NSRange(location: 0, length: n))
        var lines = 1
        for c in buf where c == 10 { lines += 1 }
        return n / lines > 400
    }

    init?(path: String, text: NSString, maxChars: Int = 3_000_000, skipMinified: Bool = false) {
        if skipMinified, NJSDoc.looksMinified(text) { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        var parseText = text
        var ranges: [NSRange] = []
        var lang: NJSLang? = NJSParsers.lang(forExtension: ext)
        if ext == "vue" {
            let (masked, rs, ts) = NJSDoc.maskVue(text)
            guard !rs.isEmpty else { return nil }
            parseText = masked; ranges = rs
            lang = NJSParsers.lang(forExtension: "vue", vueScriptIsTS: ts)
        }
        guard let l = lang, text.length < maxChars, let (t, z) = NJSParsers.parse(parseText, lang: l) else { return nil }
        guard let r = t.rootNode else { NJSAlloc.destroy(z); return nil }
        self.path = path; self.text = text; self._tree = t; self._root = r; self.zone = z; self.lang = l
        self.isVue = ext == "vue"; self.scriptRanges = ranges
    }

    deinit {
        _root = nil; _tree = nil            // the last references to the tree: its blocks are freed before the zone goes
        NJSAlloc.destroy(zone)
    }

    /// Blanks everything outside `<script ...> ... </script>` blocks.
    static func maskVue(_ text: NSString) -> (NSString, [NSRange], Bool) {
        let n = text.length
        var buf = [unichar](repeating: 32, count: n)
        text.getCharacters(&buf, range: NSRange(location: 0, length: n))
        var keep = [Bool](repeating: false, count: n)
        var ranges: [NSRange] = []
        var isTS = false
        var pos = 0
        while pos < n {
            let open = text.range(of: "<script", options: [.caseInsensitive], range: NSRange(location: pos, length: n - pos))
            if open.location == NSNotFound { break }
            let gt = text.range(of: ">", options: [], range: NSRange(location: NSMaxRange(open), length: n - NSMaxRange(open)))
            if gt.location == NSNotFound { break }
            let tag = text.substring(with: NSRange(location: open.location, length: gt.location - open.location)).lowercased()
            let close = text.range(of: "</script", options: [.caseInsensitive], range: NSRange(location: NSMaxRange(gt), length: n - NSMaxRange(gt)))
            let endLoc = close.location == NSNotFound ? n : close.location
            if !tag.hasSuffix("/") {
                if tag.contains("lang=\"ts\"") || tag.contains("lang='ts'") || tag.contains("lang=\"tsx\"") || tag.contains("lang='tsx'") { isTS = true }
                let r = NSRange(location: NSMaxRange(gt), length: endLoc - NSMaxRange(gt))
                ranges.append(r)
                for i in r.location..<NSMaxRange(r) { keep[i] = true }
            }
            pos = close.location == NSNotFound ? n : NSMaxRange(close)
        }
        for i in 0..<n where !keep[i] && buf[i] != 10 && buf[i] != 13 { buf[i] = 32 }
        for i in 0..<n where !keep[i] && (buf[i] == 10 || buf[i] == 13) { buf[i] = text.character(at: i) }
        return (String(utf16CodeUnits: buf, count: n) as NSString, ranges, isTS)
    }

    func inScript(_ offset: Int) -> Bool {
        !isVue || scriptRanges.contains { offset >= $0.location && offset <= NSMaxRange($0) }
    }

    /// Smallest node covering `offset` (UTF-16), preferring the token that starts at it.
    func leaf(at offset: Int) -> Node? {
        let o = UInt32(max(0, offset)) * 2
        return root.descendant(in: o..<(o + 2))
    }
}

// MARK: Summary model

enum NJSKind: UInt8 {
    case function, `class`, interface, typeAlias, `enum`, namespace, variable, constant, `import`, method, property, getter, setter, enumMember, parameter
    var label: String {
        switch self {
        case .function: return "function"
        case .class: return "class"
        case .interface: return "interface"
        case .typeAlias: return "type"
        case .enum: return "enum"
        case .namespace: return "namespace"
        case .variable: return "variable"
        case .constant: return "const"
        case .import: return "alias"
        case .method: return "method"
        case .property: return "property"
        case .getter: return "getter"
        case .setter: return "setter"
        case .enumMember: return "enum member"
        case .parameter: return "parameter"
        }
    }
}

struct NJSMember {
    var name: String
    var kind: NJSKind
    var loc: Int
    var len: Int
    var declStart: Int
    var sigEnd: Int
    var docStart: Int = -1
    var docEnd: Int = -1
    var isStatic = false
    var typeName: String?            // property type / method return type (simple names only)
    var sub: [NJSMember]?            // namespace members that are themselves classes / interfaces
    var sigText: String?             // `(a: number, b?: string): string` of a function-like member
    var heritage: [String] = []
}

final class NJSSym {
    var name: String
    var kind: NJSKind
    var loc: Int
    var len: Int
    var declStart: Int
    var sigEnd: Int
    var docStart = -1, docEnd = -1
    var keyword: String?                // const / let / var for variables
    var typeName: String?               // variable annotation / `new X()`, function return type
    var valueMembers: [NJSMember] = []  // `ref({...})`: what `.value` holds
    var returnMembers: [NJSMember] = [] // a function whose only return is an object literal
    var sigText: String?                // `<T>(a: number): string` of a function-like declaration (signature help)
    var overload = false                // a body-less `function f(...)` overload signature
    var aliasOf: String?                // `declare const f: typeof g`: f has the type of g (same file)
    var initCall: String?               // `const x = callee(...)`: the callee as written (its declared return type is x's type)
    var heritage: [String] = []         // extends (class: one; interface: several)
    var members: [NJSMember] = []
    var impSource: String?              // import bindings
    var impName: String?                // "default", "*" or the exported name
    var exported = false
    init(name: String, kind: NJSKind, loc: Int, len: Int, declStart: Int, sigEnd: Int) {
        self.name = name; self.kind = kind; self.loc = loc; self.len = len; self.declStart = declStart; self.sigEnd = sigEnd
    }
}

enum NJSExport {
    case local(String)
    case reexport(spec: String, name: String)
    case moduleNS(spec: String)
    case anon(loc: Int, len: Int, declStart: Int, sigEnd: Int, docStart: Int, docEnd: Int)
}

final class NJSSummary {
    var top: [String: [NJSSym]] = [:]
    var order: [NJSSym] = []
    var exports: [String: NJSExport] = [:]
    var stars: [String] = []
    var exportEquals: String?
    var isModule = false
    var commonJS = false
    var stamp: Int64 = 0
    var cost: Int { 200 + order.count * 220 + order.reduce(0) { $0 + $1.members.count * 120 } }
    func add(_ s: NJSSym) { top[s.name, default: []].append(s); order.append(s) }
}
