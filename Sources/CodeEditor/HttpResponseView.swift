import AppKit

/// Order-preserving pretty printers for response bodies (JSONSerialization would shuffle keys).
enum HttpFormat {
    /// Bodies above this are shown as received (formatting is O(n) but allocates a second copy).
    static let formatLimit = 1_000_000
    /// The viewer shows at most this much text; Save writes the whole stored body.
    static let displayLimit = 500_000

    static func json(_ text: String) -> String? {
        guard let data = text.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else { return nil }
        let c = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var depth = 0
        var i = 0
        func newline() { out.append("\n"); for _ in 0..<depth { out.append(" "); out.append(" ") } }
        func nextNonSpace(_ from: Int) -> Unicode.Scalar? {
            var k = from
            while k < c.count, c[k] == " " || c[k] == "\n" || c[k] == "\t" || c[k] == "\r" { k += 1 }
            return k < c.count ? c[k] : nil
        }
        while i < c.count {
            let ch = c[i]
            switch ch {
            case " ", "\n", "\t", "\r": break
            case "\"":
                out.append(ch); i += 1
                while i < c.count {
                    out.append(c[i])
                    if c[i] == "\\", i + 1 < c.count { i += 1; out.append(c[i]) } else if c[i] == "\"" { break }
                    i += 1
                }
            case "{", "[":
                out.append(ch)
                let close: Unicode.Scalar = ch == "{" ? "}" : "]"
                if nextNonSpace(i + 1) == close {
                    out.append(close)
                    var k = i + 1; while c[k] != close { k += 1 }
                    i = k
                } else { depth += 1; newline() }
            case "}", "]":
                depth = max(0, depth - 1); newline(); out.append(ch)
            case ",": out.append(ch); newline()
            case ":": out.append(":"); out.append(" ")
            default: out.append(ch)
            }
            i += 1
        }
        return String(out)
    }

    private static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr", "!doctype"]
    private static let rawTags: Set<String> = ["script", "style", "pre", "textarea"]

    static func html(_ text: String) -> String {
        let s = text as NSString
        var out: [String] = []
        var depth = 0
        var pos = 0
        func emit(_ t: String) {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(String(repeating: "  ", count: max(0, depth)) + trimmed) }
        }
        while pos < s.length {
            let lt = s.range(of: "<", range: NSRange(location: pos, length: s.length - pos))
            if lt.location == NSNotFound { emit(s.substring(from: pos)); break }
            if lt.location > pos { emit(s.substring(with: NSRange(location: pos, length: lt.location - pos))) }
            if s.substring(from: lt.location).hasPrefix("<!--") {
                let e = s.range(of: "-->", range: NSRange(location: lt.location, length: s.length - lt.location))
                let end = e.location == NSNotFound ? s.length : NSMaxRange(e)
                emit(s.substring(with: NSRange(location: lt.location, length: end - lt.location))); pos = end; continue
            }
            // End of the tag, skipping quoted attribute values.
            var k = lt.location + 1
            var quote: unichar = 0
            while k < s.length {
                let ch = s.character(at: k)
                if quote != 0 { if ch == quote { quote = 0 } } else if ch == 34 || ch == 39 { quote = ch } else if ch == 62 { break }
                k += 1
            }
            let tagEnd = min(k + 1, s.length)
            let tag = s.substring(with: NSRange(location: lt.location, length: tagEnd - lt.location))
            let isClose = tag.hasPrefix("</")
            let nameStart = tag.dropFirst(isClose ? 2 : 1)
            let name = String(nameStart.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }).lowercased()
            let selfClosing = tag.hasSuffix("/>") || voidTags.contains(name) || name.hasPrefix("!")
            if isClose { depth = max(0, depth - 1); emit(tag); pos = tagEnd; continue }
            emit(tag)
            pos = tagEnd
            if selfClosing { continue }
            if rawTags.contains(name) {
                let closeRange = s.range(of: "</" + name, options: .caseInsensitive, range: NSRange(location: pos, length: s.length - pos))
                let endRaw = closeRange.location == NSNotFound ? s.length : closeRange.location
                let inner = s.substring(with: NSRange(location: pos, length: endRaw - pos))
                if !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(inner.trimmingCharacters(in: .newlines)) }
                pos = endRaw
                continue
            }
            depth += 1
        }
        return out.joined(separator: "\n")
    }

    /// Display text for a response body: pretty JSON / HTML when recognised, else the text as received.
    static func body(of r: HttpResponse) -> String {
        guard !r.body.isEmpty else { return "" }
        guard let text = r.bodyText else {
            return "Binary body (\(r.contentType.isEmpty ? "unknown type" : r.contentType), \(byteString(r.totalBytes))). Use Save to write it to a file."
        }
        var shown = text
        let ct = r.contentType.lowercased()
        if text.utf8.count <= formatLimit, !r.truncated {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if ct.contains("json") || ((t.hasPrefix("{") || t.hasPrefix("[")) && !ct.contains("html")), let j = json(text) { shown = j }
            else if ct.contains("html") || ct.contains("xhtml") { shown = html(text) }
        }
        if (shown as NSString).length > displayLimit {
            shown = (shown as NSString).substring(to: displayLimit) + "\n\n… output cut at \(byteString(displayLimit)); use Save for the full stored body."
        }
        if r.truncated {
            shown += "\n\n… response truncated: stored the first \(byteString(r.body.count)) of \(byteString(r.totalBytes))."
        }
        return shown
    }

    static func byteString(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1_048_576 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.1f MB", Double(n) / 1_048_576)
    }

    static func fileExtension(for r: HttpResponse) -> String {
        let ct = r.contentType.lowercased()
        if ct.contains("json") { return "json" }
        if ct.contains("html") { return "html" }
        if ct.contains("xml") { return "xml" }
        if ct.contains("css") { return "css" }
        if ct.contains("javascript") { return "js" }
        if ct.contains("png") { return "png" }
        if ct.contains("jpeg") { return "jpg" }
        if ct.contains("pdf") { return "pdf" }
        if ct.hasPrefix("text/") { return "txt" }
        return "bin"
    }
}

/// Bottom-panel tool "HTTP": environment picker, run/stop, history of the last responses, and a Body / Headers / Request viewer.
final class HttpPanelController: NSObject {
    let root: URL
    let runner = HttpRunner()
    let view = NSView()

    /// Wired by FeatureWiring: reveals the panel.
    var reveal: (() -> Void)?

    let envPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let historyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let runButton = NSButton()
    let stopButton = NSButton()
    let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    let saveButton = NSButton(title: "Save…", target: nil, action: nil)
    let status = NSTextField(labelWithString: "No request run yet. Click the ▶ in the gutter of a .http file.")
    let tabs = NSSegmentedControl(labels: ["Body", "Headers", "Request"], trackingMode: .selectOne, target: nil, action: nil)
    let text = NSTextView()
    private let scroll = NSScrollView()

    private(set) var shown: HttpExchange?
    private var lastRun: (request: HttpRequest, document: HttpDocument, file: URL)?
    private(set) var environmentNames: [String] = []
    private(set) var selectedEnvironment: String?
    private var historyIndexes: [Int] = []

    init(root: URL) {
        self.root = root
        super.init()
        selectedEnvironment = UserDefaults.standard.string(forKey: Self.envKey(root))
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
    }

    private static func envKey(_ root: URL) -> String { "httpEnv:" + root.standardizedFileURL.path }

    private func build() {
        envPopup.target = self; envPopup.action = #selector(envChanged)
        envPopup.controlSize = .small; envPopup.toolTip = "Environment (http-client.env.json)"
        historyPopup.target = self; historyPopup.action = #selector(historyChanged)
        historyPopup.controlSize = .small; historyPopup.toolTip = "Recent responses"
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run again")
        runButton.toolTip = "Run the last request again"
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Cancel")
        stopButton.toolTip = "Cancel the running request"
        for b in [runButton, stopButton] { b.isBordered = false; b.imageScaling = .scaleProportionallyDown; b.target = self }
        runButton.action = #selector(rerun); stopButton.action = #selector(cancelRun)
        copyButton.target = self; copyButton.action = #selector(copyClicked)
        saveButton.target = self; saveButton.action = #selector(saveClicked)
        for b in [copyButton, saveButton] { b.bezelStyle = .recessed; b.controlSize = .small }
        tabs.target = self; tabs.action = #selector(tabChanged)
        tabs.selectedSegment = 0
        tabs.controlSize = .small
        status.lineBreakMode = .byTruncatingTail
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bar = NSStackView(views: [runButton, stopButton, envPopup, historyPopup, tabs, status, NSView(), copyButton, saveButton])
        bar.orientation = .horizontal; bar.spacing = 8; bar.alignment = .centerY
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        bar.setHuggingPriority(.defaultLow, for: .horizontal)

        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.isVerticallyResizable = true; text.isHorizontallyResizable = true
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.allowsUndo = false
        scroll.documentView = text
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.drawsBackground = true

        for v in [bar, scroll] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 16), stopButton.widthAnchor.constraint(equalToConstant: 16),
        ])
        refreshChrome()
        restyle()
    }

    @objc private func themeChanged() { restyle(); show(shown) }

    private func restyle() {
        text.font = Theme.font
        text.textColor = Theme.foreground
        text.backgroundColor = Theme.background
        scroll.backgroundColor = Theme.background
        runButton.contentTintColor = NSColor(srgbRed: 0.30, green: 0.70, blue: 0.35, alpha: 1)
        stopButton.contentTintColor = NSColor(srgbRed: 0.90, green: 0.32, blue: 0.32, alpha: 1)
        refreshStatusColor()
    }

    // MARK: running

    /// Gutter ▶ / command: runs the request whose block contains `line` (1-based) in `text`.
    func run(text source: String, line: Int, file: URL) {
        let doc = HttpDocument.parse(source)
        guard let request = doc.request(atLine: line) else { return }
        run(request, document: doc, file: file)
    }

    func run(_ request: HttpRequest, document: HttpDocument, file: URL, completion: ((HttpExchange) -> Void)? = nil) {
        lastRun = (request, document, file)
        loadEnvironments(for: file)
        status.stringValue = "Running \(request.method) \(request.url) …"
        status.textColor = Theme.gutter
        refreshChrome(running: true)
        reveal?()
        runner.run(request, document: document, file: file, root: root, environment: selectedEnvironment) { [weak self] exchange in
            guard let self else { return }
            self.refreshChrome(running: false)
            self.show(exchange)
            completion?(exchange)
        }
    }

    @objc private func rerun() {
        guard let l = lastRun else { return }
        // Re-read the file from disk text if it is open? The remembered parse is what the user last ran.
        run(l.request, document: l.document, file: l.file)
    }

    @objc private func cancelRun() {
        runner.cancel()
        refreshChrome(running: false)
        status.stringValue = "Cancelled"
        status.textColor = Theme.gutter
    }

    // MARK: environments

    func loadEnvironments(for file: URL) {
        let envs = HttpEnvironments.load(near: file, root: root)
        environmentNames = HttpEnvironments.names(envs)
        if let s = selectedEnvironment, !environmentNames.contains(s) { selectedEnvironment = nil }
        if selectedEnvironment == nil, environmentNames.count == 1 { selectedEnvironment = environmentNames.first }
        envPopup.removeAllItems()
        envPopup.addItem(withTitle: "No Environment")
        envPopup.addItems(withTitles: environmentNames)
        envPopup.selectItem(withTitle: selectedEnvironment ?? "No Environment")
        envPopup.isHidden = environmentNames.isEmpty
    }

    func selectEnvironment(_ name: String?) {
        selectedEnvironment = name
        UserDefaults.standard.set(name, forKey: Self.envKey(root))
        envPopup.selectItem(withTitle: name ?? "No Environment")
    }

    @objc private func envChanged() {
        let t = envPopup.titleOfSelectedItem
        selectEnvironment(t == "No Environment" ? nil : t)
    }

    // MARK: showing

    enum Tab: Int { case body, headers, request }
    var selectedTab: Tab {
        get { Tab(rawValue: tabs.selectedSegment) ?? .body }
        set { tabs.selectedSegment = newValue.rawValue; show(shown) }
    }

    func show(_ x: HttpExchange?) {
        shown = x
        refreshHistory()
        guard let x else { text.string = ""; return }
        if let e = x.error { status.stringValue = e; status.textColor = NSColor(srgbRed: 0.90, green: 0.32, blue: 0.32, alpha: 1) }
        else if let r = x.response {
            status.stringValue = "\(r.status) \(r.statusText)  ·  \(Int((r.duration * 1000).rounded())) ms  ·  \(HttpFormat.byteString(r.totalBytes))"
                + (r.truncated ? "  ·  truncated" : "")
            refreshStatusColor()
        }
        switch selectedTab {
        case .body:
            text.string = x.error.map { "\($0)\n\n\(x.method) \(x.url)" } ?? x.response.map(HttpFormat.body(of:)) ?? ""
        case .headers:
            text.string = x.response?.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n") ?? ""
        case .request:
            var lines = ["\(x.method) \(x.url)"] + x.headers.map { "\($0.name): \($0.value)" }
            if let b = x.body { lines += ["", b] }
            text.string = lines.joined(separator: "\n")
        }
        text.scrollToBeginningOfDocument(nil)
        refreshChrome(running: runner.isRunning)
    }

    private func refreshStatusColor() {
        guard let r = shown?.response, shown?.error == nil else { return }
        switch r.status {
        case 200..<300: status.textColor = NSColor(srgbRed: 0.30, green: 0.70, blue: 0.35, alpha: 1)
        case 300..<400: status.textColor = NSColor(srgbRed: 0.27, green: 0.53, blue: 0.96, alpha: 1)
        case 400..<500: status.textColor = NSColor(srgbRed: 0.90, green: 0.60, blue: 0.20, alpha: 1)
        default: status.textColor = NSColor(srgbRed: 0.90, green: 0.32, blue: 0.32, alpha: 1)
        }
    }

    private func refreshChrome(running: Bool = false) {
        stopButton.isEnabled = running
        runButton.isEnabled = lastRun != nil && !running
        copyButton.isEnabled = shown != nil
        saveButton.isEnabled = shown?.response != nil
        refreshHistory()
    }

    private func refreshHistory() {
        historyPopup.removeAllItems()
        historyIndexes = []
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        for (i, x) in runner.history.enumerated().reversed() {
            let code = x.response.map { "\($0.status)" } ?? "ERR"
            let label = x.request.displayName == "\(x.method) \(x.request.url)" ? x.url : x.request.displayName
            // Menu items directly: addItem(withTitle:) drops an existing item with the same title.
            historyPopup.menu?.addItem(NSMenuItem(title: "\(f.string(from: x.date))  \(code)  \(x.method) \(label)", action: nil, keyEquivalent: ""))
            historyIndexes.append(i)
        }
        historyPopup.isHidden = runner.history.isEmpty
        if let s = shown, let i = runner.history.firstIndex(where: { $0.date == s.date && $0.url == s.url }), let pos = historyIndexes.firstIndex(of: i) {
            historyPopup.selectItem(at: pos)
        }
    }

    @objc private func historyChanged() {
        let pos = historyPopup.indexOfSelectedItem
        guard pos >= 0, pos < historyIndexes.count else { return }
        show(runner.history[historyIndexes[pos]])
    }

    @objc private func tabChanged() { show(shown) }

    // MARK: copy / save

    /// What Copy puts on the pasteboard: the visible tab's text.
    var copyText: String { text.string }

    @objc private func copyClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText, forType: .string)
    }

    @objc private func saveClicked() {
        guard let r = shown?.response else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "response." + HttpFormat.fileExtension(for: r)
        panel.directoryURL = root
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            do { try self?.save(to: url) } catch { NSSound.beep() }
        }
        if let w = view.window { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    /// Writes the stored (capped) response body to `url`.
    func save(to url: URL) throws {
        guard let r = shown?.response else { return }
        try r.body.write(to: url, options: .atomic)
    }
}

/// Wires `.http` / `.rest` editors: ▶ markers in the gutter that run the request, kept in sync with the text.
enum HttpSystem {
    static let extensions: Set<String> = ["http", "rest"]
    private static var started = false
    private static var panels: [HttpPanelController] = []
    private static var gutters: [ObjectIdentifier: HttpGutterBinding] = [:]

    static func isHttpFile(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            guard isHttpFile(tab.url), !tab.isLargeFile, let g = gutter(of: tab) else { return }
            let b = HttpGutterBinding(tab: tab, gutter: g)
            gutters[ObjectIdentifier(tab)] = b
            b.begin()
        }
        EditorEvents.onClose { tab in gutters.removeValue(forKey: ObjectIdentifier(tab))?.end() }
    }

    static func register(_ p: HttpPanelController) { panels.append(p) }

    /// The panel of the project that contains `file` (deepest root wins).
    static func panel(for file: URL) -> HttpPanelController? {
        let path = file.standardizedFileURL.path
        return panels.filter { path.hasPrefix($0.root.standardizedFileURL.path + "/") }
            .max { $0.root.path.count < $1.root.path.count }
    }

    static func gutter(of tab: EditorTab) -> GutterView? {
        ((tab.view as? EditorPane)?.contentView as? EditorContainer)?.gutter
    }

    static func binding(for tab: EditorTab) -> HttpGutterBinding? { gutters[ObjectIdentifier(tab)] }
}

final class HttpGutterBinding: NSObject {
    private weak var tab: EditorTab?
    private weak var gutter: GutterView?
    private var pending: DispatchWorkItem?

    init(tab: EditorTab, gutter: GutterView) { self.tab = tab; self.gutter = gutter }

    func begin() {
        guard let tab else { return }
        gutter?.onPlayClick = { [weak self] line in self?.run(line: line) }
        NotificationCenter.default.addObserver(self, selector: #selector(textChanged), name: NSText.didChangeNotification, object: tab.textView)
        refresh()
    }

    func end() {
        NotificationCenter.default.removeObserver(self)
        pending?.cancel()
        gutter?.playLines = []
        gutter?.onPlayClick = nil
    }

    @objc private func textChanged() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    func refresh() {
        guard let tab else { return }
        gutter?.playLines = Set(HttpDocument.parse(tab.textView.string).requests.map(\.line))
    }

    func run(line: Int) {
        guard let tab, let panel = HttpSystem.panel(for: tab.url) else { return }
        panel.run(text: tab.textView.string, line: line, file: tab.url)
    }
}
