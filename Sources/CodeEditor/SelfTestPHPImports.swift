import AppKit

/// CE_SELFTEST: native PHP "Import class" quick fix + "Optimize imports" (PHPImports.swift) on realistic PHP fixtures.
enum SelfTestPHPImports {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    /// Applies the plan for `fqn` to `text`; nil unless the plan is an edit.
    private static func imported(_ text: String, _ fqn: String) -> String? {
        let short = String(fqn.split(separator: "\\").last ?? "")
        guard case .edit(let e) = PHPImports.plan(fqn: fqn, short: short, in: text as NSString) else { return nil }
        return (text as NSString).replacingCharacters(in: e.range, with: e.text)
    }

    private static func plan(_ text: String, _ fqn: String) -> PHPImports.Plan {
        PHPImports.plan(fqn: fqn, short: String(fqn.split(separator: "\\").last ?? ""), in: text as NSString)
    }

    /// `§` marks the caret.
    private static func name(_ marked: String) -> String? {
        let caret = (marked as NSString).range(of: "§").location
        let clean = marked.replacingOccurrences(of: "§", with: "")
        return PHPImports.nameAtCaret(clean as NSString, caret: caret)?.name
    }

    static func run(w: ProjectWindow) {
        let head = "<?php\n\nnamespace App\\Http\\Controllers;\n\n"
        let body = "class PostController extends Controller\n{\n}\n"

        // sorted insertion among existing uses
        let uses = "use App\\Models\\Post;\nuse App\\Models\\User;\nuse Illuminate\\Http\\Request;\n\n"
        check("import: before the first greater use", imported(head + uses + body, "App\\Http\\Requests\\StorePost")
              == head + "use App\\Http\\Requests\\StorePost;\nuse App\\Models\\Post;\nuse App\\Models\\User;\nuse Illuminate\\Http\\Request;\n\n" + body)
        check("import: in the middle", imported(head + uses + body, "App\\Models\\Comment")
              == head + "use App\\Models\\Comment;\nuse App\\Models\\Post;\nuse App\\Models\\User;\nuse Illuminate\\Http\\Request;\n\n" + body)
        check("import: between two uses", imported(head + uses + body, "App\\Models\\Tag")
              == head + "use App\\Models\\Post;\nuse App\\Models\\Tag;\nuse App\\Models\\User;\nuse Illuminate\\Http\\Request;\n\n" + body)
        check("import: after the last use", imported(head + uses + body, "Symfony\\Component\\Finder\\Finder")
              == head + "use App\\Models\\Post;\nuse App\\Models\\User;\nuse Illuminate\\Http\\Request;\nuse Symfony\\Component\\Finder\\Finder;\n\n" + body)
        check("import: case-insensitive ordering", imported(head + "use App\\Zeta;\n\n" + body, "App\\alpha\\Thing") == head + "use App\\alpha\\Thing;\nuse App\\Zeta;\n\n" + body)

        // first use of the file
        check("import: first use after the namespace line", imported(head + body, "Illuminate\\Http\\Request")
              == head + "use Illuminate\\Http\\Request;\n\n" + body)
        check("import: namespace directly followed by code gets a blank line",
              imported("<?php\nnamespace App;\nclass A {}\n", "Foo\\Bar") == "<?php\nnamespace App;\n\nuse Foo\\Bar;\n\nclass A {}\n")
        check("import: no namespace, no uses -> after the open tag", imported("<?php\n\nclass A {}\n", "Foo\\Bar") == "<?php\n\nuse Foo\\Bar;\n\nclass A {}\n")
        check("import: declare(strict_types) stays first",
              imported("<?php\n\ndeclare(strict_types=1);\n\nclass A {}\n", "Foo\\Bar") == "<?php\n\ndeclare(strict_types=1);\n\nuse Foo\\Bar;\n\nclass A {}\n")
        check("import: declare + namespace -> after namespace",
              imported("<?php\ndeclare(strict_types=1);\n\nnamespace App;\n\nclass A {}\n", "Foo\\Bar") == "<?php\ndeclare(strict_types=1);\n\nnamespace App;\n\nuse Foo\\Bar;\n\nclass A {}\n")
        check("import: declare directly followed by code",
              imported("<?php\ndeclare(strict_types=1);\nclass A {}\n", "Foo\\Bar") == "<?php\ndeclare(strict_types=1);\n\nuse Foo\\Bar;\n\nclass A {}\n")
        check("import: no namespace with existing uses", imported("<?php\n\nuse Foo\\Zed;\n\nclass A {}\n", "Foo\\Bar") == "<?php\n\nuse Foo\\Bar;\nuse Foo\\Zed;\n\nclass A {}\n")
        check("import: global class in a namespaced file", imported(head + body, "DateTime") == head + "use DateTime;\n\n" + body)
        check("import: CRLF files keep CRLF",
              imported("<?php\r\n\r\nnamespace App;\r\n\r\nuse A\\B;\r\n\r\nclass X {}\r\n", "A\\C") == "<?php\r\n\r\nnamespace App;\r\n\r\nuse A\\B;\r\nuse A\\C;\r\n\r\nclass X {}\r\n")
        check("import: braced use group is not split",
              imported(head + "use App\\Models\\{Post, User};\nuse Zed\\Last;\n\n" + body, "App\\Services\\Mailer")
              == head + "use App\\Models\\{Post, User};\nuse App\\Services\\Mailer;\nuse Zed\\Last;\n\n" + body)
        check("import: before a group when it sorts first", imported(head + "use Illuminate\\Support\\{Arr, Str};\n\n" + body, "App\\Models\\Post")
              == head + "use App\\Models\\Post;\nuse Illuminate\\Support\\{Arr, Str};\n\n" + body)
        check("import: use function lines do not confuse placement",
              imported(head + "use App\\Models\\Post;\nuse function App\\helper;\n\n" + body, "Zed\\Last")
              == head + "use App\\Models\\Post;\nuse Zed\\Last;\nuse function App\\helper;\n\n" + body)

        // nothing to do
        check("import: skipped when already imported", plan(head + uses + body, "App\\Models\\Post") == .alreadyImported)
        check("import: skipped when imported under an alias", plan(head + "use App\\Models\\Post as P;\n\n" + body, "App\\Models\\Post") == .alreadyImported)
        check("import: skipped for the same namespace", plan(head + body, "App\\Http\\Controllers\\Controller") == .sameNamespace)
        check("import: skipped for a global class in a global file", plan("<?php\nclass A {}\n", "Exception") == .sameNamespace)
        check("import: a name taken by another import is a conflict", plan(head + uses + body, "Other\\Post") == .conflict("App\\Models\\Post"))
        check("import: braced namespace is not touched", plan("<?php\nnamespace App {\nclass A {}\n}\n", "Foo\\Bar") == .unsupported)

        // which names are candidates
        check("name: new Foo", name("<?php\n$a = new Fo§o;") == "Foo" && name("<?php\n$a = new Foo§();") == "Foo")
        check("name: Foo::", name("<?php\nFoo§::bar();") == "Foo")
        check("name: type hint / return type", name("<?php\nfunction f(Fo§o $x): Bar {}") == "Foo" && name("<?php\nfunction f(Foo $x): Ba§r {}") == "Bar")
        check("name: extends / implements", name("<?php\nclass A extends Ba§se implements Contract {}") == "Base" && name("<?php\nclass A implements Contract§ {}") == "Contract")
        check("name: nullable and union types", name("<?php\nfunction f(?Fo§o $x) {}") == "Foo" && name("<?php\nfunction f(int|Fo§o $x) {}") == "Foo")
        check("name: catch and instanceof", name("<?php\ncatch (Ex§ception $e)") == "Exception" && name("<?php\n$a instanceof Fo§o") == "Foo")
        check("name: docblock tag", name("<?php\n/** @param Fo§o $x */") == "Foo")
        check("name: not a $variable, member, qualified or declaration",
              name("<?php\n$Fo§o = 1;") == nil && name("<?php\n$a->Fo§o") == nil && name("<?php\nFoo::BA§R") == nil && name("<?php\n\\Fo§o::x()") == nil
              && name("<?php\nFoo§\\Bar::x()") == nil && name("<?php\nclass Fo§o {}") == nil && name("<?php\nfunction Fo§o() {}") == nil
              && name("<?php\nFoo§(1)") == nil && name("<?php\nuse Fo§o;") == nil && name("<?php\nnew foo§") == nil)

        // candidate lookup: project class table + builtins + facades
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-imports-\(getpid())")
        try? fm.removeItem(at: root)
        func put(_ rel: String, _ text: String) {
            let u = root.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        put("composer.json", #"{"autoload":{"psr-4":{"App\\":"app/"}}}"#)
        put("app/Models/Post.php", "<?php\nnamespace App\\Models;\nclass Post {}\n")
        put("app/Models/User.php", "<?php\nnamespace App\\Models;\nclass User {}\n")
        put("app/Nova/User.php", "<?php\nnamespace App\\Nova;\nclass User {}\n")
        put("app/Services/Mailer.php", "<?php\nnamespace App\\Services;\nclass Mailer {}\n")
        let file = root.appendingPathComponent("app/Http/Controllers/PostController.php")
        check("candidates: several project classes with the same short name",
              PHPImports.candidates(for: "User", fileURL: file).map(\.fqn) == ["App\\Models\\User", "App\\Nova\\User"])
        check("candidates: single project class", PHPImports.candidates(for: "Mailer", fileURL: file).map(\.fqn) == ["App\\Services\\Mailer"])
        check("candidates: PHP builtin", PHPImports.candidates(for: "DateTimeImmutable", fileURL: file).map(\.fqn) == ["DateTimeImmutable"])
        check("candidates: facade fallback", PHPImports.candidates(for: "Route", fileURL: file).map(\.fqn) == ["Illuminate\\Support\\Facades\\Route"])
        check("candidates: unknown name has none", PHPImports.candidates(for: "Nope", fileURL: file).isEmpty)

        // optimize imports
        func optimized(_ t: String) -> String? { PHPImports.optimize(t as NSString).map { (t as NSString).replacingCharacters(in: $0.range, with: $0.text) } }
        let rest = "class A {\n    function f(Post $p, Collection $c) { return new Zed(); }\n}\n"
        let messy = head + "use Zed\\Zed;\nuse Illuminate\\Support\\Collection;\nuse App\\Models\\Post;\nuse App\\Models\\Post;\nuse App\\Unused\\Thing;\n\n" + rest
        check("optimize: sorts, drops duplicates and unused",
              optimized(messy) == head + "use App\\Models\\Post;\nuse Illuminate\\Support\\Collection;\nuse Zed\\Zed;\n\n" + rest)
        check("optimize: already optimal -> nothing", optimized(head + "use App\\Models\\Post;\nuse Illuminate\\Support\\Collection;\nuse Zed\\Zed;\n\n" + rest) == nil)
        check("optimize: a docblock mention keeps the import",
              optimized(head + "use B\\Thing;\nuse A\\Used;\n\n/** @var Thing */\nclass X { function f(Used $u) {} }\n")
              == head + "use A\\Used;\nuse B\\Thing;\n\n/** @var Thing */\nclass X { function f(Used $u) {} }\n")
        check("optimize: blank-line groups are sorted separately and kept",
              optimized(head + "use Zed\\Z;\n\nuse B\\B;\nuse A\\A;\n\nclass X { function f(Z $a, A $b, B $c) {} }\n")
              == head + "use Zed\\Z;\n\nuse A\\A;\nuse B\\B;\n\nclass X { function f(Z $a, A $b, B $c) {} }\n")
        check("optimize: braced group, function and const imports are kept",
              optimized(head + "use function App\\helper;\nuse App\\Models\\{Post, User};\nuse const App\\FOO;\nuse Alpha\\A;\n\nclass X { function f(A $a) {} }\n")
              == head + "use Alpha\\A;\nuse App\\Models\\{Post, User};\nuse function App\\helper;\nuse const App\\FOO;\n\nclass X { function f(A $a) {} }\n")
        check("optimize: aliases honoured", optimized(head + "use Z\\Zed as Zz;\nuse A\\Aa as Bb;\n\nclass X { function f(Zz $a, Bb $b) {} }\n")
              == head + "use A\\Aa as Bb;\nuse Z\\Zed as Zz;\n\nclass X { function f(Zz $a, Bb $b) {} }\n")
        check("optimize: file without uses -> nothing", optimized(head + body) == nil)
        check("optimize: trait `use` inside a class is not an import", optimized(head + "class A {\n    use SoftDeletes;\n    use B;\n}\n") == nil)
        check("optimize: CRLF", optimized("<?php\r\nuse B\\B;\r\nuse A\\A;\r\n\r\nclass X { function f(A $a, B $b) {} }\r\n")
              == "<?php\r\nuse A\\A;\r\nuse B\\B;\r\n\r\nclass X { function f(A $a, B $b) {} }\r\n")

        // end to end through the Alt-Return items on a real tab
        let src = head + "use Illuminate\\Http\\Request;\n\nclass PostController extends Controller\n{\n    public function show(User $u) { return new Mailer(); }\n}\n"
        put("app/Http/Controllers/PostController.php", src)
        w.open(file)
        guard let tab = w.current, tab.url.standardizedFileURL == file.standardizedFileURL else {
            check("quick fix: tab opened", false); try? fm.removeItem(at: root); return
        }
        let tv = tab.textView
        func caret(in marker: String, _ offset: Int) { tv.setSelectedRange(NSRange(location: (src as NSString).range(of: marker).location + offset, length: 0)) }
        func importItems() -> [PickerItem] { PHPQuickFixes.items(for: tab).filter { $0.title.hasPrefix("Import class") } }
        caret(in: "User $u", 2)
        check("quick fix: two candidates are listed, project first", importItems().map(\.title) == ["Import class App\\Models\\User", "Import class App\\Nova\\User"])
        importItems().first { $0.title == "Import class App\\Models\\User" }?.run()
        let expected = head + "use App\\Models\\User;\nuse Illuminate\\Http\\Request;\n\n" + String(src.dropFirst((head + "use Illuminate\\Http\\Request;\n\n").count))
        check("quick fix: choosing a candidate inserts the use line", tv.string == expected)
        check("quick fix: caret stays on the name", (tv.string as NSString).substring(with: NSRange(location: tv.selectedRange().location - 2, length: 4)) == "User")
        tv.undoManager?.undo()
        check("quick fix: one undo reverts the import", tv.string == src)
        caret(in: "Mailer", 1)
        check("quick fix: single candidate", importItems().map(\.title) == ["Import class App\\Services\\Mailer"])
        caret(in: "extends Controller", 12)
        check("quick fix: same-namespace class offers no import", importItems().isEmpty)
        caret(in: "Request;", 1)
        check("quick fix: the use line itself offers nothing", importItems().isEmpty)
        check("quick fix: optimize item appears when imports are unused", PHPQuickFixes.items(for: tab).contains { $0.title == "Optimize imports" })
        try? fm.removeItem(at: root)
    }
}
