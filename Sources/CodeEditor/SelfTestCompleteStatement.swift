import AppKit

/// Headless checks for "Complete Current Statement" (CompleteStatement.swift).
enum SelfTestCompleteStatement {
    /// Applies the edit for the caret at `§` and returns the resulting text with the caret shown as `§`.
    private static func apply(_ text: String) -> String? {
        let caret = (text as NSString).range(of: "§").location
        let clean = text.replacingOccurrences(of: "§", with: "")
        guard let e = CompleteStatement.compute(text: clean as NSString, caret: caret) else { return nil }
        var out = clean as NSString
        out = out.replacingCharacters(in: e.range, with: e.text) as NSString
        let c = min(e.caret, out.length)
        return out.substring(to: c) + "§" + out.substring(from: c)
    }

    static func run() {
        let c = SelfTest.check
        c("statement: closes the open call and adds `;`", apply("foo($a, bar(§") == "foo($a, bar());§")
        c("statement: plain assignment gets `;`", apply("$x = 5§") == "$x = 5;§")
        c("statement: caret in the middle of the line still completes it", apply("$x = fo§o($a)") == "$x = foo($a);§")
        c("statement: return gets `;`", apply("    return $x§") == "    return $x;§")
        c("statement: open array bracket closed", apply("$a = [§") == "$a = [];§")
        c("statement: trailing comment kept after the `;`", apply("$x = foo() // note§") == "$x = foo();§ // note")
        c("statement: already complete line only moves the caret", apply("$x = 5;§ ") == "$x = 5;§")
        c("statement: if header gets a block with the caret inside", apply("if ($a > 1)§") == "if ($a > 1) {\n    §\n}")
        c("statement: indented foreach block", apply("    foreach ($items as $item)§") == "    foreach ($items as $item) {\n        §\n    }")
        c("statement: unclosed header paren is closed first", apply("while ($i < 3§") == "while ($i < 3) {\n    §\n}")
        c("statement: method declaration gets a body", apply("    public function save(Request $r): bool§") == "    public function save(Request $r): bool {\n        §\n    }")
        c("statement: abstract method is a plain statement", apply("    abstract public function save()§") == "    abstract public function save();§")
        c("statement: class header gets a body", apply("class Foo extends Bar§") == "class Foo extends Bar {\n    §\n}")
        c("statement: else / try", apply("else§") == "else {\n    §\n}" && apply("try§") == "try {\n    §\n}")
        c("statement: closure assignment ends with };", apply("$f = function ($x) use ($y)§") == "$f = function ($x) use ($y) {\n    §\n};")
        c("statement: a comment or docblock line is left alone", apply("// todo§") == nil && apply(" * @param int $a§") == nil)
        c("statement: an open string is left alone", apply("echo 'abc§") == nil)
        c("statement: an open block line is left alone", apply("if ($a) {§") == nil)
        c("statement: inside multi-line call arguments no `;` is added", apply("foo([\n    'a' => 1§").map { !$0.contains(";") } ?? true)
        c("statement: `::class` is not a class declaration", apply("$x = Foo::class§") == "$x = Foo::class;§")
        // integration: one undo step
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        tv.allowsUndo = true
        tv.string = "$x = foo(1, bar("
        tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
        CompleteStatement.perform(on: tv)
        c("statement: perform edits the text view", tv.string == "$x = foo(1, bar());" && tv.selectedRange().location == tv.string.utf16.count)
    }
}
