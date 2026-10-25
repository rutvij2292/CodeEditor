import Foundation

// Data model of the native Python engine (see NativePy.swift). A PyFile is a compact outline of one .py file (scopes, bindings,
// small expression trees); the syntax tree itself is thrown away after the outline is built. Nothing here holds source text except
// short signature headers, so a few thousand files fit in a few MB (NativePyCache caps it).

enum PyKind: UInt8 { case cls, fn, variable, param, imp, attr }

/// Small expression tree: only the shapes the type inference understands. Everything else is `.unknown`.
indirect enum PyExpr {
    case name(String, Int)                 // identifier, UTF-16 offset
    case attr(PyExpr, String, Int)         // base.attr (offset of attr)
    case call(PyExpr, PyExpr?, Int)        // callee, first argument, offset of the call node
    case sub(PyExpr, [PyExpr])             // base[a, b] (generic annotations)
    case str(String)                       // plain string literal (forward reference in annotations)
    case lit(String)                       // literal of a builtin type (int, str, list, None ...)
    case union([PyExpr])                   // a | b
    case either(PyExpr, PyExpr)            // a if c else b / a or b
    case await(PyExpr)
    case enter(PyExpr)                     // `with expr as name`
    case exc(PyExpr)                       // `except Expr as name`
    case iter(PyExpr)                      // `for name in expr`
    case unknown
}

struct PyParam {
    var name: String
    var nameOff: Int
    var annotation: PyExpr?
    var star: UInt8 = 0                    // 1 = *args, 2 = **kwargs
    var defaultText: String?
}

final class PySym {
    let name: String
    var kind: PyKind
    let path: String
    var nameOff: Int
    var declStart = 0, declEnd = 0         // the whole statement / definition
    weak var scope: PyScope?               // scope the binding lives in
    var inner: PyScope?                    // body scope of classes / functions
    var header: String?                    // `def f(a, b) -> int` / `class C(Base)`
    var bases: [PyExpr] = []
    var decorators: [String] = []
    var params: [PyParam] = []
    var returns: PyExpr?
    var retExprs: [PyExpr] = []
    var annotation: PyExpr?
    var value: PyExpr?
    var docRange: NSRange?
    var paramIndex = -1
    var isAsync = false
    var hasYield = false
    var isAugmented = false
    // import bindings
    var impModule = "", impLevel = 0, impName: String?

    init(name: String, kind: PyKind, path: String, nameOff: Int) {
        self.name = name; self.kind = kind; self.path = path; self.nameOff = nameOff
    }

    func hasDecorator(_ names: String...) -> Bool {
        decorators.contains { d in names.contains { d == $0 || d.hasSuffix("." + $0) } }
    }
    var isProperty: Bool { hasDecorator("property", "cached_property", "abstractproperty") }
    var isStatic: Bool { hasDecorator("staticmethod") }
    var isClassMethod: Bool { hasDecorator("classmethod") }
    var isDefLike: Bool { kind == .cls || kind == .fn }
}

final class PyScope {
    enum Kind: UInt8 { case module, cls, fn, lambda, comp }
    let kind: Kind
    var start: Int, end: Int
    weak var parent: PyScope?
    weak var owner: PySym?
    var table: [String: [PySym]] = [:]
    var order: [PySym] = []
    var attrs: [String: [PySym]] = [:]      // class scopes: `self.x = ...` assignments in methods
    var attrOrder: [PySym] = []
    var children: [PyScope] = []
    var globals: Set<String> = []
    var nonlocals: Set<String> = []
    var stars: [(module: String, level: Int)] = []
    var dunderAll: [String]?
    var usesLocals = false

    init(kind: Kind, start: Int, end: Int, parent: PyScope?) {
        self.kind = kind; self.start = start; self.end = end; self.parent = parent
    }

    func add(_ s: PySym) {
        s.scope = self
        table[s.name, default: []].append(s)
        order.append(s)
    }
    func addAttr(_ s: PySym) {
        s.scope = self
        attrs[s.name, default: []].append(s)
        attrOrder.append(s)
    }

    /// Innermost scope containing `offset`.
    func innermost(at offset: Int) -> PyScope {
        for c in children where offset >= c.start && offset < c.end { return c.innermost(at: offset) }
        return self
    }
}

final class PyFile {
    let path: String
    let root: PyScope
    var size = 0
    var mtime: TimeInterval = 0
    var rawSize = 0
    var lineStarts: [Int32] = [0]
    var declByOff: [Int: PySym] = [:]
    var symCount = 0
    var isStub: Bool { path.hasSuffix(".pyi") }
    var isInit: Bool { let n = (path as NSString).lastPathComponent; return n == "__init__.py" || n == "__init__.pyi" }
    var docRange: NSRange?
    var live: NSString?                      // the buffer text, only for the live (unsaved) outline of the open file
    var lastUse = 0
    var cost: Int { 400 + symCount * 220 + lineStarts.count * 4 }

    init(path: String, root: PyScope) { self.path = path; self.root = root }

    func position(of offset: Int) -> (line: Int, col: Int) {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if Int(lineStarts[mid]) <= offset { lo = mid } else { hi = mid - 1 }
        }
        return (lo + 1, offset - Int(lineStarts[lo]) + 1)
    }

    func target(_ s: PySym) -> NPTarget {
        let p = position(of: s.nameOff)
        return NPTarget(path: path, offset: s.nameOff, line: p.line, column: p.col)
    }
    func moduleTarget() -> NPTarget { NPTarget(path: path, offset: 0, line: 1, column: 1) }
}
