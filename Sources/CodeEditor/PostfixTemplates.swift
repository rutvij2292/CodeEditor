import AppKit

/// Postfix templates (PhpStorm / WebStorm style): `$items.foreach` + Tab / Return becomes `foreach ($items as $item) { }`,
/// `$user->name.if`, `foo($x).var`, `$x.dd`, `$x.isset` ... A static table and one completion provider; nothing is cached or indexed.
/// The expression in front of the dot is found by a bounded backwards scan (identifier / variable chain, `->`, `::`, balanced `()` `[]`).
enum PostfixTemplates {
    struct Template {
        var name: String
        var detail: String
        /// Live-template body (see LiveTemplates.snippet); `\u{1}` marks the expression.
        var body: String
        var vars: [String: String] = [:]
    }

    static let expr = "\u{1}"

    static let php: [Template] = [
        Template(name: "foreach", detail: "foreach ($expr as $item)", body: "foreach (\(expr) as $$ITEM$) {\n\t$END$\n}", vars: ["ITEM": "item"]),
        Template(name: "forek", detail: "foreach ($expr as $key => $value)", body: "foreach (\(expr) as $$KEY$ => $$VALUE$) {\n\t$END$\n}", vars: ["KEY": "key", "VALUE": "value"]),
        Template(name: "for", detail: "for ($i = 0; $i < count($expr); $i++)", body: "for ($$i = 0; $$i < count(\(expr)); $$i++) {\n\t$END$\n}"),
        Template(name: "while", detail: "while ($expr)", body: "while (\(expr)) {\n\t$END$\n}"),
        Template(name: "if", detail: "if ($expr)", body: "if (\(expr)) {\n\t$END$\n}"),
        Template(name: "else", detail: "if (!$expr)", body: "if (!\(expr)) {\n\t$END$\n}"),
        Template(name: "not", detail: "!$expr", body: "!\(expr)$END$"),
        Template(name: "null", detail: "if ($expr === null)", body: "if (\(expr) === null) {\n\t$END$\n}"),
        Template(name: "notnull", detail: "if ($expr !== null)", body: "if (\(expr) !== null) {\n\t$END$\n}"),
        Template(name: "isset", detail: "isset($expr)", body: "isset(\(expr))$END$"),
        Template(name: "empty", detail: "empty($expr)", body: "empty(\(expr))$END$"),
        Template(name: "count", detail: "count($expr)", body: "count(\(expr))$END$"),
        Template(name: "var", detail: "$name = $expr;", body: "$$NAME$ = \(expr);$END$", vars: ["NAME": "value"]),
        Template(name: "return", detail: "return $expr;", body: "return \(expr);$END$"),
        Template(name: "throw", detail: "throw $expr;", body: "throw \(expr);$END$"),
        Template(name: "tn", detail: "throw new Exception($expr);", body: "throw new $EXCEPTION$(\(expr));$END$", vars: ["EXCEPTION": "\\Exception"]),
        Template(name: "echo", detail: "echo $expr;", body: "echo \(expr);$END$"),
        Template(name: "dd", detail: "dd($expr);", body: "dd(\(expr));$END$"),
        Template(name: "dump", detail: "dump($expr);", body: "dump(\(expr));$END$"),
        Template(name: "log", detail: "Log::info($expr);", body: "Log::info(\(expr));$END$"),
        Template(name: "json", detail: "json_encode($expr)", body: "json_encode(\(expr))$END$"),
        Template(name: "coll", detail: "collect($expr)", body: "collect(\(expr))$END$"),
        Template(name: "arr", detail: "(array) $expr", body: "(array) \(expr)$END$"),
        Template(name: "str", detail: "(string) $expr", body: "(string) \(expr)$END$"),
        Template(name: "int", detail: "(int) $expr", body: "(int) \(expr)$END$"),
        Template(name: "float", detail: "(float) $expr", body: "(float) \(expr)$END$"),
        Template(name: "bool", detail: "(bool) $expr", body: "(bool) \(expr)$END$"),
        Template(name: "cls", detail: "get_class($expr)", body: "get_class(\(expr))$END$"),
        Template(name: "par", detail: "($expr)", body: "(\(expr))$END$"),
        Template(name: "trim", detail: "trim($expr)", body: "trim(\(expr))$END$"),
        Template(name: "lower", detail: "strtolower($expr)", body: "strtolower(\(expr))$END$"),
        Template(name: "upper", detail: "strtoupper($expr)", body: "strtoupper(\(expr))$END$"),
        Template(name: "unset", detail: "unset($expr);", body: "unset(\(expr));$END$"),
        Template(name: "tern", detail: "$expr ? a : b", body: "\(expr) ? $A$ : $B$$END$", vars: ["A": "a", "B": "b"]),
        Template(name: "coalesce", detail: "$expr ?? default", body: "\(expr) ?? $DEFAULT$$END$", vars: ["DEFAULT": "null"]),
        Template(name: "sw", detail: "switch ($expr)", body: "switch (\(expr)) {\n\tcase $VALUE$:\n\t\t$END$\n\t\tbreak;\n}", vars: ["VALUE": "value"]),
        Template(name: "match", detail: "match ($expr)", body: "match (\(expr)) {\n\t$END$\n}"),
    ]

    static let js: [Template] = [
        Template(name: "log", detail: "console.log(expr)", body: "console.log(\(expr))$END$"),
        Template(name: "const", detail: "const name = expr", body: "const $NAME$ = \(expr)$END$", vars: ["NAME": "value"]),
        Template(name: "let", detail: "let name = expr", body: "let $NAME$ = \(expr)$END$", vars: ["NAME": "value"]),
        Template(name: "var", detail: "const name = expr", body: "const $NAME$ = \(expr)$END$", vars: ["NAME": "value"]),
        Template(name: "return", detail: "return expr", body: "return \(expr)$END$"),
        Template(name: "throw", detail: "throw expr", body: "throw \(expr)$END$"),
        Template(name: "if", detail: "if (expr)", body: "if (\(expr)) {\n\t$END$\n}"),
        Template(name: "else", detail: "if (!expr)", body: "if (!\(expr)) {\n\t$END$\n}"),
        Template(name: "not", detail: "!expr", body: "!\(expr)$END$"),
        Template(name: "null", detail: "if (expr === null)", body: "if (\(expr) === null) {\n\t$END$\n}"),
        Template(name: "notnull", detail: "if (expr !== null)", body: "if (\(expr) !== null) {\n\t$END$\n}"),
        Template(name: "foreach", detail: "for (const item of expr)", body: "for (const $ITEM$ of \(expr)) {\n\t$END$\n}", vars: ["ITEM": "item"]),
        Template(name: "forof", detail: "for (const item of expr)", body: "for (const $ITEM$ of \(expr)) {\n\t$END$\n}", vars: ["ITEM": "item"]),
        Template(name: "forin", detail: "for (const key in expr)", body: "for (const $KEY$ in \(expr)) {\n\t$END$\n}", vars: ["KEY": "key"]),
        Template(name: "await", detail: "await expr", body: "await \(expr)$END$"),
        Template(name: "typeof", detail: "typeof expr", body: "typeof \(expr)$END$"),
        Template(name: "json", detail: "JSON.stringify(expr)", body: "JSON.stringify(\(expr))$END$"),
        Template(name: "par", detail: "(expr)", body: "(\(expr))$END$"),
        Template(name: "tern", detail: "expr ? a : b", body: "\(expr) ? $A$ : $B$$END$", vars: ["A": "a", "B": "b"]),
    ]

    static let phpExtensions: Set<String> = ["php", "phtml"]
    static let jsExtensions: Set<String> = ["js", "jsx", "ts", "tsx", "mjs", "cjs", "mts", "cts", "vue"]

    // MARK: Expression in front of the dot

    /// Start offset of the expression that ends right before the `.` at `dot`, nil when there is none (or it is not a convincing
    /// expression: a bare word, a number, a string). `js`: `.` also separates members.
    static func exprStart(_ ns: NSString, dot: Int, js: Bool) -> Int? {
        guard dot > 0, dot <= ns.length else { return nil }
        let lineStart = max(CompletionLex.lineStart(ns, dot), dot - 400)
        var i = dot
        var sawVariableOrCall = false
        var steps = 0
        while i > lineStart, steps < 200 {
            steps += 1
            let c = ns.character(at: i - 1)
            if CompletionLex.isIdent(c) || c == 36 || c == 92 { if c == 36 { sawVariableOrCall = true }; i -= 1; continue }
            if c == 41 || c == 93 {                                    // ) ]  -> jump to the matching opener
                var depth = 0
                var j = i - 1
                var found = -1
                while j >= lineStart {
                    let d = ns.character(at: j)
                    if d == 41 || d == 93 { depth += 1 } else if d == 40 || d == 91 { depth -= 1; if depth == 0 { found = j; break } }
                    j -= 1
                }
                guard found >= 0 else { return nil }
                if c == 41 { sawVariableOrCall = true }
                i = found
                continue
            }
            if c == 62, i - 2 >= lineStart, ns.character(at: i - 2) == 45 {   // ->
                i -= 2
                if i - 1 >= lineStart, ns.character(at: i - 1) == 63 { i -= 1 }
                continue
            }
            if c == 58, i - 2 >= lineStart, ns.character(at: i - 2) == 58 { i -= 2; sawVariableOrCall = true; continue }   // ::
            if js, c == 46, i - 2 >= lineStart, CompletionLex.isIdent(ns.character(at: i - 2)) || ns.character(at: i - 2) == 41 || ns.character(at: i - 2) == 93 { i -= 1; continue }
            break
        }
        guard i < dot else { return nil }
        let first = ns.character(at: i)
        if first >= 48 && first <= 57 { return nil }                  // number
        if !js, !sawVariableOrCall { return nil }                      // PHP: `foo.bar` is a concatenation of constants, not a postfix target
        if js, !sawVariableOrCall {
            let word = ns.substring(with: NSRange(location: i, length: dot - i))
            let reserved: Set<String> = ["return", "await", "typeof", "new", "throw", "const", "let", "var", "in", "of", "else", "case", "default", "yield", "delete", "void", "if", "for"]
            if reserved.contains(word) { return nil }
        }
        return i
    }

    // MARK: Provider

    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        let ext = ctx.fileExtension.lowercased()
        let isPHP = phpExtensions.contains(ext), isJS = jsExtensions.contains(ext)
        guard isPHP || isJS else { return [] }
        let ns = ctx.text as NSString
        let p = ctx.prefixRange.location
        guard !ctx.prefix.isEmpty, p >= 2, ns.character(at: p - 1) == 46 else { return [] }
        // inside a string or a comment: no templates; in Blade only inside `{{ }}` / `@php` (PHP region)
        let st = CompletionLex.state(ctx)
        guard st == .code else { return [] }
        let info = CompletionLex.info(ctx)
        let useJS: Bool
        switch info.region {
        case .php, .bladeExpr: useJS = false
        case .js: useJS = true
        default: return []
        }
        if useJS && !isJS && !(isPHP && info.region == .js) { return [] }
        if !useJS && !isPHP { return [] }
        guard let start = exprStart(ns, dot: p - 1, js: useJS) else { return [] }
        let exprText = ns.substring(with: NSRange(location: start, length: p - 1 - start))
        guard !exprText.isEmpty, exprText.utf16.count <= 300 else { return [] }
        let escaped = exprText.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "}", with: "\\}")
        let range = NSRange(location: start, length: ctx.caret - start)
        let q = ctx.prefix.lowercased()
        var out: [CompletionItem] = []
        for t in (useJS ? js : php) {
            let l = t.name.lowercased()
            guard l.hasPrefix(q) || (q.count >= 2 && CompletionLex.subsequence(Array(q.utf8), in: l)) else { continue }
            let lt = LiveTemplate(abbrev: t.name, description: t.detail, scopes: [], body: t.body, vars: t.vars)
            var snippet = LiveTemplates.snippet(lt, fileURL: ctx.fileURL)
            snippet = snippet.replacingOccurrences(of: expr, with: escaped)
            var it = CI.make("." + t.name, .template, detail: t.detail.replacingOccurrences(of: "$expr", with: exprText), insert: snippet, snippet: true, sort: "0" + t.name, range: range)
            it.filterText = exprText + "." + t.name
            it.documentation = "Postfix template `.\(t.name)`\n\n```\n\(t.detail)\n```"
            it.priority = 8
            out.append(it)
        }
        return out
    }
}
