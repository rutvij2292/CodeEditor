import AppKit
import Darwin

/// Tiny blocking HTTP/1.1 server on 127.0.0.1 (thread per connection) for the HTTP client checks.
final class LoopbackHTTPServer {
    private(set) var port: UInt16 = 0
    private var fd: Int32 = -1

    init?() {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return nil }
        var out = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &out) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        port = UInt16(bigEndian: out.sin_port)
        let listener = fd
        Thread.detachNewThread {
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 { return }
                Thread.detachNewThread { Self.serve(c) }
            }
        }
    }

    func stop() { close(fd) }

    private static func readRequest(_ c: Int32) -> (head: String, body: Data)? {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        let sep = Data("\r\n\r\n".utf8)
        while data.range(of: sep) == nil {
            let n = read(c, &buf, buf.count)
            if n <= 0 { return nil }
            data.append(buf, count: n)
        }
        let r = data.range(of: sep)!
        let head = String(decoding: data[..<r.lowerBound], as: UTF8.self)
        var body = Data(data[r.upperBound...])
        let lower = head.lowercased()
        if let cl = lower.components(separatedBy: "\r\n").first(where: { $0.hasPrefix("content-length:") }),
           let want = Int(cl.dropFirst(15).trimmingCharacters(in: .whitespaces)) {
            while body.count < want {
                let n = read(c, &buf, buf.count)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
        }
        return (head, body)
    }

    private static func write(_ c: Int32, _ status: String, _ headers: [String], _ body: Data) {
        var head = "HTTP/1.1 \(status)\r\n" + headers.joined(separator: "\r\n")
        head += "\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8); out.append(body)
        out.withUnsafeBytes { p in
            var off = 0
            while off < out.count {
                let n = Darwin.write(c, p.baseAddress! + off, out.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    private static func serve(_ c: Int32) {
        defer { close(c) }
        guard let (head, body) = readRequest(c) else { return }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return }
        let method = String(parts[0]), path = String(parts[1])
        func header(_ name: String) -> String {
            lines.dropFirst().first { $0.lowercased().hasPrefix(name.lowercased() + ":") }.map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) } ?? ""
        }
        switch path.split(separator: "?").first.map(String.init) ?? path {
        case "/json":
            write(c, "200 OK", ["Content-Type: application/json", "X-Seen-Env: \(header("X-Env"))", "X-Seen-Dot: \(header("X-Dot"))"],
                  Data(#"{"token":"abc","items":[{"id":7},{"id":8}],"ok":true,"nested":{"a":[],"b":{}}}"#.utf8))
        case "/echo":
            let obj: [String: Any] = ["method": method, "auth": header("Authorization"), "ctype": header("Content-Type"),
                                      "body": String(decoding: body, as: UTF8.self), "query": path]
            write(c, "201 Created", ["Content-Type: application/json"], (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
        case "/html":
            write(c, "200 OK", ["Content-Type: text/html; charset=utf-8"], Data("<html><head><title>T</title></head><body><p>hi<br>there</p><script>var a = 1;</script></body></html>".utf8))
        case "/big":
            write(c, "200 OK", ["Content-Type: application/octet-stream"], Data(repeating: 0x41, count: 6 * 1024 * 1024))
        case "/slow":
            Thread.sleep(forTimeInterval: 2.5)
            write(c, "200 OK", [], Data("late".utf8))
        default:
            write(c, "404 Not Found", ["Content-Type: text/plain"], Data("nope".utf8))
        }
    }
}

/// CE_SELFTEST: HTTP client parser, variables, chaining, formatting, gutter markers and the runner against a loopback server.
enum SelfTestHttp {
    private static func check(_ n: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("http: " + n, ok()) }

    static func run(w: ProjectWindow, then done: @escaping () -> Void) {
        parserChecks()
        variableChecks()
        formatChecks()
        guard let server = LoopbackHTTPServer() else { check("loopback server starts", false); done(); return }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-http-\(getpid())")
        try? fm.createDirectory(at: dir.appendingPathComponent("api"), withIntermediateDirectories: true)
        runnerChecks(w: w, server: server, dir: dir) {
            server.stop()
            try? fm.removeItem(at: dir)
            done()
        }
    }

    // MARK: parser

    private static let sample = """
    @host = http://example.test
    @token=abc

    ### Login
    # @name login
    POST {{host}}/login HTTP/1.1
    Content-Type: application/json
    # a comment between headers
    X-A: 1

    {"user": "a",
     "pass": "b"}

    ### List
    // @name list
    GET {{host}}/items
        ?page=2
        &q=x
    Accept: */*

    ###
    https://example.test/bare

    ###
    DELETE {{host}}/items/1
    """

    private static func parserChecks() {
        let doc = HttpDocument.parse(sample)
        check("parser finds 4 requests", doc.requests.count == 4)
        check("parser reads @vars", doc.variables.count == 2 && doc.variables[0].name == "host" && doc.variables[1].value == "abc")
        let r0 = doc.requests[0]
        check("parser: name, method, url sans HTTP/1.1", r0.name == "login" && r0.method == "POST" && r0.url == "{{host}}/login")
        check("parser: title after ###", r0.title == "Login")
        check("parser: headers (comment skipped)", r0.headers.count == 2 && r0.headers[1].name == "X-A" && r0.headers[1].value == "1")
        check("parser: multi-line body", r0.body == "{\"user\": \"a\",\n \"pass\": \"b\"}")
        check("parser: request line numbers", r0.line == 6 && doc.requests[1].line == 16)
        check("parser: continuation lines join url", doc.requests[1].url == "{{host}}/items?page=2&q=x" && doc.requests[1].name == "list")
        check("parser: bare URL means GET", doc.requests[2].method == "GET" && doc.requests[2].url == "https://example.test/bare")
        check("parser: last request without trailing newline", doc.requests[3].method == "DELETE" && doc.requests[3].body == nil)
        check("request(atLine:) maps block lines", doc.request(atLine: 12)?.name == "login" && doc.request(atLine: 18)?.name == "list" && doc.request(atLine: 1) == nil)
        check("request(named:)", doc.request(named: "list")?.method == "GET")
        check("CRLF files parse", HttpDocument.parse("GET http://a.test/x\r\nAccept: a\r\n\r\nbody\r\n").requests.first?.body == "body")
        check("empty / comment-only file has no requests", HttpDocument.parse("").requests.isEmpty && HttpDocument.parse("# nothing\n###\n").requests.isEmpty)

        // Lexer: methods, header names, templates, comments.
        var spans: [(String, String)] = []
        let text = "### t\n# @name x\nGET {{host}}/a HTTP/1.1\nAccept: {{t}}\n\n{\"a\": \"{{b}}\"}\n"
        let u = Array(text.utf16)
        HttpLexer.lex(u, base: 0) { lo, hi, name in spans.append((String(utf16CodeUnits: Array(u[lo..<hi]), count: hi - lo), name)) }
        check("lexer: GET keyword, header property, comments", spans.contains { $0 == ("GET", "keyword") } && spans.contains { $0 == ("Accept", "property") }
              && spans.contains { $0.1 == "comment" && $0.0.hasPrefix("###") } && spans.contains { $0 == ("@name", "keyword") })
        check("lexer: {{templates}} in url, header and body", spans.filter { $0.1 == "variable.builtin" }.map(\.0) == ["{{host}}", "{{t}}", "{{b}}"])
        check(".http / .rest map to the http grammar", Languages.key(forFileName: "a.http") == "http" && Languages.key(forFileName: "x/b.REST") == "http"
              && Languages.grammar(forKey: "http")?.lexer != nil)
    }

    // MARK: variables

    private static func variableChecks() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-httpvars-\(getpid())")
        try? fm.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try? #"{"$shared": {"a": "shared", "n": 5}, "dev": {"host": "http://dev", "flag": true}, "prod": {"host": "http://prod"}}"#
            .write(to: root.appendingPathComponent("http-client.env.json"), atomically: true, encoding: .utf8)
        try? #"{"dev": {"host": "http://dev-private", "secret": "s3"}}"#
            .write(to: root.appendingPathComponent("http-client.private.env.json"), atomically: true, encoding: .utf8)
        try? "# c\nexport DOT=\"quoted value\"\nPLAIN=x # trailing\nHOST=http://dotenv\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let file = root.appendingPathComponent("sub/a.http")
        let envs = HttpEnvironments.load(near: file, root: root)
        check("env names exclude $shared", HttpEnvironments.names(envs) == ["dev", "prod"])
        let dev = HttpEnvironments.variables(envs, env: "dev")
        check("private env overrides public, $shared merges, non-strings stringify",
              dev["host"] == "http://dev-private" && dev["secret"] == "s3" && dev["a"] == "shared" && dev["n"] == "5" && dev["flag"] == "true")
        check("no env selected leaves only $shared", HttpEnvironments.variables(envs, env: nil)["host"] == nil)
        let dot = HttpEnvironments.loadDotenv(root: root)
        check(".env parsing (export, quotes, trailing comment)", dot["DOT"] == "quoted value" && dot["PLAIN"] == "x" && dot["HOST"] == "http://dotenv")

        let body = HttpResponse(status: 200, headers: [("Content-Type", "application/json"), ("X-Req", "r1")],
                                body: Data(#"{"data":{"id":42,"tags":["a","b"],"on":true,"nil":null},"list":[{"k":"v"}]}"#.utf8),
                                totalBytes: 10, truncated: false, duration: 0.1)
        var r = HttpResolver(fileVariables: ["x": "file", "ref": "{{x}}-{{host}}"], environment: dev, dotenv: dot, responses: ["login": body])
        func ex(_ s: String) -> String { r.expand(s).text }
        check("file var beats env beats .env", ex("{{x}}") == "file" && ex("{{host}}") == "http://dev-private" && ex("{{DOT}}") == "quoted value")
        check("nested variables resolve", ex("{{ref}}") == "file-http://dev-private")
        check("chain: body json path", ex("{{login.response.body.$.data.id}}") == "42" && ex("{{login.response.body.$.data.tags[1]}}") == "b"
              && ex("{{login.response.body.$.list[0].k}}") == "v" && ex("{{login.response.body.$.data.tags[-1]}}") == "b")
        check("chain: bool/null/object values", ex("{{login.response.body.$.data.on}}") == "true" && ex("{{login.response.body.$.data.nil}}") == "null"
              && ex("{{login.response.body.$.list[0]}}") == #"{"k":"v"}"#)
        check("chain: headers are case-insensitive", ex("{{login.response.headers.x-req}}") == "r1" && ex("{{login.response.headers.Content-Type}}") == "application/json")
        check("chain: whole body", ex("{{login.response.body.*}}").hasPrefix("{\"data\""))
        let miss = r.expand("{{nope}} {{login.response.body.$.zzz}} {{other.response.body.$.a}}")
        check("unresolved are kept and reported", miss.unresolved.count == 3 && miss.text.contains("{{nope}}"))
        check("dynamic variables", ex("{{$uuid}}").count == 36 && Int(ex("{{$timestamp}}")) != nil && Int(ex("{{$randomInt 5 5}}")) == 5)
        check("referencedResponses finds chained names", HttpResolver.referencedResponses(in: "a {{login.response.body.$.x}} {{host}} {{b.response.headers.H}}") == ["login", "b"])
        r.responses = [:]
        check("no responses: chain unresolved", !r.expand("{{login.response.body.$.data.id}}").unresolved.isEmpty)
        check("Basic auth helper encodes user:pass", HttpRunner.basicAuth("Basic user:pw") == "Basic dXNlcjpwdw==" && HttpRunner.basicAuth("Basic dXNlcjpwdw==") == "Basic dXNlcjpwdw==")
        try? fm.removeItem(at: root)
    }

    // MARK: formatting

    private static func formatChecks() {
        let j = HttpFormat.json(#"{"b":1,"a":[1,2,{"x":"q\"uo,te"}],"e":[],"o":{}}"#)
        check("json pretty-print keeps key order, escapes and empty containers",
              j == "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2,\n    {\n      \"x\": \"q\\\"uo,te\"\n    }\n  ],\n  \"e\": [],\n  \"o\": {}\n}")
        check("invalid json is not reformatted", HttpFormat.json("{nope") == nil)
        let h = HttpFormat.html("<html><head><title>T</title></head><body><p>hi<br>there</p><script>var a = 1;</script></body></html>")
        check("html pretty-print indents and keeps raw script", h.contains("\n  <head>\n    <title>\n      T") && h.contains("<p>\n      hi\n      <br>\n      there") && h.contains("var a = 1;"))
        let r = HttpResponse(status: 200, headers: [("Content-Type", "application/json")], body: Data("{\"a\":1}".utf8), totalBytes: 7, truncated: false, duration: 0)
        check("body(of:) pretty-prints json by content type", HttpFormat.body(of: r) == "{\n  \"a\": 1\n}")
        let bin = HttpResponse(status: 200, headers: [("Content-Type", "image/png")], body: Data([0xff, 0xfe, 0x00, 0x80]), totalBytes: 4, truncated: false, duration: 0)
        check("binary body shows a notice", HttpFormat.body(of: bin).hasPrefix("Binary body"))
    }

    // MARK: runner (loopback)

    private static func runnerChecks(w: ProjectWindow, server: LoopbackHTTPServer, dir: URL, then done: @escaping () -> Void) {
        let base = "http://127.0.0.1:\(server.port)"
        try? #"{"local": {"envname": "local-env"}, "other": {"envname": "other-env"}}"#.write(to: dir.appendingPathComponent("http-client.env.json"), atomically: true, encoding: .utf8)
        try? "DOTVAR=from-dotenv\n".write(to: dir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let file = dir.appendingPathComponent("api/main.http")
        let text = """
        @host = \(base)

        ### Login
        # @name login
        GET {{host}}/json
        X-Env: {{envname}}
        X-Dot: {{DOTVAR}}

        ### Use
        POST {{host}}/echo?x=1
        Authorization: Bearer {{login.response.body.$.token}}
        Content-Type: application/json

        {"id": {{login.response.body.$.items[0].id}}}

        ### Html
        GET {{host}}/html

        ### Big
        GET {{host}}/big

        ### Slow
        GET {{host}}/slow

        ### Missing
        GET {{host}}/{{undefinedVar}}

        ### Bad
        GET http://127.0.0.1:1/refused
        """
        try? text.write(to: file, atomically: true, encoding: .utf8)
        let panel = HttpPanelController(root: dir)
        HttpSystem.register(panel)
        let doc = HttpDocument.parse(text)
        func req(_ name: String) -> HttpRequest { doc.requests.first { $0.title == name }! }

        // Gutter markers on an opened .http file.
        w.open(file)
        if let tab = w.current, let g = HttpSystem.gutter(of: tab) {
            check("gutter: one play marker per request", g.playLines == Set(doc.requests.map(\.line)) && g.playLines.count == 7)
            check("gutter: click handler wired and panel found by root", g.onPlayClick != nil && HttpSystem.panel(for: file) === panel)
            tab.textView.string += "\n###\nGET http://x.test/new\n"
            tab.textView.didChangeText()
            HttpSystem.binding(for: tab)?.refresh()
            check("gutter: markers follow edits", g.playLines.count == 8)
            w.close(file.standardizedFileURL.path)
        } else { check("gutter: http tab has a gutter", false) }

        panel.loadEnvironments(for: file)
        check("panel lists environments", panel.environmentNames == ["local", "other"])
        panel.selectEnvironment("local")

        // 1. Dependency auto-run + chaining + env + .env.
        panel.run(req("Use"), document: doc, file: file) { use in
            check("chained run: ok status 201 + elapsed time + size", use.response?.status == 201 && (use.response?.duration ?? 0) > 0 && (use.response?.totalBytes ?? 0) > 10)
            let echoed = (try? JSONSerialization.jsonObject(with: use.response?.body ?? Data())) as? [String: Any]
            check("chained run: header + body substituted from login response", echoed?["auth"] as? String == "Bearer abc" && echoed?["body"] as? String == #"{"id": 7}"# && echoed?["method"] as? String == "POST")
            check("chained run: query kept", (echoed?["query"] as? String) == "/echo?x=1")
            check("dependency ran first and is in history", panel.runner.history.count == 2 && panel.runner.history[0].request.name == "login")
            let login = panel.runner.history[0].response
            check("environment + .env vars reach the request", login?.headers.first { $0.name.lowercased() == "x-seen-env" }?.value == "local-env"
                  && login?.headers.first { $0.name.lowercased() == "x-seen-dot" }?.value == "from-dotenv")
            check("panel shows pretty body and status", panel.copyText.contains("\"auth\"") && panel.status.stringValue.hasPrefix("201 Created"))
            panel.selectedTab = .headers
            check("headers tab lists response headers", panel.copyText.lowercased().contains("content-type: application/json"))
            panel.selectedTab = .request
            check("request tab shows resolved request", panel.copyText.hasPrefix("POST \(base)/echo?x=1") && panel.copyText.contains("Authorization: Bearer abc"))
            panel.selectedTab = .body

            // 2. Environment switch changes the substituted value.
            panel.selectEnvironment("other")
            panel.run(req("Login"), document: doc, file: file) { other in
                check("switching environment re-resolves variables", other.response?.headers.first { $0.name.lowercased() == "x-seen-env" }?.value == "other-env")
                html()
            }
        }

        // 3. HTML, save, truncation.
        func html() {
            panel.run(req("Html"), document: doc, file: file) { x in
                check("html response is pretty-printed in the viewer", panel.copyText.contains("\n  <head>"))
                let out = dir.appendingPathComponent("saved.html")
                try? panel.save(to: out)
                check("save writes the body to a file", (try? Data(contentsOf: out)) == x.response?.body)
                big()
            }
        }
        func big() {
            let before = rss()
            panel.run(req("Big"), document: doc, file: file) { x in
                let r = x.response
                check("body capped at 5 MB with truncation flag", r?.body.count == HttpRunner.maxBodyBytes && r?.truncated == true && r?.totalBytes == 6 * 1024 * 1024)
                check("truncation notice shown", panel.copyText.contains("truncated") || panel.copyText.contains("Binary"))
                fputs("http big rss delta \(rss() - before) MB\n", stderr)
                check("big response does not balloon memory", rss() - before < 120)
                missing()
            }
        }
        func missing() {
            panel.run(req("Missing"), document: doc, file: file) { x in
                check("unresolved variable is reported without sending", x.response == nil && x.error?.contains("{{undefinedVar}}") == true)
                refused()
            }
        }
        func refused() {
            panel.run(req("Bad"), document: doc, file: file) { x in
                check("connection failure surfaces an error", x.response == nil && x.error != nil)
                timeout()
            }
        }
        func timeout() {
            HttpRunner.timeout = 0.4
            panel.run(req("Slow"), document: doc, file: file) { x in
                HttpRunner.timeout = 30
                check("timeout is enforced", x.error?.contains("timed out") == true)
                cancel()
            }
        }
        func cancel() {
            var fired = false
            panel.run(req("Slow"), document: doc, file: file) { _ in fired = true }
            check("request is running", panel.runner.isRunning)
            panel.runner.cancel()
            check("cancel stops the run", !panel.runner.isRunning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                check("cancelled run never delivers a result", !fired)
                history()
            }
        }
        func history() {
            var n = 0
            func next() {
                if n == 25 {
                    check("history keeps only the last \(HttpRunner.maxHistory) exchanges", panel.runner.history.count == HttpRunner.maxHistory)
                    panel.show(panel.runner.history.last)
                    check("history popup lists them", panel.historyPopup.numberOfItems == HttpRunner.maxHistory)
                    check("named responses are bounded", panel.runner.named.count <= HttpRunner.maxHistory)
                    done()
                    return
                }
                n += 1
                panel.runner.run(req("Html"), document: doc, file: file, root: dir, environment: "local") { _ in next() }
            }
            next()
        }
    }

    private static func rss() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }
}
