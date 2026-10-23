import AppKit

// MARK: - About

final class AboutPane: SettingsPane {
    static let repoURL = Brand.repoURL
    private var timer: Timer?
    private var historySize: UInt64?
    private var cacheSize: UInt64?

    private static var cachesRoot: URL { URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/CodeEditor", isDirectory: true) }

    override func build() {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "development build"
        let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        section(Brand.name)
        row("Version", infoLabel { version + build })
        row("Source", infoLabel { Self.repoURL })

        section("Memory")
        row("This app", infoLabel { SystemStats.megabytes(SystemStats.physFootprint()) + " physical footprint" })
        row("Language servers", infoLabel {
            let all = LanguageServers.statuses()
            return all.isEmpty ? "None running" : "\(all.count) running · " + SystemStats.megabytes(all.reduce(UInt64(0)) { $0 + $1.rssBytes })
        })
        row("Total", infoLabel {
            SystemStats.megabytes(SystemStats.physFootprint() + LanguageServers.statuses().reduce(UInt64(0)) { $0 + $1.rssBytes })
        })

        section("Caches and logs")
        row("Local History", infoLabel { [weak self] in self?.historySize.map(SystemStats.megabytes) ?? "Calculating…" })
        row(nil, button("Clear Local History…") { [weak self] in self?.clear("Local History", LocalHistory.root) })
        row("Index caches", infoLabel { [weak self] in self?.cacheSize.map(SystemStats.megabytes) ?? "Calculating…" },
            help: "Everything under ~/Library/Caches/CodeEditor, including Local History and the vendor index. They are rebuilt on demand.")
        row(nil, button("Clear Index Caches…") { [weak self] in self?.clear("index caches", Self.cachesRoot) })
        row(nil, button("Reveal Caches in Finder") {
            try? FileManager.default.createDirectory(at: Self.cachesRoot, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([Self.cachesRoot])
        })
        measure()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 1
    }

    override func viewDidDisappear() { super.viewDidDisappear(); timer?.invalidate(); timer = nil }

    private func measure() {
        let history = LocalHistory.root, caches = Self.cachesRoot
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let h = SystemStats.directorySize(history), c = SystemStats.directorySize(caches)
            DispatchQueue.main.async { self?.historySize = h; self?.cacheSize = c; self?.refresh() }
        }
    }

    private func clear(_ what: String, _ dir: URL) {
        guard confirm("Clear \(what)?", detail: "This deletes the cached files at \(dir.path). They are rebuilt when needed.", button: "Clear") else { return }
        try? FileManager.default.removeItem(at: dir)
        historySize = nil; cacheSize = nil
        refresh()
        measure()
    }
}
