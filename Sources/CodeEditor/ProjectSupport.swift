import AppKit

extension GitRepo {
    /// `repoRoot(for:)` runs `git` synchronously; this variant keeps it off the main thread.
    static func repoRoot(for url: URL, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let root = repoRoot(for: url)
            DispatchQueue.main.async { completion(root) }
        }
    }
}

/// Collects bursts of file-system events and delivers them once, after `interval` of quiet (trailing debounce).
final class ChangeCoalescer {
    var interval: TimeInterval
    private let handler: (Set<String>) -> Void
    private var pending = Set<String>()
    private var work: DispatchWorkItem?
    private(set) var deliveries = 0
    /// A pure trailing debounce starves while something keeps writing under the project (queue worker, agent, cache): the
    /// tree and index would never refresh. A batch is therefore delivered at most `maxWait` after its first event.
    var maxWait: TimeInterval = 3
    private var firstPending: Date?

    init(interval: TimeInterval = 0.75, handler: @escaping (Set<String>) -> Void) {
        self.interval = interval
        self.handler = handler
    }

    func add(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        pending.formUnion(paths)
        work?.cancel()
        let first = firstPending ?? Date()
        firstPending = first
        let delay = Self.delay(interval: interval, maxWait: maxWait, waited: -first.timeIntervalSinceNow)
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Trailing-debounce delay, shortened so the batch is never held longer than `maxWait` in total.
    static func delay(interval: TimeInterval, maxWait: TimeInterval, waited: TimeInterval) -> TimeInterval {
        max(0, min(interval, maxWait - waited))
    }

    private func flush() {
        let batch = pending
        pending = []
        work = nil
        firstPending = nil
        guard !batch.isEmpty else { return }
        deliveries += 1
        handler(batch)
    }

    func cancel() { work?.cancel(); work = nil; pending = []; firstPending = nil }
}

/// Editor-area message for a file that cannot be opened as plain text, with buttons to open it another way.
final class LoadProblemView: NSView {
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let buttons = NSStackView()
    private var runs: [NSButton: () -> Void] = [:]
    var message: String { title.stringValue }
    private(set) var actionTitles: [String] = []

    init(message: String, detail text: String, actions: [(String, () -> Void)]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        title.stringValue = message
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = Theme.foreground
        detail.stringValue = text
        detail.textColor = Theme.gutter
        buttons.spacing = 8
        let stack = NSStackView(views: [title, detail, buttons])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        actions.forEach { addAction($0.0, $0.1) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func addAction(_ name: String, _ run: @escaping () -> Void) {
        let b = NSButton(title: name, target: self, action: #selector(fire(_:)))
        b.bezelStyle = .rounded
        runs[b] = run
        actionTitles.append(name)
        buttons.addArrangedSubview(b)
    }

    func perform(_ index: Int) {
        if buttons.arrangedSubviews.indices.contains(index), let b = buttons.arrangedSubviews[index] as? NSButton { runs[b]?() }
    }
    @objc private func fire(_ b: NSButton) { runs[b]?() }
}

/// "42" or "42:7" typed into Go to Line.
enum GoToLineInput {
    static func parse(_ text: String) -> (line: Int, column: Int)? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard (1...2).contains(parts.count), let line = Int(parts[0]), line >= 1 else { return nil }
        if parts.count == 2 {
            if parts[1].isEmpty { return (line, 1) }
            guard let column = Int(parts[1]), column >= 1 else { return nil }
            return (line, column)
        }
        return (line, 1)
    }
}
