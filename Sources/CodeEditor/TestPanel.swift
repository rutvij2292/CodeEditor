import AppKit

/// "Tests" tab of the bottom panel: toolbar (status, Re-run, Re-run Failed, Stop, Output), the result list of the last run,
/// and a text area showing the raw run output or the selected failure's message.
final class TestPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSView()
    var onRerun: (() -> Void)?
    var onRerunFailed: (() -> Void)?
    var onStop: (() -> Void)?
    var onOpen: ((String, Int) -> Void)?

    private let status = NSTextField(labelWithString: "")
    private let rerun = NSButton(title: "Re-run", target: nil, action: nil)
    private let rerunFailed = NSButton(title: "Re-run Failed", target: nil, action: nil)
    private let stop = NSButton(title: "Stop", target: nil, action: nil)
    private let outputButton = NSButton(title: "Output", target: nil, action: nil)
    private let toolbar = NSView()
    private let split = NSSplitView()
    private let table = NSTableView()
    private let tableScroll = NSScrollView()
    private let text = NSTextView()
    private let textScroll = NSScrollView()
    private var rows: [TestResult] = []
    private var positioned = false

    override init() {
        super.init()
        view.wantsLayer = true
        for (b, action) in [(rerun, #selector(rerunClicked)), (rerunFailed, #selector(rerunFailedClicked)),
                            (stop, #selector(stopClicked)), (outputButton, #selector(outputClicked))] {
            b.target = self; b.action = action
            b.bezelStyle = .recessed; b.controlSize = .small; b.font = .systemFont(ofSize: 11)
            toolbar.addSubview(b)
        }
        status.font = .systemFont(ofSize: 12)
        status.lineBreakMode = .byTruncatingTail
        toolbar.addSubview(status)
        view.addSubview(toolbar)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("t"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 18
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(doubleClicked)
        table.target = self
        table.usesAlternatingRowBackgroundColors = false
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true

        text.isEditable = false
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textContainerInset = NSSize(width: 6, height: 4)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        textScroll.documentView = text
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true

        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(tableScroll)
        split.addArrangedSubview(textScroll)
        view.addSubview(split)
        view.postsFrameChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(layoutSubviews), name: NSView.frameDidChangeNotification, object: view)
        nc.addObserver(self, selector: #selector(storeChanged(_:)), name: TestResultsStore.didChange, object: nil)
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        themeChanged()
        layoutSubviews()
        reload()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func layoutSubviews() {
        let w = view.bounds.width, h = view.bounds.height, th: CGFloat = 28
        toolbar.frame = NSRect(x: 0, y: h - th, width: w, height: th)
        split.frame = NSRect(x: 0, y: 0, width: w, height: max(0, h - th))
        var x = w - 8
        for b in [outputButton, stop, rerunFailed, rerun] {
            b.sizeToFit()
            x -= b.frame.width + 6
            b.frame = NSRect(x: x, y: (th - 20) / 2, width: b.frame.width + 6, height: 20)
            x -= 4
        }
        status.frame = NSRect(x: 10, y: (th - 16) / 2, width: max(0, x - 14), height: 16)
        if !positioned, w > 100 { positioned = true; split.setPosition(w * 0.45, ofDividerAt: 0) }
    }

    @objc private func themeChanged() {
        view.layer?.backgroundColor = Theme.background.cgColor
        table.backgroundColor = Theme.background
        text.backgroundColor = Theme.background
        text.textColor = Theme.foreground
        status.textColor = Theme.gutter
        table.reloadData()
    }

    @objc private func storeChanged(_ n: Notification) {
        if n.userInfo?["outputOnly"] != nil { if table.selectedRow < 0 { showOutput() }; return }
        reload()
    }

    func reload() {
        let store = TestResultsStore.shared
        rows = store.lastRun.filter(\.isFailure) + store.lastRun.filter { !$0.isFailure }
        table.reloadData()
        status.stringValue = store.statusLine
        stop.isEnabled = store.isRunning
        rerun.isEnabled = !store.isRunning && store.lastRequest != nil
        rerunFailed.isEnabled = !store.isRunning && !store.failed.isEmpty
        if table.selectedRow < 0 { showOutput() }
    }

    private func showOutput() {
        text.string = TestResultsStore.shared.output
        text.scrollToEndOfDocument(nil)
    }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let r = rows[row]
        let (glyph, color): (String, NSColor) = {
            switch r.status {
            case .passed: return ("✓", NSColor(calibratedRed: 0.25, green: 0.65, blue: 0.35, alpha: 1))
            case .failed, .errored: return ("✗", NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.25, alpha: 1))
            case .skipped: return ("○", NSColor.systemGray)
            }
        }()
        let s = NSMutableAttributedString(string: glyph + " ", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12, weight: .bold)])
        s.append(NSAttributedString(string: r.name, attributes: [.foregroundColor: Theme.foreground, .font: NSFont.systemFont(ofSize: 12)]))
        if r.time > 0 { s.append(NSAttributedString(string: String(format: "  %.2fs", r.time), attributes: [.foregroundColor: Theme.gutter, .font: NSFont.systemFont(ofSize: 11)])) }
        return s
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < rows.count else { return }
        let r = rows[table.selectedRow]
        text.string = r.message.isEmpty ? r.name : r.message
        text.scrollToBeginningOfDocument(nil)
    }

    @objc private func doubleClicked() {
        guard table.clickedRow >= 0, table.clickedRow < rows.count else { return }
        let r = rows[table.clickedRow]
        if !r.file.isEmpty { onOpen?(r.file, r.failureLine) }
    }

    @objc private func rerunClicked() { onRerun?() }
    @objc private func rerunFailedClicked() { onRerunFailed?() }
    @objc private func stopClicked() { onStop?() }
    @objc private func outputClicked() { table.deselectAll(nil); showOutput() }
}
