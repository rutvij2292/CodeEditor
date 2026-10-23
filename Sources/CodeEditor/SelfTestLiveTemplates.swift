import AppKit

/// CE_SELFTEST: live templates (LiveTemplates.swift): file format, scopes, $VAR$ conversion, completion items, Tab expansion.
enum SelfTestLiveTemplates {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    private static func ctx(_ marked: String, file: String) -> CompletionContext {
        let caret = (marked as NSString).range(of: "§").location
        let clean = marked.replacingOccurrences(of: "§", with: "")
        let ns = clean as NSString
        var s = caret
        while s > 0, CompletionLex.isIdent(ns.character(at: s - 1)) { s -= 1 }
        let url = URL(fileURLWithPath: "/tmp/ce-lt/" + file)
        CompletionLex.resetCache()
        return CompletionContext(text: clean, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil, isManual: false,
                                 prefixRange: NSRange(location: s, length: caret - s))
    }

    private static func tabEvent(shift: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
    }

    static func run(w: ProjectWindow) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-lt-\(getpid())")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let savedURL = LiveTemplates.fileURL
        defer { LiveTemplates.fileURL = savedURL; try? fm.removeItem(at: dir) }
        let tfile = dir.appendingPathComponent("templates.json")
        LiveTemplates.fileURL = tfile
        let lt = LiveTemplates.shared

        // snippet conversion
        let t1 = LiveTemplate(abbrev: "x", description: "", scopes: [], body: "foo($$ARG$, $B$) { $this->$ARG$ = $B$; \\n }$END$", vars: ["ARG": "a}b", "B": "$1"])
        let s1 = LiveTemplates.snippet(t1, fileURL: nil)
        let p1 = SnippetParser.parse(s1)
        check("template: $VAR$ becomes ordered tab stops, PHP $vars stay literal", p1.text == "foo($a}b, $1) { $this->a}b = $1; \\n }")
        check("template: stops are ARG, B, then the end", p1.stops.map(\.index) == [1, 2, 0] && p1.stops[0].range == NSRange(location: 5, length: 3)
              && p1.stops[2].range.location == p1.text.utf16.count)
        let t2 = LiveTemplate(abbrev: "c", description: "", scopes: [], body: "class $CLASS$ { $SELECTION$ }\n// $YEAR$", vars: [:])
        let s2 = SnippetParser.parse(LiveTemplates.snippet(t2, fileURL: URL(fileURLWithPath: "/x/UserController.php"), now: Date(timeIntervalSince1970: 1_800_000_000)))
        check("template: $CLASS$ is the file name, $YEAR$ the year", s2.text == "class UserController {  }\n// 2027")
        check("template: blade file names drop .blade", LiveTemplates.snippet(LiveTemplate(abbrev: "c", description: "", scopes: [], body: "$CLASS$"),
                                                                               fileURL: URL(fileURLWithPath: "/x/home.blade.php")) == "home")
        check("template: lowercase / unmatched dollars are literal", SnippetParser.parse(LiveTemplates.snippet(
            LiveTemplate(abbrev: "d", description: "", scopes: [], body: "$a $B $ $$ cost$5 $Z"), fileURL: nil)).text == "$a $B $ $$ cost$5 $Z")

        // defaults all convert and parse sanely
        var bad: [String] = []
        for t in LiveTemplates.defaults {
            let p = SnippetParser.parse(LiveTemplates.snippet(t, fileURL: URL(fileURLWithPath: "/x/Foo.php")))
            if p.stops.last?.index != 0 || p.text.contains("$$") && !t.body.contains("$$") { bad.append(t.abbrev) }
            if t.abbrev.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) { bad.append(t.abbrev + " (abbrev)") }
        }
        check("template: every default parses with a final stop and a plain abbreviation (\(bad))", bad.isEmpty)
        let abbrevs = Set(LiveTemplates.defaults.map(\.abbrev))
        check("template: defaults cover Laravel / PHP / Vue basics", ["rt", "fn", "pubf", "foreach", "dd", "ctrl", "vsfc", "ref", "computed"].allSatisfy(abbrevs.contains))
        let rt = LiveTemplates.defaults.first { $0.abbrev == "rt" }!
        check("template: rt expands to a route", SnippetParser.parse(LiveTemplates.snippet(rt, fileURL: nil)).text == "Route::get('/', [Controller::class, 'index'])->name('name');")

        // scopes
        func scopes(_ m: String, _ f: String) -> Set<String> { LiveTemplates.scopes(for: ctx(m, file: f)) }
        check("scopes: php", scopes("<?php\nrt§", "a.php") == ["php"])
        check("scopes: blade html + blade expression", scopes("<div>\nbfe§", "v.blade.php") == ["blade", "html"] && scopes("<div>{{ x§ }}", "v.blade.php") == ["blade"])
        check("scopes: vue script / template / style", scopes("<script setup>\nre§", "A.vue").isSuperset(of: ["vue", "vue-script", "js"])
              && scopes("<template>\n<div>§", "A.vue").isSuperset(of: ["vue", "vue-template", "html"]) && scopes("<style>\n§", "A.vue").isSuperset(of: ["vue", "css"]))
        check("scopes: ts includes js, js excludes ts", scopes("x§", "a.ts") == ["ts", "js"] && scopes("x§", "a.js") == ["js"])
        check("scopes: css, md, html", scopes("§", "a.css") == ["css"] && scopes("§", "a.md") == ["md"] && scopes("<p>§", "a.html") == ["html"])
        check("scopes: php file's html region", scopes("<div>§</div>", "a.php") == ["html"])
        check("lookup: scoped (rt only in php)", lt.lookup("rt", scopes: ["php"]) != nil && lt.lookup("rt", scopes: ["js"]) == nil && lt.lookup("ref", scopes: ["vue-script"]) != nil
              && lt.lookup("ref", scopes: ["vue-template"]) == nil)

        // completion items
        var items = LiveTemplateCompletion.generate(ctx("<?php\npub§", file: "a.php"))
        check("completion: templates listed with the template kind", items.contains { $0.label == "pubf" && $0.kind == .template && $0.isSnippet }
              && items.contains { $0.label == "pubsf" })
        check("completion: nothing for another language's templates", !LiveTemplateCompletion.generate(ctx("<?php\nbf§", file: "a.php")).contains { $0.label == "bfe" })
        check("completion: blade templates in blade", LiveTemplateCompletion.generate(ctx("<div>\nbf§", file: "v.blade.php")).contains { $0.label == "bfe" })
        check("completion: not after $ or ->", LiveTemplateCompletion.generate(ctx("<?php\n$dd§", file: "a.php")).isEmpty
              && LiveTemplateCompletion.generate(ctx("<?php\n$a->dd§", file: "a.php")).isEmpty)
        check("completion: not inside strings", LiveTemplateCompletion.generate(ctx("<?php\n$a = 'dd§';", file: "a.php")).isEmpty)
        check("completion: needs a prefix", LiveTemplateCompletion.generate(ctx("<?php\n§", file: "a.php")).isEmpty)
        items = SnippetCompletion.generate(ctx("<?php\nfn§", file: "a.php"))
        check("completion: live template shadows the built-in snippet of the same abbreviation", !items.contains { $0.label == "fn" })
        check("completion: other built-in snippets remain", SnippetCompletion.generate(ctx("<?php\nswi§", file: "a.php")).contains { $0.label == "switch" })

        // user file: format, shadowing, reload on change, errors
        check("user file: missing file -> only defaults", lt.lookup("zz", scopes: ["php"]) == nil && lt.lastError == nil && lt.templates().count == LiveTemplates.defaults.count)
        let json1 = """
        {"templates": [
          {"abbrev": "zz", "description": "mine", "scopes": ["php"], "body": "echo $WHAT$;$END$", "vars": {"WHAT": "'hi'"}},
          {"abbrev": "rt", "scopes": "php", "body": ["Route::any('$URI$');", "$END$"]},
          {"abbrev": "everywhere", "body": "E$END$"},
          {"abbrev": "bad abbrev", "body": "x"},
          {"abbrev": "nobody"}
        ]}
        """
        try? json1.write(to: tfile, atomically: true, encoding: .utf8)
        check("user file: new template found without restart", lt.lookup("zz", scopes: ["php"])?.body == "echo $WHAT$;$END$" && lt.lookup("zz", scopes: ["php"])?.vars["WHAT"] == "'hi'")
        check("user file: shadows a default with the same abbrev, body lines joined", lt.lookup("rt", scopes: ["php"])?.body == "Route::any('$URI$');\n$END$")
        check("user file: no scopes = everywhere", lt.lookup("everywhere", scopes: ["css"]) != nil && lt.lookup("everywhere", scopes: []) != nil)
        check("user file: invalid entries skipped and reported", lt.lookup("bad abbrev", scopes: ["php"]) == nil && lt.lookup("nobody", scopes: ["php"]) == nil && lt.lastError?.contains("2 entries") == true)
        check("user file: Tab pre-check knows user abbreviations", lt.knows(abbrev: "zz") && lt.knows(abbrev: "dd") && !lt.knows(abbrev: "qqq"))
        let json2 = #"[{"abbrev": "zz", "scopes": ["php"], "body": "changed"}]"#
        try? json2.write(to: tfile, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: tfile.path)
        check("user file: edits are picked up (mtime changed), old entries gone", lt.lookup("zz", scopes: ["php"])?.body == "changed" && lt.lookup("everywhere", scopes: []) == nil
              && lt.lookup("rt", scopes: ["php"])?.body.hasPrefix("Route::$METHOD$") == true)
        try? "{ not json".write(to: tfile, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: tfile.path)
        check("user file: broken JSON falls back to defaults with an error", lt.lookup("dd", scopes: ["php"]) != nil && lt.lookup("zz", scopes: ["php"]) == nil && lt.lastError != nil)
        try? fm.removeItem(at: tfile)
        check("user file: deleting the file removes user templates", lt.lookup("zz", scopes: ["php"]) == nil && lt.lastError == nil)

        // Tab expansion in a real editor tab
        try? #"{"templates": [{"abbrev": "zz", "scopes": ["php"], "body": "echo $WHAT$ . $OTHER$;$END$", "vars": {"WHAT": "'hi'", "OTHER": "1"}}]}"#.write(to: tfile, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(20)], ofItemAtPath: tfile.path)
        let file = dir.appendingPathComponent("Demo.php")
        try? "<?php\n\nclass Demo\n{\n    zz\n}\n".write(to: file, atomically: true, encoding: .utf8)
        w.open(file)
        guard let tab = w.current, tab.url.standardizedFileURL == file.standardizedFileURL, let cc = CompletionSystem.controller(for: tab) else {
            check("tab expansion: editor and completion controller available", false); return
        }
        let tv = tab.textView
        func text() -> String { tv.string }
        let ns0 = text() as NSString
        tv.setSelectedRange(NSRange(location: ns0.range(of: "zz").location + 2, length: 0))
        check("tab expansion: Tab after the abbreviation is consumed", cc.handleKey(tabEvent()))
        check("tab expansion: abbreviation replaced by the body", text() == "<?php\n\nclass Demo\n{\n    echo 'hi' . 1;\n}\n")
        check("tab expansion: first stop selected", (text() as NSString).substring(with: tv.selectedRange()) == "'hi'")
        check("tab expansion: Tab visits the next stop", cc.handleKey(tabEvent()) && (text() as NSString).substring(with: tv.selectedRange()) == "1")
        check("tab expansion: last Tab lands on $END$", cc.handleKey(tabEvent()) && tv.selectedRange().length == 0
              && tv.selectedRange().location == (text() as NSString).range(of: ";\n}").location + 1 && cc.session == nil)
        tv.undoManager?.undo()
        check("tab expansion: single undo restores the abbreviation", text().contains("    zz\n}"))

        // not expanded: unknown word, member access, mid-word, selection, wrong scope
        func tryTab(_ s: String, caretAfter marker: String) -> (Bool, String) {
            tv.string = s
            tv.setSelectedRange(NSRange(location: (s as NSString).range(of: marker).upperBound, length: 0))
            let handled = cc.handleKey(tabEvent())
            return (handled, text())
        }
        var r = tryTab("<?php\n$a->zz", caretAfter: "zz")
        check("tab expansion: not after ->", !r.0 && r.1 == "<?php\n$a->zz")
        r = tryTab("<?php\n$zz", caretAfter: "zz")
        check("tab expansion: not after $", !r.0)
        r = tryTab("<?php\nnope", caretAfter: "nope")
        check("tab expansion: unknown abbreviation falls through to normal Tab", !r.0 && r.1 == "<?php\nnope")
        r = tryTab("<?php\n$s = 'zz';", caretAfter: "zz")
        check("tab expansion: not inside a string", !r.0)
        r = tryTab("<?php\nzzz", caretAfter: "zz")
        check("tab expansion: needs the whole word", !r.0)
        tv.string = "<?php\nzz"
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        check("tab expansion: mid-word is not expanded", !cc.handleKey(tabEvent()))
        tv.string = "<?php\nzz x"
        tv.setSelectedRange(NSRange(location: 6, length: 2))
        check("tab expansion: a selection is not expanded", !cc.handleKey(tabEvent()))
        tv.string = "<?php\nzz"
        tv.setSelectedRange(NSRange(location: 8, length: 0))
        check("tab expansion: Shift-Tab does not expand", !cc.handleKey(tabEvent(shift: true)))
        tv.string = "<?php\nzz"
        tv.setSelectedRange(NSRange(location: 8, length: 0))
        check("tab expansion: same text expands again", cc.handleKey(tabEvent()) && text().hasPrefix("<?php\necho 'hi' . 1;"))
        cc.endSession()
        tv.string = "<?php\n\nclass Demo {\n    function a() {\n        foreach"
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        check("tab expansion: default template, indentation follows the line", cc.handleKey(tabEvent())
              && text().hasSuffix("        foreach ($items as $item) {\n            \n        }") && (text() as NSString).substring(with: tv.selectedRange()) == "items")
        cc.endSession()
    }
}
