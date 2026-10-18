import Foundation

/// One executed test, parsed from JUnit XML.
struct TestResult: Equatable {
    enum Status { case passed, failed, errored, skipped }
    var name: String
    var className: String?
    var file: String        // absolute path ("" when the log has none)
    var line: Int           // declaration line from the log (0 when unknown)
    var status: Status
    var message: String     // failure/error text, empty when passed
    var time: Double
    var isFailure: Bool { status == .failed || status == .errored }

    /// Line inside the test file named by the failure trace (`/path/FooTest.php:23`), else the declaration line.
    var failureLine: Int {
        guard !file.isEmpty, let rx = TestResult.traceRx else { return max(line, 1) }
        let ns = message as NSString
        for m in rx.matches(in: message, range: NSRange(location: 0, length: ns.length)) where ns.substring(with: m.range(at: 1)) == file {
            return Int(ns.substring(with: m.range(at: 2))) ?? max(line, 1)
        }
        return max(line, 1)
    }
    private static let traceRx = try? NSRegularExpression(pattern: #"(/[^\s:()]+\.php):(\d+)"#)
}

/// JUnit XML (PHPUnit / Pest `--log-junit`) to results. Suites nest; only `<testcase>` elements count.
final class JUnitParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) -> [TestResult] {
        let p = JUnitParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        return p.results
    }

    private var results: [TestResult] = []
    private var current: TestResult?
    private var text = ""
    private var inProblem = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "testcase":
            let cls = a["class"] ?? a["classname"]
            current = TestResult(name: a["name"] ?? "", className: (cls?.isEmpty ?? true) ? nil : cls, file: a["file"] ?? "",
                                 line: Int(a["line"] ?? "") ?? 0, status: .passed, message: "", time: Double(a["time"] ?? "") ?? 0)
        case "failure": begin(.failed, a)
        case "error": begin(.errored, a)
        case "skipped": if current != nil { current?.status = .skipped }
        default: break
        }
    }

    private func begin(_ status: TestResult.Status, _ a: [String: String]) {
        guard current != nil, current?.isFailure != true else { return }
        current?.status = status
        text = ""
        inProblem = true
        if let m = a["message"], !m.isEmpty { current?.message = m }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if inProblem { text += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if inProblem { text += String(decoding: CDATABlock, as: UTF8.self) } }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "failure", "error":
            guard inProblem else { return }
            inProblem = false
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { current?.message = body }
        case "testcase":
            if let c = current { results.append(c) }
            current = nil
        default: break
        }
    }
}

/// How a run was requested; also what "re-run last" repeats.
struct TestRequest: Equatable {
    var title: String
    /// Test files / directories (absolute or project-relative); empty runs the whole suite.
    var paths: [String] = []
    /// Regex handed to `--filter` (no delimiters).
    var filter: String?
}

/// Latest results per file plus run state. Main thread only. Posts `didChange` on every change and
/// `LanguageServers.problemsDidChange` when the failure set changes so the Problems panel follows.
final class TestResultsStore {
    static let shared = TestResultsStore()
    static let didChange = Notification.Name("CodeEditor.testResultsDidChange")

    private(set) var byFile: [String: [TestResult]] = [:]
    /// Results of the most recent run, in run order (what the Tests panel lists).
    private(set) var lastRun: [TestResult] = []
    private(set) var isRunning = false
    private(set) var lastRequest: TestRequest?
    private(set) var output = ""
    private(set) var statusLine = "No tests run yet"
    /// Files (absolute paths) a running request covers; nil means the whole suite.
    private(set) var runningPaths: Set<String>?

    var failed: [TestResult] { byFile.values.flatMap { $0 }.filter(\.isFailure) }

    func begin(_ request: TestRequest, root: URL) {
        isRunning = true
        lastRequest = request
        output = ""
        statusLine = "Running \(request.title)…"
        runningPaths = request.paths.isEmpty ? nil : Set(request.paths.map { TestRunner.absolute($0, root: root) })
        changed(problems: false)
    }

    func appendOutput(_ s: String) {
        output += s
        if output.utf8.count > 2_000_000 { output = String(output.suffix(1_000_000)) }
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["outputOnly": true])
    }

    /// `results` replace earlier entries for the same test (or, on a full-file run, for the whole file).
    func finish(results: [TestResult], request: TestRequest, status: String) {
        isRunning = false
        runningPaths = nil
        statusLine = status
        lastRun = results
        if request.paths.isEmpty && request.filter == nil { byFile = [:] }
        let files = Set(results.map(\.file))
        for file in files {
            let new = results.filter { $0.file == file }
            if request.filter == nil { byFile[file] = new; continue }
            var merged = (byFile[file] ?? []).filter { old in !new.contains { $0.name == old.name } }
            merged += new
            byFile[file] = merged
        }
        changed(problems: true)
    }

    func fail(status: String) {
        isRunning = false
        runningPaths = nil
        statusLine = status
        changed(problems: false)
    }

    func clear() {
        byFile = [:]; lastRun = []; lastRequest = nil; output = ""; statusLine = "No tests run yet"
        changed(problems: true)
    }

    private func changed(problems: Bool) {
        NotificationCenter.default.post(name: Self.didChange, object: self)
        if problems { NotificationCenter.default.post(name: LanguageServers.problemsDidChange, object: nil) }
    }

    // MARK: matching results to discovered tests

    private static func norm(_ s: String) -> String { String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }) }

    /// The result for a discovered test in `file` (PHPUnit by method name, Pest by description), if one was recorded.
    func result(for test: DiscoveredTest, in file: String) -> TestResult? {
        guard let list = byFile[file] else { return nil }
        let key = Self.norm(test.name)
        let matches = list.filter { r in
            var n = Self.norm(r.name)
            if n.hasPrefix("pestevaluable") { n.removeFirst("pestevaluable".count) }
            let base = n.components(separatedBy: "withdataset").first ?? n
            switch test.kind {
            case .method: return base == key
            case .pest: return base == key || base == "it" + key || base == "test" + key
            default: return false
            }
        }
        return matches.first(where: \.isFailure) ?? matches.first
    }

    /// Aggregate for a class or file marker: failed if any test in the file failed, passed if all passed.
    func summary(in file: String) -> TestResult.Status? {
        guard let list = byFile[file], !list.isEmpty else { return nil }
        if list.contains(where: \.isFailure) { return .failed }
        return list.contains { $0.status == .passed } ? .passed : .skipped
    }

    // MARK: Problems panel

    /// Failures as diagnostics (source "test"), merged into `files` (open files may already have language-server entries).
    func merged(into files: [FileProblems], root: URL) -> [FileProblems] {
        let rp = root.standardizedFileURL.path
        var out = files
        for (path, list) in byFile where path.hasPrefix(rp + "/") {
            let ds = list.filter(\.isFailure).map { r -> FileProblems.Diagnostic in
                let first = r.message.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "Test failed"
                let line = r.failureLine
                return FileProblems.Diagnostic(severity: 1, message: "\(r.name): \(first)", line: line, column: 1, endLine: line, endColumn: 1,
                                               source: "test", code: nil)
            }
            guard !ds.isEmpty else { continue }
            if let i = out.firstIndex(where: { $0.url.path == path }) { out[i].diagnostics += ds }
            else { out.append(FileProblems(url: URL(fileURLWithPath: path), diagnostics: ds)) }
        }
        return out
    }
}
