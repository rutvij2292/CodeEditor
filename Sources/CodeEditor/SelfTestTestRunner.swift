import AppKit

/// CE_SELFTEST checks for the Pest/PHPUnit runner: discovery, JUnit parsing, command building, and a full run
/// against a fake `vendor/bin/pest` shell script (also cancellation and re-run failed).
enum SelfTestTestRunner {
    static func run(w: ProjectWindow, then done: @escaping () -> Void) {
        discoveryChecks()
        gutterChecks(w: w)
        junitChecks()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-testrunner-\(getpid())")
        try? fm.createDirectory(at: root.appendingPathComponent("vendor/bin"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent("tests"), withIntermediateDirectories: true)
        commandChecks(root: root)
        runChecks(root: root) {
            try? fm.removeItem(at: root)
            done()
        }
    }

    private static func discoveryChecks() {
        let pest = "<?php\n\ntest('adds numbers', function () {\n    expect(1 + 1)->toBe(2);\n});\n\nit(\"does \\\"things\\\"\", function () {});\n$x->it('nope');\n"
        let p = TestDiscovery.discover(in: pest)
        SelfTest.check("testrunner: pest finds test() and it() plus a file marker",
                       p.map(\.kind) == [.file, .pest, .pest] && p.map(\.line) == [1, 3, 7] && p[1].name == "adds numbers")
        let unit = """
        <?php
        namespace Tests\\Feature;

        class UserTest extends TestCase
        {
            public function test_creates_user(): void {}

            /** @test */
            public function it_lists_users() {}

            #[Test]
            #[DataProvider('x')]
            public function attribute_marked() {}

            /** @testdox not a test marker */
            public function helper() {}

            private function testHelperIsStillATest() {}

            public function notATest() {}
        }
        """
        let u = TestDiscovery.discover(in: unit)
        SelfTestTestRunner.expect("testrunner: phpunit class and test_*, @test, #[Test] methods found",
                                  u.map(\.name) == ["UserTest", "test_creates_user", "it_lists_users", "attribute_marked", "testHelperIsStillATest"]
                                  && u.first?.kind == .class && u[1].line == 6)
        SelfTest.check("testrunner: plain PHP has no tests", TestDiscovery.discover(in: "<?php\nclass Foo { function bar() {} }\n").isEmpty)
    }

    /// A PHP test file opened in a real tab gets run icons in its gutter, and failures turn them red.
    private static func gutterChecks(w: ProjectWindow) {
        guard let root = w.root else { return }
        let url = root.appendingPathComponent("tests/GutterTest.php")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "<?php\nclass GutterTest extends TestCase\n{\n    public function test_a() {}\n    public function test_b() {}\n}\n".write(to: url, atomically: true, encoding: .utf8)
        w.open(url)
        guard let tab = w.current, let gutter = (tab.view.subviews.first as? EditorContainer)?.gutter, let g = TestGutter.controller(for: tab) else {
            SelfTest.check("testrunner: php tab gets a gutter controller", false); return
        }
        SelfTest.check("testrunner: gutter shows run icons on class and tests", gutter.lineIcons == [2: .run, 4: .run, 5: .run])
        SelfTest.check("testrunner: caret picks the test above it", { tab.textView.setSelectedRange(NSRange(location: 0, length: 0)); return g.testAtCaret()?.kind == .class }())
        let path = url.standardizedFileURL.path
        let results = [TestResult(name: "test_a", className: "GutterTest", file: path, line: 4, status: .passed, message: "", time: 0),
                       TestResult(name: "test_b", className: "GutterTest", file: path, line: 5, status: .failed, message: "boom\n\(path):5", time: 0)]
        TestResultsStore.shared.finish(results: results, request: TestRequest(title: "x"), status: "")
        SelfTest.check("testrunner: gutter shows pass, fail and a failed class", gutter.lineIcons == [2: .failed, 4: .passed, 5: .failed])
        TestResultsStore.shared.clear()
        SelfTest.check("testrunner: clearing results restores run icons", gutter.lineIcons == [2: .run, 4: .run, 5: .run])
        w.close(path)
    }

    fileprivate static func expect(_ name: String, _ ok: Bool) { SelfTest.check(name, ok) }

    private static let sampleXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <testsuites><testsuite name="Feature" tests="4">
      <testsuite name="Tests\\Feature\\UserTest" file="/p/tests/UserTest.php" tests="4">
        <testcase name="test_ok" class="Tests\\Feature\\UserTest" classname="Tests.Feature.UserTest" file="/p/tests/UserTest.php" line="10" time="0.010"/>
        <testcase name="test_bad" class="Tests\\Feature\\UserTest" file="/p/tests/UserTest.php" line="14" time="0.020">
          <failure type="PHPUnit\\Framework\\ExpectationFailedException">Tests\\Feature\\UserTest::test_bad
    Failed asserting that false is true.

    /p/tests/UserTest.php:17</failure>
        </testcase>
        <testcase name="test_boom" class="Tests\\Feature\\UserTest" file="/p/tests/UserTest.php" line="20" time="0.005">
          <error type="Error">Call to undefined function foo()

    /p/app/Thing.php:9
    /p/tests/UserTest.php:22</error>
        </testcase>
        <testcase name="test_skip" class="Tests\\Feature\\UserTest" file="/p/tests/UserTest.php" line="30" time="0"><skipped/></testcase>
      </testsuite></testsuite></testsuites>
    """

    private static func junitChecks() {
        let r = JUnitParser.parse(Data(sampleXML.utf8))
        SelfTest.check("testrunner: junit yields 4 cases in order", r.map(\.name) == ["test_ok", "test_bad", "test_boom", "test_skip"])
        SelfTest.check("testrunner: junit statuses", r.map(\.status) == [.passed, .failed, .errored, .skipped])
        SelfTest.check("testrunner: junit failure line comes from the trace in the test file", r[1].failureLine == 17 && r[2].failureLine == 22 && r[0].failureLine == 10)
        SelfTest.check("testrunner: junit class and message", r[1].className == "Tests\\Feature\\UserTest" && r[1].message.contains("Failed asserting"))
        SelfTest.check("testrunner: malformed junit gives no results", JUnitParser.parse(Data("<testsuite><testcase".utf8)).isEmpty)

        let store = TestResultsStore()
        store.finish(results: r, request: TestRequest(title: "x"), status: "")
        let method = DiscoveredTest(kind: .method, name: "test_bad", line: 14, className: "UserTest")
        SelfTest.check("testrunner: store maps result to discovered method", store.result(for: method, in: "/p/tests/UserTest.php")?.status == .failed)
        SelfTest.check("testrunner: store does not match a longer method name",
                       store.result(for: DiscoveredTest(kind: .method, name: "test_ba", line: 1, className: nil), in: "/p/tests/UserTest.php") == nil)
        SelfTest.check("testrunner: file summary is failed", store.summary(in: "/p/tests/UserTest.php") == .failed)
        let problems = store.merged(into: [], root: URL(fileURLWithPath: "/p"))
        SelfTest.check("testrunner: failures become problems at the trace line",
                       problems.count == 1 && problems[0].diagnostics.map(\.line) == [17, 22] && problems[0].diagnostics[0].message.hasPrefix("test_bad: "))
        let pestResult = TestResult(name: "__pest_evaluable_it_adds_numbers", className: nil, file: "/p/a.php", line: 3, status: .passed, message: "", time: 0)
        let pestStore = TestResultsStore()
        pestStore.finish(results: [pestResult], request: TestRequest(title: "x"), status: "")
        SelfTest.check("testrunner: pest names match descriptions",
                       pestStore.result(for: DiscoveredTest(kind: .pest, name: "adds numbers", line: 3, className: nil), in: "/p/a.php") != nil)
    }

    private static func commandChecks(root: URL) {
        let fm = FileManager.default
        func script(_ name: String) {
            let url = root.appendingPathComponent("vendor/bin/\(name)")
            try? "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        SelfTest.check("testrunner: no vendor binary gives no command", TestRunner.command(root: root, request: TestRequest(title: "t"), junit: "/tmp/j.xml") == nil)
        script("phpunit")
        var c = TestRunner.command(root: root, request: TestRequest(title: "t", paths: ["tests/A.php"], filter: "::test_x( |$)"), junit: "/tmp/j.xml")
        SelfTest.check("testrunner: phpunit command with filter, junit and path",
                       c?.isPest == false && c?.executable.hasSuffix("vendor/bin/phpunit") == true
                       && c?.arguments == ["--colors=never", "--log-junit", "/tmp/j.xml", "--filter", "::test_x( |$)", "tests/A.php"])
        script("pest")
        c = TestRunner.command(root: root, request: TestRequest(title: "t"), junit: "/tmp/j.xml")
        SelfTest.check("testrunner: pest preferred over phpunit", c?.isPest == true && c?.cwd == root.standardizedFileURL.path)
        SelfTest.check("testrunner: pest description filter wildcards punctuation",
                       TestRunner.filterPattern(name: "it adds: 2 numbers", isMethod: false) == "it.+adds.+2.+numbers")
        SelfTest.check("testrunner: phpunit method filter is anchored on ::name",
                       TestRunner.filterPattern(name: "test_a", isMethod: true) == "::test_a( |$)")
        let failed = [TestResult(name: "test_bad with data set #0", className: nil, file: "", line: 0, status: .failed, message: "", time: 0),
                      TestResult(name: "__pest_evaluable_it_breaks", className: nil, file: "", line: 0, status: .errored, message: "", time: 0)]
        SelfTest.check("testrunner: re-run failed builds one alternation filter",
                       TestRunner.request(rerunning: failed)?.filter == "::test_bad( |$)|it.+breaks" && TestRunner.request(rerunning: []) == nil)
    }

    /// Fake pest: prints a line, writes JUnit to the `--log-junit` path, exits 1. `PEST_SLEEP` makes it hang for cancellation.
    private static let fakePest = """
    #!/bin/sh
    junit=""
    while [ $# -gt 0 ]; do
      if [ "$1" = "--log-junit" ]; then junit="$2"; shift; fi
      shift
    done
    echo "fake pest running"
    if [ -f "$(dirname "$0")/hang" ]; then sleep 30; fi
    cat > "$junit" <<'XML'
    __XML__
    XML
    exit 1
    """

    private static func runChecks(root: URL, then done: @escaping () -> Void) {
        let fm = FileManager.default
        let pest = root.appendingPathComponent("vendor/bin/pest")
        try? fakePest.replacingOccurrences(of: "__XML__", with: sampleXML.replacingOccurrences(of: "/p/", with: root.standardizedFileURL.path + "/"))
            .write(to: pest, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pest.path)

        let c = TestController(root: root)
        let store = TestResultsStore.shared
        var shown = 0
        c.showPanel = { shown += 1 }
        var problemNotes = 0
        let token = NotificationCenter.default.addObserver(forName: LanguageServers.problemsDidChange, object: nil, queue: .main) { _ in problemNotes += 1 }

        c.onFinish = { outcome in
            SelfTest.check("testrunner: fake run reports exit 1 with 4 results", outcome.exitCode == 1 && outcome.results.count == 4 && !outcome.cancelled)
            SelfTest.check("testrunner: store has the run, output and failures",
                           !store.isRunning && store.output.contains("fake pest running") && store.failed.count == 2 && store.statusLine.hasPrefix("1 passed, 2 failed, 1 skipped"))
            SelfTest.check("testrunner: panel shown and problems notified", shown >= 1 && problemNotes >= 1)
            let file = root.appendingPathComponent("tests/UserTest.php").standardizedFileURL.path
            SelfTest.check("testrunner: problems panel feed includes the failures",
                           LanguageServers.problems(forRoot: root).first { $0.url.path == file }?.diagnostics.count == 2)
            SelfTest.check("testrunner: store results keyed by standardized path", store.byFile[file]?.count == 4)

            // Re-run failed: the fake prints the same XML; check the request was the filter one, then cancel a hanging run.
            c.onFinish = { _ in
                SelfTest.check("testrunner: re-run failed used a --filter request", store.lastRequest?.filter?.contains("::test_bad( |$)") == true && store.lastRequest?.paths.isEmpty == true)
                fm.createFile(atPath: root.appendingPathComponent("vendor/bin/hang").path, contents: Data())
                c.onFinish = { outcome in
                    _ = c   // keep the controller alive until the last run reports
                    SelfTest.check("testrunner: cancel terminates the process and keeps old results",
                                   outcome.cancelled && store.statusLine == "Cancelled" && !store.isRunning && store.failed.count == 2)
                    NotificationCenter.default.removeObserver(token)
                    store.clear()
                    done()
                }
                c.rerunLast()
                SelfTest.check("testrunner: re-run last starts a run", store.isRunning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { c.stop() }
            }
            c.rerunFailed()
        }
        c.run(TestRequest(title: "UserTest.php", paths: ["tests/UserTest.php"]))
    }
}
