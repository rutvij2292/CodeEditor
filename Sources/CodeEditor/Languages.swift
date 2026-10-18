import Foundation
import SwiftTreeSitter
import TreeSitterPHP
import TreeSitterJavaScript
import TreeSitterHTML
import TreeSitterCSS
import TreeSitterJSON
import TreeSitterTypeScript
import TreeSitterTSX
import TreeSitterBlade
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterYAML
import TreeSitterBash
import TreeSitterXML
import TreeSitterSCSS

/// A loaded grammar: language, parser, highlight + injection queries. Created lazily the first
/// time a language is opened and cached afterwards (the parser holds no tree, so it is cheap).
final class Grammar {
    let key: String
    let language: Language?
    let highlights: Query?
    let injections: Query?
    let parser: Parser?
    /// Grammar-less highlighters (SQL, dotenv).
    let lexer: SimpleLexer.Kind?
    /// Vue single-file components: `{{ expr }}` interpolations in text nodes are JS.
    var findsInterpolations = false
    lazy var textQuery: Query? = {
        guard let language else { return nil }
        return try? Query(language: language, data: Data("(text) @t".utf8))
    }()
    lazy var configuration: LanguageConfiguration? = {
        guard let language else { return nil }
        var queries: [Query.Definition: Query] = [:]
        if let highlights { queries[.highlights] = highlights }
        if let injections { queries[.injections] = injections }
        return LanguageConfiguration(language, name: key, queries: queries)
    }()

    init(key: String, language: Language?, highlights: Query?, injections: Query?, lexer: SimpleLexer.Kind?) {
        self.key = key
        self.language = language
        self.highlights = highlights
        self.injections = injections
        self.lexer = lexer
        if let language {
            let p = Parser()
            try? p.setLanguage(language)
            parser = p
        } else {
            parser = nil
        }
    }
}

/// Maps file names / extensions / injection tags to grammars.
enum Languages {
    private static var grammars: [String: Grammar] = [:]
    private static var missing: Set<String> = []

    // MARK: Query loading

    /// SwiftPM resource bundles keep `queries/` at the bundle root (flat layout), while
    /// SwiftTreeSitter's own lookup expects `Contents/Resources/`. Accept both, next to the
    /// executable or inside an .app's Resources.
    private static func queriesURL(for name: String) -> URL? {
        let bundle = "TreeSitter\(name)_TreeSitter\(name).bundle"
        let roots = [Bundle.main.bundleURL, Bundle.main.resourceURL,
                     Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        for root in roots {
            for sub in ["", "Contents/Resources/"] {
                let url = root.appendingPathComponent(bundle).appendingPathComponent(sub + "queries")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    private static func read(_ bundle: String, _ file: String) -> String {
        guard let dir = queriesURL(for: bundle),
              let s = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else { return "" }
        // Drop "; inherits:" lines - composition is done explicitly below.
        return s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("; inherits") }.joined(separator: "\n")
    }

    /// Compiles the concatenation of `parts`; if that fails, keeps only the parts that compile alone.
    private static func compile(_ language: Language, _ parts: [String]) -> Query? {
        let parts = parts.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        if let q = try? Query(language: language, data: Data(parts.joined(separator: "\n").utf8)) { return q }
        let good = parts.filter { part in
            do { _ = try Query(language: language, data: Data(part.utf8)); return true } catch {
                return false
            }
        }
        guard !good.isEmpty else { return nil }
        return try? Query(language: language, data: Data(good.joined(separator: "\n").utf8))
    }

    // MARK: Extra queries

    private static let commentKinds = #"""
    ((comment) @comment.doc (#match? @comment.doc "^/\\*\\*"))
    ((comment) @comment.line (#match? @comment.line "^(//|#(?!\\[))"))
    """#

    private static let jsonPunctuation = #"["{" "}" "[" "]" ","] @punctuation.json"#

    /// PhpStorm-style distinctions on top of the upstream PHP queries. Later patterns win over earlier ones when a
    /// span is captured twice with the same number of name components, so order matters here.
    private static let phpExtras = [
        "(class_declaration name: (name) @type)", "(interface_declaration name: (name) @type)",
        "(trait_declaration name: (name) @type)", "(enum_declaration name: (name) @type)",
        "(base_clause (name) @type)", "(base_clause (qualified_name) @type)",
        "(class_interface_clause (name) @type)", "(class_interface_clause (qualified_name) @type)",
        // `$var`: both the `$` and the name carry the variable colour (upstream paints `$` as an operator).
        "(variable_name \"$\" @variable.php)", "(variable_name (name) @variable.php)",
        #"((variable_name "$" @variable.builtin (name) @_n @variable.builtin) (#eq? @_n "this"))"#,
        // Parameters (declaration sites), promoted constructor properties, named arguments.
        #"(simple_parameter name: (variable_name ["$" (name)] @variable.parameter.php))"#,
        #"(variadic_parameter name: (variable_name ["$" (name)] @variable.parameter.php))"#,
        #"(property_promotion_parameter name: (variable_name ["$" (name)] @variable.parameter.php))"#,
        "(argument name: (name) @variable.parameter.named)",
        // Members: instance / nullsafe / static properties, class constants, enum cases.
        "(property_element (variable_name [\"$\" (name)] @property.declared))",
        "(member_access_expression name: (name) @property)",
        "(nullsafe_member_access_expression name: (name) @property)",
        #"(scoped_property_access_expression name: (variable_name ["$" (name)] @property.static))"#,
        #"(class_constant_access_expression "::" . (name) @constant.class (#not-eq? @constant.class "class"))"#,
        #"(class_constant_access_expression "::" . (name) @keyword (#eq? @keyword "class"))"#,
        "(enum_case name: (name) @constant.class)",
        // Calls: `$obj->m()` / `$obj?->m()` vs `Class::m()`, `__construct` is a normal method name.
        "(method_declaration name: (name) @function.method.declaration)",
        "(member_call_expression name: (name) @function.method.call)",
        "(nullsafe_member_call_expression name: (name) @function.method.call)",
        "(scoped_call_expression name: (name) @function.method.static)",
        "(escape_sequence) @string.escape",
        // Attributes `#[Route(...)]` (name only).
        "(attribute (name) @meta.annotation)", "(attribute (qualified_name) @meta.annotation)",
    ]

    private static let htmlExtras = #"["<" ">" "</" "/>"] @tag.delimiter"#

    private static let bladeExtras = #"""
    [(directive) (directive_start) (directive_end)] @keyword.directive
    ["{{" "}}" "{!!" "!!}"] @punctuation.special
    """#

    private static let htmlInjections = #"""
    ((script_element (start_tag) @_t (raw_text) @injection.content)
     (#match? @_t "lang=[\"']?tsx[\"' >]") (#set! injection.language "tsx"))
    ((script_element (start_tag) @_t (raw_text) @injection.content)
     (#match? @_t "lang=[\"']?(ts|typescript)[\"' >]") (#set! injection.language "typescript"))
    ((script_element (start_tag) @_t (raw_text) @injection.content)
     (#match? @_t "json") (#set! injection.language "json"))
    ((script_element (start_tag) @_t (raw_text) @injection.content)
     (#not-match? @_t "json|lang=[\"']?(ts|tsx|typescript)[\"' >]|type=[\"']?text/(template|x-template|html)")
     (#set! injection.language "javascript"))
    ((style_element (start_tag) @_t (raw_text) @injection.content)
     (#match? @_t "lang=[\"']?s[ac]ss[\"' >]") (#set! injection.language "scss"))
    ((style_element (start_tag) @_t (raw_text) @injection.content)
     (#not-match? @_t "lang=[\"']?s[ac]ss[\"' >]") (#set! injection.language "css"))
    (attribute (attribute_name) @_n (#match? @_n "^on[a-z]+$")
      (quoted_attribute_value (attribute_value) @injection.content) (#set! injection.language "javascript"))
    (attribute (attribute_name) @_n (#eq? @_n "style")
      (quoted_attribute_value (attribute_value) @injection.content) (#set! injection.language "css_decl"))
    """#

    private static let frameworkAttrs = #"""
    (attribute (attribute_name) @_n (#match? @_n "^(v-|:|@|#|x-|wire:)[A-Za-z]")
      (quoted_attribute_value (attribute_value) @injection.content) (#set! injection.language "javascript"))
    """#

    private static let jsInjections = #"""
    (call_expression
      function: [(identifier) @injection.language (member_expression property: (property_identifier) @injection.language)]
      arguments: (template_string (string_fragment) @injection.content)
      (#set! injection.combined "1") (#set! injection.include-children "1"))
    """#

    private static let phpInjections = ["""
    ((text) @injection.content (#set! injection.language "html") (#set! injection.combined "1"))
    """, """
    (heredoc (heredoc_body) @injection.content (heredoc_end) @injection.language (#set! injection.include-children "1"))
    """, """
    (nowdoc (nowdoc_body) @injection.content (heredoc_end) @injection.language (#set! injection.include-children "1"))
    """]

    private static let bladeInjections = #"""
    ((php_only) @injection.content (#set! injection.language "php_only"))
    ((parameter) @injection.content (#set! injection.include-children "1") (#set! injection.language "php_only"))
    """#

    private static let markdownInjections = #"""
    (fenced_code_block (info_string (language) @injection.language) (code_fence_content) @injection.content (#set! injection.include-children "1"))
    ((html_block) @injection.content (#set! injection.language "html") (#set! injection.include-children "1"))
    ((minus_metadata) @injection.content (#set! injection.language "yaml") (#set! injection.include-children "1"))
    ((inline) @injection.content (#set! injection.language "markdown_inline") (#set! injection.include-children "1"))
    """#

    // MARK: Grammar construction

    private static func build(_ key: String) -> Grammar? {
        func g(_ lang: OpaquePointer, hl: [String], inj: [String] = []) -> Grammar {
            let language = Language(lang)
            return Grammar(key: key, language: language, highlights: compile(language, hl),
                           injections: compile(language, inj), lexer: nil)
        }
        let js = read("JavaScript", "highlights.scm") + "\n" + read("JavaScript", "highlights-jsx.scm")
        let jsPlain = read("JavaScript", "highlights.scm")
        let html = read("HTML", "highlights.scm")
        switch key {
        case "php": return g(tree_sitter_php(), hl: [read("PHP", "highlights.scm"), commentKinds] + phpExtras, inj: phpInjections)
        case "php_only": return g(tree_sitter_php_only(), hl: [read("PHP", "highlights.scm"), commentKinds] + phpExtras, inj: Array(phpInjections.dropFirst()))
        case "blade":
            return g(tree_sitter_blade(), hl: [html, htmlExtras, read("Blade", "highlights.scm"), bladeExtras],
                     inj: [htmlInjections, frameworkAttrs, bladeInjections])
        case "html": return g(tree_sitter_html(), hl: [html, htmlExtras], inj: [htmlInjections])
        case "vue":
            let grammar = g(tree_sitter_html(), hl: [html, htmlExtras], inj: [htmlInjections, frameworkAttrs])
            grammar.findsInterpolations = true
            return grammar
        case "js": return g(tree_sitter_javascript(), hl: [js, commentKinds], inj: [jsInjections])
        case "ts":
            return g(tree_sitter_typescript(), hl: [jsPlain, read("TypeScript", "highlights.scm"), commentKinds],
                     inj: [jsInjections])
        case "tsx":
            return g(tree_sitter_tsx(), hl: [js, read("TSX", "highlights.scm"), commentKinds], inj: [jsInjections])
        case "css": return g(tree_sitter_css(), hl: [read("CSS", "highlights.scm")])
        case "scss": return g(tree_sitter_scss(), hl: [read("SCSS", "highlights.scm"), commentKinds, "(single_line_comment) @comment.line"])
        case "json": return g(tree_sitter_json(), hl: [read("JSON", "highlights.scm"), jsonPunctuation])
        case "yaml": return g(tree_sitter_yaml(), hl: [read("YAML", "highlights.scm")])
        case "bash": return g(tree_sitter_bash(), hl: [read("Bash", "highlights.scm")])
        case "xml": return g(tree_sitter_xml(), hl: [read("XML", "highlights.scm")])
        case "md":
            return g(tree_sitter_markdown(), hl: [read("Markdown", "highlights.scm")], inj: [markdownInjections])
        case "md_inline":
            return g(tree_sitter_markdown_inline(), hl: [read("MarkdownInline", "highlights.scm")])
        case "sql": return Grammar(key: key, language: nil, highlights: nil, injections: nil, lexer: .sql)
        case "dotenv": return Grammar(key: key, language: nil, highlights: nil, injections: nil, lexer: .dotenv)
        default: return nil
        }
    }

    /// Lazily builds and caches the grammar for a key such as "php", "blade", "ts".
    static func grammar(forKey key: String) -> Grammar? {
        if let g = grammars[key] { return g }
        if missing.contains(key) { return nil }
        guard let g = build(key) else { missing.insert(key); return nil }
        grammars[key] = g
        return g
    }

    // MARK: Detection

    private static let extensionKeys: [String: String] = [
        "php": "php", "phtml": "php", "php3": "php", "php4": "php", "php5": "php", "phps": "php", "inc": "php",
        "js": "js", "jsx": "js", "mjs": "js", "cjs": "js",
        "ts": "ts", "mts": "ts", "cts": "ts", "tsx": "tsx",
        "html": "html", "htm": "html", "xhtml": "html", "vue": "vue",
        "css": "css", "scss": "scss", "less": "css",
        "json": "json", "jsonc": "json", "json5": "json", "webmanifest": "json", "map": "json", "geojson": "json",
        "md": "md", "markdown": "md", "mdx": "md", "mkd": "md",
        "yml": "yaml", "yaml": "yaml",
        "sh": "bash", "bash": "bash", "zsh": "bash", "ksh": "bash", "command": "bash", "env": "dotenv",
        "xml": "xml", "svg": "xml", "xsd": "xml", "xsl": "xml", "xslt": "xml", "plist": "xml", "csproj": "xml",
        "rss": "xml", "atom": "xml", "wsdl": "xml", "storyboard": "xml", "xib": "xml",
        "sql": "sql",
    ]

    private static let fileNameKeys: [String: String] = [
        "composer.lock": "json", ".babelrc": "json", ".prettierrc": "json", ".eslintrc": "json",
        ".bashrc": "bash", ".zshrc": "bash", ".bash_profile": "bash", ".zprofile": "bash", ".profile": "bash",
        ".bash_aliases": "bash", ".zshenv": "bash", "artisan": "php",
    ]

    static func key(forFileName fileName: String) -> String? {
        let name = (fileName as NSString).lastPathComponent.lowercased()
        if name.hasSuffix(".blade.php") { return "blade" }
        if name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".env") { return "dotenv" }
        if let k = fileNameKeys[name] { return k }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : extensionKeys[ext]
    }

    static func key(forExtension ext: String) -> String? {
        extensionKeys[ext.lowercased()]
    }

    /// Resolves an injection language tag (markdown fence info string, heredoc label, tagged
    /// template tag...) to a grammar key.
    static func key(forInjectionName raw: String) -> String? {
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "php": return "php"
        case "php_only": return "php_only"
        case "blade": return "blade"
        case "html", "htm", "xhtml", "twig": return "html"
        case "vue": return "vue"
        case "javascript", "js", "jsx", "mjs", "cjs", "node": return "js"
        case "typescript", "ts", "mts": return "ts"
        case "tsx": return "tsx"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "css_decl": return "css_decl"
        case "json", "jsonc", "json5": return "json"
        case "yaml", "yml": return "yaml"
        case "bash", "sh", "shell", "zsh", "console", "shellscript": return "bash"
        case "xml", "svg": return "xml"
        case "markdown", "md": return "md"
        case "markdown_inline": return "md_inline"
        case "sql", "mysql", "pgsql", "postgresql", "sqlite", "psql", "gql_sql": return "sql"
        case "env", "dotenv", "ini": return "dotenv"
        default: return nil
        }
    }

    // MARK: Public entry points

    static func configuration(forFileName fileName: String) -> LanguageConfiguration? {
        key(forFileName: fileName).flatMap { grammar(forKey: $0)?.configuration }
    }

    /// Kept for existing callers (Symbols uses it for "php" / "js" / "jsx").
    static func configuration(forExtension ext: String) -> LanguageConfiguration? {
        key(forExtension: ext).flatMap { grammar(forKey: $0)?.configuration }
    }
}
