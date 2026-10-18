import Foundation

/// A runnable thing found in a PHP file: a Pest/PHPUnit test, a PHPUnit class, or a Pest file (marked on line 1).
struct DiscoveredTest: Equatable {
    enum Kind { case file, `class`, method, pest }
    var kind: Kind
    /// Method name (PHPUnit) or description (Pest); the class name for `.class`; empty for `.file`.
    var name: String
    var line: Int           // 1-based
    var className: String?
}

/// Finds Pest (`test('..')` / `it('..')`) and PHPUnit (`test*` methods, `#[Test]`, `@test`) tests by a line scan.
/// Cheap enough to run on the main thread for ordinary test files; callers skip very large files.
enum TestDiscovery {
    private static let pest = try! NSRegularExpression(pattern: #"^\s*(test|it)\s*\(\s*(['"])(.*?)\2"#)
    private static let classRx = try! NSRegularExpression(pattern: #"^\s*(?:(?:final|abstract|readonly)\s+)*class\s+(\w+)(?:\s+extends\s+([\w\\]+))?"#)
    private static let functionRx = try! NSRegularExpression(pattern: #"^\s*(?:(?:public|protected|private|static|final)\s+)*function\s+(\w+)\s*\("#)
    private static let attributeRx = try! NSRegularExpression(pattern: #"#\[[^\]]*\bTest\b"#)
    private static let docTagRx = try! NSRegularExpression(pattern: #"@test\b"#)

    /// Quick pre-check so ordinary PHP files cost one substring scan.
    static func mightContainTests(_ text: String) -> Bool {
        text.contains("TestCase") || text.contains("function test") || text.contains("@test") || text.contains("#[")
            || text.contains("test(") || text.contains("it(") || text.contains("Test ")
    }

    static func discover(in text: String) -> [DiscoveredTest] {
        guard mightContainTests(text) else { return [] }
        let ns = text as NSString
        var out: [DiscoveredTest] = []
        var currentClass: String?
        var classIsTest = false
        var pendingTag = false
        var pestSeen = false
        var lineNo = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            lineNo += 1
            let line = ns.substring(with: enclosing) as NSString
            let r = NSRange(location: 0, length: line.length)
            let trimmed = (line as String).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }
            if let m = classRx.firstMatch(in: line as String, range: r) {
                let name = line.substring(with: m.range(at: 1))
                let parent = m.range(at: 2).location == NSNotFound ? "" : line.substring(with: m.range(at: 2))
                currentClass = name
                classIsTest = name.hasSuffix("Test") || name.hasSuffix("Tests") || parent.hasSuffix("TestCase")
                if classIsTest { out.append(DiscoveredTest(kind: .class, name: name, line: lineNo, className: name)) }
                pendingTag = false
                return
            }
            if !classIsTest, let m = pest.firstMatch(in: line as String, range: r) {
                out.append(DiscoveredTest(kind: .pest, name: line.substring(with: m.range(at: 3)), line: lineNo, className: nil))
                pestSeen = true
                return
            }
            if let m = functionRx.firstMatch(in: line as String, range: r) {
                let name = line.substring(with: m.range(at: 1))
                if classIsTest, name.hasPrefix("test") || pendingTag {
                    out.append(DiscoveredTest(kind: .method, name: name, line: lineNo, className: currentClass))
                }
                pendingTag = false
                return
            }
            if attributeRx.firstMatch(in: line as String, range: r) != nil || docTagRx.firstMatch(in: line as String, range: r) != nil { pendingTag = true; return }
            // Attributes, docblocks and comments keep the pending tag alive; anything else clears it.
            if !(trimmed.hasPrefix("#[") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("//")) { pendingTag = false }
        }
        if pestSeen { out.insert(DiscoveredTest(kind: .file, name: "", line: 1, className: nil), at: 0) }
        return out
    }
}
