import AppKit

/// CE_SELFTEST: built-in Blade formatter (nesting, directives, raw regions, multi-line tags, idempotence, selection).
enum SelfTestBladeFormat {
    static func run() {
        func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("blade-format: " + name, ok()) }
        func f(_ s: String, tabs: Bool = false, size: Int = 4, lines: Range<Int>? = nil) -> String { BladeFormatter.format(s, useTabs: tabs, size: size, lines: lines) }

        let messy = """
        @extends('layouts.app')
        @section('content')
        <div class="a">
        <ul>
        @foreach($items as $item)
        <li>{{ $item->name }}</li>
        @endforeach
        </ul>
        @if($x)
        <p>yes</p>
        @elseif($y)
        <p>maybe</p>
        @else
        <p>no</p>
        @endif
        </div>
        @endsection
        """ + "\n"
        let clean = """
        @extends('layouts.app')
        @section('content')
            <div class="a">
                <ul>
                    @foreach($items as $item)
                        <li>{{ $item->name }}</li>
                    @endforeach
                </ul>
                @if($x)
                    <p>yes</p>
                @elseif($y)
                    <p>maybe</p>
                @else
                    <p>no</p>
                @endif
            </div>
        @endsection
        """ + "\n"
        check("nesting and directives", f(messy) == clean)
        check("idempotent", f(clean) == clean)
        check("tabs", f(messy, tabs: true).contains("\n\t\t<ul>\n\t\t\t@foreach"))
        check("two-space indent", f(messy, size: 2).contains("\n    <ul>\n      @foreach"))

        check("inline pairs stay put", f("<div>\n<span>a</span> @if($a) b @endif\n</div>\n") == "<div>\n    <span>a</span> @if($a) b @endif\n</div>\n")
        check("void and self-closing tags", f("<div>\n<br>\n<img src=\"a\">\n<x-foo />\n<input type=\"text\">\n</div>\n") == "<div>\n    <br>\n    <img src=\"a\">\n    <x-foo />\n    <input type=\"text\">\n</div>\n")
        check("trailing whitespace trimmed, blank runs collapsed, final newline", f("<p>a</p>   \n\n\n\n<p>b</p>\n\n\n") == "<p>a</p>\n\n<p>b</p>\n")
        check("empty stays empty", f("") == "")

        let multi = "<div\nclass=\"a\"\nid=\"b\"\n>\n<span>x</span>\n</div>\n"
        check("multi-line attributes", f(multi) == "<div\n    class=\"a\"\n    id=\"b\"\n>\n    <span>x</span>\n</div>\n")
        check("multi-line self-closing tag", f("<div>\n<x-input\nname=\"a\"\n/>\n<p>z</p>\n</div>\n") == "<div>\n    <x-input\n        name=\"a\"\n    />\n    <p>z</p>\n</div>\n")
        check("gt inside attribute value", f("<div>\n<a @click=\"a > b\" href=\"#\">x</a>\n</div>\n") == "<div>\n    <a @click=\"a > b\" href=\"#\">x</a>\n</div>\n")
        check("mustache with > inside tag", f("<div>\n<a class=\"{{ $a > 1 ? 'x' : 'y' }}\">t</a>\n</div>\n") == "<div>\n    <a class=\"{{ $a > 1 ? 'x' : 'y' }}\">t</a>\n</div>\n")

        let pre = "<div>\n<pre>\n  keep\n     this\n</pre>\n<p>a</p>\n</div>\n"
        check("pre is untouched", f(pre) == "<div>\n    <pre>\n  keep\n     this\n</pre>\n    <p>a</p>\n</div>\n")
        check("verbatim is untouched", f("<div>\n@verbatim\n   {{ raw }}\n  <b>\n@endverbatim\n<p>a</p>\n</div>\n") == "<div>\n    @verbatim\n   {{ raw }}\n  <b>\n    @endverbatim\n    <p>a</p>\n</div>\n")
        check("script block shifts as a unit", f("<div>\n<script>\nlet a = 1;\n  if (a) {\n    go()\n  }\n</script>\n</div>\n") == "<div>\n    <script>\n    let a = 1;\n      if (a) {\n        go()\n      }\n    </script>\n</div>\n")
        check("php block shifts as a unit", f("<div>\n@php\n$a = 1;\n    $b = 2;\n@endphp\n</div>\n") == "<div>\n    @php\n    $a = 1;\n        $b = 2;\n    @endphp\n</div>\n")
        check("inline @php(...) has no block", f("<div>\n@php($a = 1)\n<p>x</p>\n</div>\n") == "<div>\n    @php($a = 1)\n    <p>x</p>\n</div>\n")
        check("blade comment multi-line shifts", f("<div>\n{{-- a\n  b --}}\n<p>x</p>\n</div>\n") == "<div>\n    {{-- a\n      b --}}\n    <p>x</p>\n</div>\n")
        check("html comment containing tags", f("<div>\n<!-- <span> -->\n<p>x</p>\n</div>\n") == "<div>\n    <!-- <span> -->\n    <p>x</p>\n</div>\n")

        check("section with two args is inline", f("@section('title', 'Home')\n<p>x</p>\n") == "@section('title', 'Home')\n<p>x</p>\n")
        check("section closed by @show", f("@section('a')\n<p>x</p>\n@show\n<p>y</p>\n") == "@section('a')\n    <p>x</p>\n@show\n<p>y</p>\n")
        check("forelse/@empty", f("@forelse($a as $b)\n<p>x</p>\n@empty\n<p>none</p>\n@endforelse\n") == "@forelse($a as $b)\n    <p>x</p>\n@empty\n    <p>none</p>\n@endforelse\n")
        check("switch/case", f("@switch($a)\n@case(1)\n<p>1</p>\n@break\n@case(2)\n<p>2</p>\n@break\n@endswitch\n") == "@switch($a)\n@case(1)\n    <p>1</p>\n    @break\n@case(2)\n    <p>2</p>\n    @break\n@endswitch\n")
        check("directive args with html-looking strings", f("@if($a == '<div>')\n<p>x</p>\n@endif\n") == "@if($a == '<div>')\n    <p>x</p>\n@endif\n")
        check("multi-line directive args shift", f("<div>\n@foreach(\n$a as $b\n)\n<p>x</p>\n@endforeach\n</div>\n") == "<div>\n    @foreach(\n    $a as $b\n    )\n        <p>x</p>\n    @endforeach\n</div>\n")
        check("email and escaped directives are text", f("<div>\nmail me@example.com\n@@if\n<p>x</p>\n</div>\n") == "<div>\n    mail me@example.com\n    @@if\n    <p>x</p>\n</div>\n")
        check("escaped mustache", f("<div>\n@{{ name }}\n<p>x</p>\n</div>\n") == "<div>\n    @{{ name }}\n    <p>x</p>\n</div>\n")
        check("x-slot named", f("<x-card>\n<x-slot:title>\nHi\n</x-slot>\nbody\n</x-card>\n") == "<x-card>\n    <x-slot:title>\n        Hi\n    </x-slot>\n    body\n</x-card>\n")
        check("unclosed li does not drift", f("<ul>\n<li>a\n<li>b\n<li>c\n</ul>\n<p>x</p>\n") == "<ul>\n    <li>a\n    <li>b\n    <li>c\n</ul>\n<p>x</p>\n")
        check("stray closer does not go negative", f("</div>\n<p>x</p>\n") == "</div>\n<p>x</p>\n")
        check("closing tag line then open", f("<div>\n<p>a</p>\n</div><div>\n<p>b</p>\n</div>\n") == "<div>\n    <p>a</p>\n</div><div>\n    <p>b</p>\n</div>\n")
        check("text with < is not a tag", f("<div>\n1 < 2 and 3 > 2\n<p>x</p>\n</div>\n") == "<div>\n    1 < 2 and 3 > 2\n    <p>x</p>\n</div>\n")
        check("unterminated tag at EOF does not crash", !f("<div\nclass=\"a").isEmpty)
        check("unterminated mustache at EOF does not crash", !f("<div>\n{{ $a\n").isEmpty)

        let sel = "<div>\n<p>a</p>\n<p>b</p>\n</div>\n"
        check("selection formats only chosen lines", f(sel, lines: 1..<2) == "<div>\n    <p>a</p>\n<p>b</p>\n</div>\n")
        let r = BladeFormatter.lineRange(for: NSRange(location: 6, length: 12), in: sel)
        check("line range from selection", r == 1..<3)

        // Same visible text before and after (only whitespace may change).
        func strip(_ s: String) -> String { String(s.unicodeScalars.filter { !$0.properties.isWhitespace }) }
        check("only whitespace changes", strip(f(messy)) == strip(messy))
    }

    /// Diff view: lands on the first change when shown; next/previous step through changes and wrap.
    static func runDiffNav() {
        func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("diff-nav: " + name, ok()) }
        var old: [String] = [], new: [String] = []
        for i in 1...200 { old.append("line \(i)"); new.append("line \(i)") }
        new[79] = "changed 80"; new[149] = "changed 150"
        let v = SideBySideDiffView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        v.show(old: old.joined(separator: "\n") + "\n", new: new.joined(separator: "\n") + "\n", oldTitle: "a", newTitle: "b", fileExtension: "txt")
        check("two changes found", v.changeCount == 2)
        check("opens scrolled to the first change", v.currentChange == 0 && v.scrollY > 500)
        let first = v.scrollY
        v.nextChange()
        check("next goes to the second change", v.currentChange == 1 && v.scrollY > first)
        v.nextChange()
        check("next wraps to the first change", v.currentChange == 0 && abs(v.scrollY - first) < 1)
        v.previousChange()
        check("previous wraps to the last change", v.currentChange == 1)
        let top = SideBySideDiffView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        top.show(old: "a\nb\n", new: "x\nb\n", oldTitle: "a", newTitle: "b", fileExtension: "txt")
        check("change at the top stays at the top", top.scrollY == 0 && top.currentChange == 0)
    }
}
