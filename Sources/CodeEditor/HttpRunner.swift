import Foundation

/// A finished (or failed) HTTP response. The body is capped at `HttpRunner.maxBodyBytes`; `totalBytes` is what the server sent.
struct HttpResponse {
    var status: Int
    var headers: [(name: String, value: String)]
    var body: Data
    var totalBytes: Int
    var truncated: Bool
    var duration: TimeInterval

    var statusText: String { HTTPURLResponse.localizedString(forStatusCode: status).capitalized }
    var contentType: String { headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value ?? "" }
    /// UTF-8 text of the (possibly truncated) body; nil for binary data.
    var bodyText: String? {
        if let s = String(data: body, encoding: .utf8) { return s }
        // A cap can cut a multi-byte character in half.
        if truncated, body.count > 4, let s = String(data: body.dropLast(3), encoding: .utf8) { return s }
        return nil
    }
}

/// One request/response pair as shown in the panel.
struct HttpExchange {
    var request: HttpRequest
    /// Request after variable substitution.
    var method: String
    var url: String
    var headers: [(name: String, value: String)]
    var body: String?
    var response: HttpResponse?
    var error: String?
    var date = Date()
    var fileName: String
}

/// Executes requests with an ephemeral URLSession (no cookies, cache or credential storage on disk), resolves variables and
/// chained responses, and keeps the last `maxHistory` exchanges. Main-thread API.
final class HttpRunner {
    static let maxBodyBytes = 5 * 1024 * 1024
    static let maxHistory = 20
    static var timeout: TimeInterval = 30

    private(set) var history: [HttpExchange] = []
    /// Named responses for `{{name.response...}}` chaining (bounded: at most `maxHistory` names).
    private(set) var named: [String: HttpResponse] = [:]
    private var namedOrder: [String] = []
    private var current: Token?

    var isRunning: Bool { current != nil }

    /// Cancels the in-flight request(s), if any.
    func cancel() { current?.cancel(); current = nil }

    func clearNamed() { named.removeAll(); namedOrder.removeAll() }

    func remember(name: String, response: HttpResponse) {
        if named[name] == nil { namedOrder.append(name) }
        named[name] = response
        while namedOrder.count > Self.maxHistory { named.removeValue(forKey: namedOrder.removeFirst()) }
    }

    private func record(_ x: HttpExchange) {
        history.append(x)
        if history.count > Self.maxHistory { history.removeFirst(history.count - Self.maxHistory) }
        if let n = x.request.name, let r = x.response { remember(name: n, response: r) }
    }

    final class Token { var urlTask: URLSessionTask?; var session: URLSession?; var cancelled = false
        func cancel() { cancelled = true; urlTask?.cancel(); session?.invalidateAndCancel() } }

    /// Runs `request` of `document` (first running named requests it depends on). `completion` runs on the main queue.
    func run(_ request: HttpRequest, document: HttpDocument, file: URL, root: URL?, environment: String?,
             completion: @escaping (HttpExchange) -> Void) {
        cancel()
        let token = Token()
        current = token
        let envs = HttpEnvironments.load(near: file, root: root)
        var resolver = HttpResolver(fileVariables: Dictionary(document.variables.map { ($0.name, $0.value) }, uniquingKeysWith: { _, b in b }),
                                    environment: HttpEnvironments.variables(envs, env: environment),
                                    dotenv: HttpEnvironments.loadDotenv(root: root))
        resolver.responses = named
        step(request, document, file, resolver, token, depth: 0) { [weak self] exchange in
            guard let self else { return }
            if self.current === token { self.current = nil }
            if !token.cancelled { completion(exchange) }
        }
    }

    /// Runs missing dependencies (named requests referenced via `{{name.response...}}`), then the request itself.
    private func step(_ request: HttpRequest, _ doc: HttpDocument, _ file: URL, _ resolver: HttpResolver, _ token: Token, depth: Int,
                      completion: @escaping (HttpExchange) -> Void) {
        var resolver = resolver
        let texts = [request.url, request.body ?? ""] + request.headers.map(\.value)
        let missing = texts.flatMap { HttpResolver.referencedResponses(in: $0) }
            .filter { resolver.responses[$0] == nil && $0 != request.name && doc.request(named: $0) != nil }
        if let dep = missing.first, depth < 8, let depReq = doc.request(named: dep) {
            step(depReq, doc, file, resolver, token, depth: depth + 1) { [weak self] ex in
                guard let self else { return }
                if let r = ex.response, ex.error == nil { resolver.responses[dep] = r; self.step(request, doc, file, resolver, token, depth: depth, completion: completion) }
                else { completion(ex) }
            }
            return
        }
        send(request, resolver, file, token) { [weak self] ex in
            self?.record(ex)
            completion(ex)
        }
    }

    private func fail(_ request: HttpRequest, _ message: String, file: URL, url: String? = nil) -> HttpExchange {
        HttpExchange(request: request, method: request.method, url: url ?? request.url, headers: request.headers, body: request.body,
                     response: nil, error: message, fileName: file.lastPathComponent)
    }

    private func send(_ request: HttpRequest, _ resolver: HttpResolver, _ file: URL, _ token: Token, completion: @escaping (HttpExchange) -> Void) {
        var unresolved: [String] = []
        func sub(_ s: String) -> String { let r = resolver.expand(s); unresolved += r.unresolved; return r.text }
        let urlText = sub(request.url).trimmingCharacters(in: .whitespacesAndNewlines)
        var headers = request.headers.map { (name: $0.name, value: sub($0.value)) }
        var body: Data?
        var bodyText = request.body.map(sub)
        if let t = bodyText?.trimmingCharacters(in: .whitespacesAndNewlines), t.hasPrefix("< "), !t.contains("\n") {
            let path = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : file.deletingLastPathComponent().appendingPathComponent(path)
            guard let d = try? Data(contentsOf: url) else {
                completion(fail(request, "Cannot read body file \(path)", file: file, url: urlText)); return
            }
            body = d; bodyText = "< \(path) (\(d.count) bytes)"
        } else if let t = bodyText { body = Data(t.utf8) }
        for i in headers.indices where headers[i].name.caseInsensitiveCompare("Authorization") == .orderedSame {
            headers[i].value = Self.basicAuth(headers[i].value)
        }
        var exchange = HttpExchange(request: request, method: request.method, url: urlText, headers: headers, body: bodyText,
                                    response: nil, error: nil, fileName: file.lastPathComponent)
        guard unresolved.isEmpty else {
            exchange.error = "Unresolved variable" + (Set(unresolved).count == 1 ? "" : "s") + ": " + Set(unresolved).sorted().map { "{{\($0)}}" }.joined(separator: ", ")
            completion(exchange); return
        }
        var full = urlText
        if !full.contains("://") { full = "http://" + full }
        guard let url = URL(string: full) ?? URL(string: full.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(CharacterSet(charactersIn: "%#"))) ?? ""),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            exchange.error = "Invalid URL: \(urlText)"
            completion(exchange); return
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: Self.timeout)
        req.httpMethod = request.method
        req.httpShouldHandleCookies = false
        for h in headers { req.addValue(h.value, forHTTPHeaderField: h.name) }
        if request.method != "GET" && request.method != "HEAD" { req.httpBody = body } else if let body, !body.isEmpty { req.httpBody = body }
        exchange.url = url.absoluteString

        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = Self.timeout
        cfg.timeoutIntervalForResource = Self.timeout * 4
        let delegate = Collector(cap: Self.maxBodyBytes)
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        let start = CFAbsoluteTimeGetCurrent()
        let task = session.dataTask(with: req)
        token.session = session
        token.urlTask = task
        delegate.onFinish = { response, error in
            DispatchQueue.main.async {
                session.finishTasksAndInvalidate()
                var x = exchange
                if token.cancelled { x.error = "Cancelled"; completion(x); return }
                if let error = error as NSError? {
                    x.error = error.code == NSURLErrorTimedOut ? "Request timed out after \(Int(Self.timeout)) s" : error.localizedDescription
                } else if let http = response as? HTTPURLResponse {
                    let hs = http.allHeaderFields.compactMap { k, v -> (name: String, value: String)? in
                        guard let k = k as? String else { return nil }
                        return (k, "\(v)")
                    }.sorted { $0.name.lowercased() < $1.name.lowercased() }
                    x.response = HttpResponse(status: http.statusCode, headers: hs, body: delegate.body, totalBytes: delegate.total,
                                              truncated: delegate.total > delegate.body.count, duration: CFAbsoluteTimeGetCurrent() - start)
                }
                completion(x)
            }
        }
        task.resume()
    }

    /// `Basic user:password` / `Basic user password` -> base64; an already encoded value is left alone.
    static func basicAuth(_ value: String) -> String {
        let t = value.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("basic ") else { return value }
        let cred = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        if cred.contains(":") { return "Basic " + Data(cred.utf8).base64EncodedString() }
        if let sp = cred.firstIndex(of: " ") {
            let user = cred[..<sp], pass = cred[cred.index(after: sp)...].trimmingCharacters(in: .whitespaces)
            return "Basic " + Data("\(user):\(pass)".utf8).base64EncodedString()
        }
        return value
    }

    /// Accumulates the body up to a cap (further bytes are only counted), so a huge download cannot grow memory.
    private final class Collector: NSObject, URLSessionDataDelegate {
        let cap: Int
        var body = Data()
        var total = 0
        var response: URLResponse?
        var onFinish: ((URLResponse?, Error?) -> Void)?
        init(cap: Int) { self.cap = cap }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.response = response
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            total += data.count
            if body.count < cap { body.append(data.prefix(cap - body.count)) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let f = onFinish
            onFinish = nil
            f?(response, error)
        }
    }
}
