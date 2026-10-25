import AppKit

/// Headless checks for postfix templates (PostfixTemplates.swift) and the extra PHP live templates.
enum SelfTestPostfix {
    private static func items(_ text: String, file: String = "/tmp/pf/Foo.php") -> [CompletionItem] {
        let caret = (text as NSString).range(of: "§").location
        let clean = text.replacingOccurrences(of: "§", with: "")
        let ns = clean as NSString
        var s = caret
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        let url = URL(fileURLWithPath: file)
        CompletionLex.resetCache()
        let ctx = CompletionContext(text: clean, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: ".", isManual: false,
                                    prefixRange: NSRange(location: s, length: caret - s))
        return PostfixTemplates.generate(ctx)
    }

    /// Text the template produces when accepted (snippet parsed, tab stops dropped).
    private static func expand(_ it: CompletionItem) -> String { SnippetParser.parse(it.insertText).text }

    static func run() {
        let c = SelfTest.check
        let php = "<?php\nclass A { function f($items, $user) {\n    "
        let r1 = items(php + "$items.fo§")
        let fe = r1.first { $0.label == ".foreach" }
        c("postfix: `$items.fo` offers .foreach", fe != nil && r1.contains { $0.label == ".forek" })
        c("postfix: foreach expansion", fe.map(expand) == "foreach ($items as $item) {\n\t\n}")
        c("postfix: replaces the whole `$items.fo` text", fe.map { ($0.replaceRange?.length ?? 0) == "$items.fo".utf16.count } == true)
        c("postfix: filter text starts with the typed text (ranker prefix match)", fe?.filterText == "$items.foreach")
        let r2 = items(php + "$user->posts.if§")
        c("postfix: member chain is the expression", r2.first { $0.label == ".if" }.map(expand) == "if ($user->posts) {\n\t\n}")
        let r3 = items(php + "$this->repo->find($id).va§")
        c("postfix: call chain with arguments; $ in the expression is kept literal", r3.first { $0.label == ".var" }.map(expand) == "$value = $this->repo->find($id);")
        c("postfix: static call", items(php + "Foo::bar($x).re§").first { $0.label == ".return" }.map(expand) == "return Foo::bar($x);")
        c("postfix: array element", items(php + "$rows['a'].dd§").first { $0.label == ".dd" }.map(expand) == "dd($rows['a']);")
        c("postfix: isset / null / notnull / not", items(php + "$a.iss§").first.map(expand) == "isset($a)"
          && items(php + "$a.nul§").first { $0.label == ".null" }.map(expand) == "if ($a === null) {\n\t\n}"
          && items(php + "$a.notn§").first { $0.label == ".notnull" }.map(expand) == "if ($a !== null) {\n\t\n}"
          && items(php + "$a.no§").first { $0.label == ".not" }.map(expand) == "!$a")
        c("postfix: casts and count", items(php + "$a.ar§").first { $0.label == ".arr" }.map(expand) == "(array) $a" && items(php + "$a.co§").first { $0.label == ".count" }.map(expand) == "count($a)")
        c("postfix: tn throws new", items(php + "$msg.tn§").first { $0.label == ".tn" }.map(expand) == "throw new \\Exception($msg);")
        c("postfix: not after a space (concatenation)", items(php + "$a . fo§").isEmpty && items(php + "$a. fo§").isEmpty)
        c("postfix: not after a bare word or a number", items(php + "foo.fo§").isEmpty && items(php + "1.fo§").isEmpty)
        c("postfix: not in a string", items("<?php\n$s = '$items.fo§").isEmpty)
        c("postfix: nothing without a typed name", items(php + "$items.§").isEmpty)
        c("postfix: not for other file types", items("body { }\n.fo§", file: "/tmp/pf/a.css").isEmpty)
        let js = "function f(items) {\n  "
        let j1 = items(js + "items.fo§", file: "/tmp/pf/a.js")
        c("postfix js: `items.fo` offers .foreach (for...of)", j1.first { $0.label == ".foreach" }.map(expand) == "for (const item of items) {\n\t\n}")
        c("postfix js: member chain + log", items(js + "this.state.items.lo§", file: "/tmp/pf/a.js").first { $0.label == ".log" }.map(expand) == "console.log(this.state.items)")
        c("postfix js: await call", items(js + "fetch(url).aw§", file: "/tmp/pf/a.ts").first { $0.label == ".await" }.map(expand) == "await fetch(url)")
        c("postfix js: not after a keyword", items(js + "return.if§", file: "/tmp/pf/a.js").isEmpty)
        // extra PHP live templates
        for ab in ["if", "ife", "elif", "for", "while", "sw", "try", "cls", "iface", "trait", "enum", "pubp", "prop", "inv", "get", "set", "strict"] {
            c("live template `\(ab)` exists for php", LiveTemplates.shared.has(ab, scopes: ["php"]))
        }
        // popup rows
        var m = CI.make("format", .method, detail: "(Money $m, array $o = ['a', 'b']): string")
        var row = PopupRow.make(m, matches: [0])
        c("popup row: parameter list after the name, return type right-aligned", row.params == "(Money $m, array $o = ['a', 'b'])" && row.detail == "string")
        m.source = "Model"
        row = PopupRow.make(m, matches: [])
        c("popup row: inherited member shows its declaring class in the detail", row.detail == "string  Model")
        row = PopupRow.make(CI.make("name", .property, detail: "string"), matches: [])
        c("popup row: properties keep their type as detail, no params", row.detail == "string" && row.params.isEmpty)
        c("popup row: deprecated flag passes through", { var d = CI.make("old", .method, detail: "()"); d.deprecated = true; return PopupRow.make(d, matches: []).deprecated }())
        c("live template `if` expands to a block", LiveTemplates.shared.lookup("if", scopes: ["php"]).map { SnippetParser.parse(LiveTemplates.snippet($0, fileURL: nil)).text.hasPrefix("if (") } == true)
    }
}
