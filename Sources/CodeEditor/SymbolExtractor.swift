import Foundation
import SwiftTreeSitter

struct CodeSymbol {
    let name: String
    let kind: Kind
    let line: Int           // 1-based
    let container: String?  // enclosing class / namespace name

    enum Kind: String { case namespace, `class`, interface, trait, `enum`, function, method, property, constant, variable }

    var isType: Bool { kind == .class || kind == .interface || kind == .trait || kind == .enum }
}

/// Tree-sitter based outline extraction. Only declaration scaffolding is walked (never function
/// bodies), parse trees and text are dropped as soon as extraction returns.
enum SymbolExtractor {
    private static let lock = NSLock()
    private static var languages: [String: Language] = [:]

    private static func parser(forKey key: String, ext: String) -> Parser? {
        let dict = Thread.current.threadDictionary
        if let p = dict["ce.symbols.parser.\(key)"] as? Parser { return p }
        lock.lock()
        var lang = languages[key]
        if lang == nil, let config = Languages.configuration(forExtension: ext) {
            lang = config.language
            languages[key] = lang
        }
        lock.unlock()
        guard let lang else { return nil }
        let p = Parser()
        do { try p.setLanguage(lang) } catch { return nil }
        dict["ce.symbols.parser.\(key)"] = p
        return p
    }

    /// Loads the grammars on the calling thread (Languages' cache is not thread-safe).
    static func prime() {
        _ = parser(forKey: "php", ext: "php")
        _ = parser(forKey: "js", ext: "js")
    }

    static func symbols(in text: String, fileExtension: String) -> [CodeSymbol] {
        let isPHP: Bool
        switch fileExtension.lowercased() {
        case "php", "phtml": isPHP = true
        case "js", "jsx", "mjs", "cjs": isPHP = false
        default: return []
        }
        guard let parser = parser(forKey: isPHP ? "php" : "js", ext: isPHP ? "php" : "js"),
              let tree = parser.parse(text), let root = tree.rootNode else { return [] }
        var walker = Walker(text: text as NSString)
        if isPHP { walker.php(root, container: nil, namespace: nil) } else { walker.js(root) }
        return walker.out
    }

    private struct Walker {
        let text: NSString
        var out: [CodeSymbol] = []

        func str(_ n: Node) -> String {
            let r = n.range
            guard r.location != NSNotFound, NSMaxRange(r) <= text.length else { return "" }
            return text.substring(with: r)
        }

        func line(_ n: Node) -> Int { Int(n.pointRange.lowerBound.row) + 1 }

        mutating func add(_ nameNode: Node?, _ kind: CodeSymbol.Kind, at: Node, _ container: String?, strip: Bool = false) {
            guard let nameNode else { return }
            var name = str(nameNode)
            if strip, name.hasPrefix("$") { name.removeFirst() }
            guard !name.isEmpty, name.utf16.count < 200 else { return }
            out.append(CodeSymbol(name: name, kind: kind, line: line(at), container: container))
        }

        func named(_ n: Node, _ type: String) -> Node? {
            for i in 0..<n.namedChildCount {
                if let c = n.namedChild(at: i), c.nodeType == type { return c }
            }
            return nil
        }

        // MARK: PHP

        /// Statement containers that can hold declarations without being declarations themselves.
        static let phpTransparent: Set<String> = [
            "program", "compound_statement", "if_statement", "else_clause", "else_if_clause", "return_statement",
            "expression_statement", "object_creation_expression", "assignment_expression", "parenthesized_expression", "ERROR",
        ]

        mutating func php(_ node: Node, container: String?, namespace: String?) {
            var ns = namespace
            for i in 0..<node.namedChildCount {
                guard let n = node.namedChild(at: i), let type = n.nodeType else { continue }
                switch type {
                case "namespace_definition":
                    let nameNode = n.child(byFieldName: "name")
                    if let nameNode { add(nameNode, .namespace, at: n, nil) }
                    let nsName = nameNode.map(str)
                    if let body = n.child(byFieldName: "body") { php(body, container: container, namespace: nsName) }
                    else { ns = nsName }
                case "class_declaration": phpType(n, .class, ns)
                case "interface_declaration": phpType(n, .interface, ns)
                case "trait_declaration": phpType(n, .trait, ns)
                case "enum_declaration": phpType(n, .enum, ns)
                case "anonymous_class":
                    if let body = n.child(byFieldName: "body") { phpMembers(body, "anonymous class") }
                case "function_definition":
                    add(n.child(byFieldName: "name"), .function, at: n, container ?? ns)
                case "const_declaration": phpConst(n, container ?? ns)
                default:
                    if Self.phpTransparent.contains(type) { php(n, container: container, namespace: ns) }
                }
            }
        }

        mutating func phpType(_ n: Node, _ kind: CodeSymbol.Kind, _ ns: String?) {
            guard let nameNode = n.child(byFieldName: "name") else { return }
            add(nameNode, kind, at: n, ns)
            if let body = n.child(byFieldName: "body") { phpMembers(body, str(nameNode)) }
        }

        mutating func phpConst(_ n: Node, _ container: String?) {
            for i in 0..<n.namedChildCount {
                if let e = n.namedChild(at: i), e.nodeType == "const_element" { add(named(e, "name"), .constant, at: e, container) }
            }
        }

        mutating func phpMembers(_ body: Node, _ cls: String) {
            for i in 0..<body.namedChildCount {
                guard let m = body.namedChild(at: i), let type = m.nodeType else { continue }
                switch type {
                case "method_declaration":
                    let nameNode = m.child(byFieldName: "name")
                    add(nameNode, .method, at: m, cls)
                    if nameNode.map(str)?.lowercased() == "__construct", let params = m.child(byFieldName: "parameters") {
                        for j in 0..<params.namedChildCount {
                            if let p = params.namedChild(at: j), p.nodeType == "property_promotion_parameter" {
                                add(p.child(byFieldName: "name"), .property, at: p, cls, strip: true)
                            }
                        }
                    }
                case "property_declaration":
                    for j in 0..<m.namedChildCount {
                        if let e = m.namedChild(at: j), e.nodeType == "property_element" {
                            add(e.child(byFieldName: "name"), .property, at: e, cls, strip: true)
                        }
                    }
                case "const_declaration": phpConst(m, cls)
                case "enum_case": add(m.child(byFieldName: "name"), .constant, at: m, cls)
                default: break
                }
            }
        }

        // MARK: JavaScript

        mutating func js(_ node: Node) {
            for i in 0..<node.namedChildCount {
                guard let n = node.namedChild(at: i), let type = n.nodeType else { continue }
                switch type {
                case "export_statement":
                    if let d = n.child(byFieldName: "declaration") { jsDecl(d) }
                    else if let v = n.child(byFieldName: "value") { jsDecl(v) }
                case "ERROR": js(n)
                default: jsDecl(n)
                }
            }
        }

        mutating func jsDecl(_ n: Node) {
            switch n.nodeType {
            case "class_declaration", "class":
                jsClass(n, nameNode: n.child(byFieldName: "name"))
            case "function_declaration", "generator_function_declaration":
                add(n.child(byFieldName: "name"), .function, at: n, nil)
            case "lexical_declaration", "variable_declaration":
                for i in 0..<n.namedChildCount {
                    guard let d = n.namedChild(at: i), d.nodeType == "variable_declarator",
                          let nameNode = d.child(byFieldName: "name"), nameNode.nodeType == "identifier",
                          let value = d.child(byFieldName: "value") else { continue }
                    switch value.nodeType {
                    case "arrow_function", "function_expression", "function", "generator_function":
                        add(nameNode, .function, at: d, nil)
                    case "class":
                        jsClass(value, nameNode: nameNode, at: d)
                    default: break
                    }
                }
            default: break
            }
        }

        mutating func jsClass(_ n: Node, nameNode: Node?, at: Node? = nil) {
            guard let nameNode else { return }
            add(nameNode, .class, at: at ?? n, nil)
            let cls = str(nameNode)
            guard let body = n.child(byFieldName: "body") else { return }
            for i in 0..<body.namedChildCount {
                guard let m = body.namedChild(at: i) else { continue }
                switch m.nodeType {
                case "method_definition": add(m.child(byFieldName: "name"), .method, at: m, cls)
                case "field_definition": add(m.child(byFieldName: "property"), .property, at: m, cls)
                default: break
                }
            }
        }
    }
}
