import AppKit

// MARK: - Languages

final class LanguagesPane: SettingsPane {
    override var observedNotifications: [Notification.Name] { super.observedNotifications + [LanguageServers.statusDidChange] }
    /// Overridable for tests / headless rendering.
    var projectRoot: () -> URL? = { (NSApp.delegate as? AppDelegate)?.active?.root }
    private var toolsText = "Open a project to detect formatters."
    private var licenceField: NSSecureTextField?

    override func build() {
        section("PHP")
        let nativeOnly = NSButton(checkboxWithTitle: "Use native PHP engine only (stop Intelephense)", target: nil, action: nil)
        nativeOnly.target = action { c in NativePHP.setNativeOnly((c as? NSButton)?.state == .on) }
        nativeOnly.action = #selector(SettingsAction.fire(_:))
        nativeOnly.setAccessibilityLabel("Use native PHP engine only")
        onRefresh { nativeOnly.state = NativePHP.nativeOnly ? .on : .off }
        row(nil, nativeOnly, help: "Go to definition and hover come from Kode's built-in PHP index (about 0 MB extra). Intelephense (160-600 MB) is not started; features not yet native (find usages, rename, signature help) are unavailable meanwhile; diagnostics are native (see PHP diagnostics below). See docs/native-php.md.")

        section("PHP diagnostics")
        for g in NPDiagGroup.allCases {
            let box = NSButton(checkboxWithTitle: g.title, target: nil, action: nil)
            box.target = action { c in
                g.enabled = (c as? NSButton)?.state == .on
                NotificationCenter.default.post(name: NativePHPDiagController.settingsDidChange, object: nil)
            }
            box.action = #selector(SettingsAction.fire(_:))
            box.setAccessibilityLabel("PHP diagnostics: \(g.title)")
            onRefresh { box.state = g.enabled ? .on : .off }
            row(nil, box, help: g == .syntax ? "Native checks run after edits settle, for the open file only. Rules stay silent when they cannot be certain; with Intelephense running the same problem is never listed twice." : nil)
        }
        let severity = NSPopUpButton(frame: .zero, pullsDown: false)
        severity.addItems(withTitles: ["Warning", "Error"])
        severity.target = action { c in
            NativePHPDiag.classSeverity = (c as? NSPopUpButton)?.indexOfSelectedItem == 1 ? 1 : 2
            NotificationCenter.default.post(name: NativePHPDiagController.settingsDidChange, object: nil)
        }
        severity.action = #selector(SettingsAction.fire(_:))
        severity.setAccessibilityLabel("Severity of undefined classes")
        onRefresh { severity.selectItem(at: NativePHPDiag.classSeverity == 1 ? 1 : 0) }
        row("Undefined class severity", severity)

        section("HTML / CSS / Tailwind")
        let webOn = NSButton(checkboxWithTitle: "Native HTML, CSS and Tailwind services", target: nil, action: nil)
        webOn.target = action { c in NativeWeb.enabled = (c as? NSButton)?.state == .on }
        webOn.action = #selector(SettingsAction.fire(_:))
        webOn.setAccessibilityLabel("Native HTML, CSS and Tailwind services")
        onRefresh { webOn.state = NativeWeb.enabled ? .on : .off }
        row(nil, webOn, help: "Completion, hover and go to definition for CSS, HTML and Tailwind classes come from Kode itself (the Tailwind theme is read from tailwind.config.* or @theme, no node process).")
        let webOnly = NSButton(checkboxWithTitle: "Use native HTML / CSS / Tailwind only (stop the external servers)", target: nil, action: nil)
        webOnly.target = action { c in NativeWeb.setNativeOnly((c as? NSButton)?.state == .on) }
        webOnly.action = #selector(SettingsAction.fire(_:))
        webOnly.setAccessibilityLabel("Use native HTML CSS Tailwind only")
        onRefresh { webOnly.state = NativeWeb.nativeOnly ? .on : .off }
        row(nil, webOnly, help: "Does not start the HTML, CSS and Tailwind language servers (the Tailwind server alone is about 200 MB). Diagnostics and formatting from those servers are unavailable meanwhile.")

        section("Language servers")
        for server in LanguageServers.serverIds {
            let status = infoLabel { [weak self] in self?.statusText(for: server.id) ?? "" }
            status.font = .systemFont(ofSize: 11)
            let check = NSButton(checkboxWithTitle: server.name, target: nil, action: nil)
            check.target = action { c in
                LanguageServers.setEnabled(server.id, (c as? NSButton)?.state == .on)
            }
            check.action = #selector(SettingsAction.fire(_:))
            check.setAccessibilityLabel("Enable \(server.name) language server")
            onRefresh { check.state = LanguageServers.isEnabled(server.id) ? .on : .off }
            check.translatesAutoresizingMaskIntoConstraints = false
            check.widthAnchor.constraint(equalToConstant: 140).isActive = true
            status.preferredMaxLayoutWidth = 280
            let h = NSStackView(views: [check, status])
            h.orientation = .horizontal
            h.alignment = .firstBaseline
            h.spacing = 8
            row(nil, h)
        }
        let total = infoLabel { [weak self] in self?.totalText() ?? "" }
        row("Memory", total)
        row(nil, button("Restart Language Servers") {
            let roots = Set((NSApp.delegate as? AppDelegate)?.windows.compactMap(\.root) ?? [])
            roots.forEach { LanguageServers.restartAll(forRoot: $0) }
        }, help: "Disabling a server stops it for open projects the next time they restart.")

        section("Intelephense licence")
        let field = NSSecureTextField(string: "")
        field.placeholderString = "Paste licence key"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        field.setAccessibilityLabel("Intelephense licence key")
        licenceField = field
        let save = button("Save") { [weak self] in
            guard let self, let field = self.licenceField else { return }
            if IntelephenseLicence.save(field.stringValue) { field.stringValue = "" } else { NSSound.beep() }
            self.refresh()
        }
        let remove = button("Remove") { [weak self] in IntelephenseLicence.remove(); self?.refresh() }
        let h = NSStackView(views: [field, save, remove])
        h.orientation = .horizontal
        h.spacing = 8
        row("Licence key", h, help: "Stored in the macOS Keychain (service “CodeEditor.intelephense”) and never written to disk or logs. Takes effect after restarting language servers.")
        row("Status", infoLabel {
            if IntelephenseLicence.isInKeychain { return "Licence stored in Keychain" }
            return IntelephenseLicence.current() != nil ? "Using a licence from ~/intelephense/licence.txt or defaults (not in Keychain)" : "No licence (free features only)"
        })

        section("Formatters (current project)")
        let tools = infoLabel { [weak self] in self?.toolsText ?? "" }
        row("Detected", tools)
        detectTools { [weak self] text in self?.toolsText = text; self?.refresh() }
        restoreButton()
    }

    override func restoreDefaults() { SettingsDefaults.restoreLanguages() }

    private func statusText(for id: String) -> String {
        guard LanguageServers.isEnabled(id) else { return "Disabled" }
        let mine = LanguageServers.statuses().filter { $0.serverId == id }
        if mine.isEmpty { return "Not running" }
        return mine.map { "\($0.root.lastPathComponent): " + $0.text.replacingOccurrences(of: "\($0.name) · ", with: "").replacingOccurrences(of: $0.name, with: "running") }
            .joined(separator: "   ")
    }

    private func totalText() -> String {
        let all = LanguageServers.statuses()
        let sum = all.reduce(UInt64(0)) { $0 + $1.rssBytes }
        return all.isEmpty ? "No language servers running" : "\(all.count) running · \(SystemStats.megabytes(sum)) total"
    }

    private func detectTools(_ done: @escaping (String) -> Void) {
        guard let root = projectRoot() else { done("Open a project to detect formatters."); return }
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            func has(_ rel: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(rel).path) }
            let prettier = FormatTools.detect(for: root.appendingPathComponent("x.ts"))
            let blade = FormatTools.detect(for: root.appendingPathComponent("x.blade.php"))
            var lines = ["Pint: " + (has("vendor/bin/pint") ? "found" : "not found"),
                         "PHP-CS-Fixer: " + (has("vendor/bin/php-cs-fixer") ? "found" : "not found"),
                         "Prettier: " + (prettier.map { $0.global ? "found (global)" : "found (project)" } ?? "not found")]
            lines.append("Blade formatting: " + (blade == nil ? "needs Prettier with a Blade plugin" : "ready"))
            let text = root.lastPathComponent + "\n" + lines.joined(separator: "\n")
            DispatchQueue.main.async { done(text) }
        }
    }
}

// MARK: - Terminal

final class TerminalPane: SettingsPane {
    static let builtInAgents = ["Claude Code (claude)", "Gemini CLI (gemini)", "Codex (codex)", "OpenCode (opencode)", "Aider (aider)"]

    /// Parses `Title|command` lines; returns launchers plus the 1-based numbers of lines that are malformed.
    static func parseAgents(_ text: String) -> (valid: [(title: String, command: String)], invalid: [Int]) {
        var valid: [(String, String)] = [], invalid: [Int] = []
        for (i, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { valid.append((parts[0], parts[1])) } else { invalid.append(i + 1) }
        }
        return (valid, invalid)
    }

    private let agentsView = NSTextView()
    private var agentsStatus: NSTextField?

    override func build() {
        section("Terminal")
        popup("Dock", ["Right of editor", "Bottom panel"], help: "Where the terminal appears when opened with ⌥F12.",
              get: { Prefs.terminalDock == "bottom" ? 1 : 0 }, set: { Prefs.terminalDock = $0 == 1 ? "bottom" : "right" })
        let shell = textField(width: 320, placeholder: "Default: $SHELL", label: "Shell path", get: { Prefs.terminalShell }, set: { Prefs.terminalShell = $0.trimmingCharacters(in: .whitespaces) })
        row("Shell", shell)
        row(nil, infoLabel({
            let p = Prefs.terminalShell
            if p.isEmpty { return "Using your login shell" }
            return FileManager.default.isExecutableFile(atPath: (p as NSString).expandingTildeInPath) ? "Executable found" : "Not an executable file: the default shell is used instead"
        }, color: {
            let p = Prefs.terminalShell
            return p.isEmpty || FileManager.default.isExecutableFile(atPath: (p as NSString).expandingTildeInPath) ? .secondaryLabelColor : .systemOrange
        }))

        section("Font and cursor")
        row("Font family", fontFamilyPopup(label: "Terminal font family", get: { Prefs.terminalFontName }, set: { Prefs.terminalFontName = $0 }))
        number("Size", range: 8...30, step: 1, unit: "pt", slider: true, get: { Prefs.terminalFontSize }, set: { Prefs.terminalFontSize = $0 })
        popup("Cursor", ["Block", "Beam", "Underline"],
              get: { ["block", "beam", "underline"].firstIndex(of: Prefs.terminalCursorStyle) ?? 0 },
              set: { Prefs.terminalCursorStyle = ["block", "beam", "underline"][$0] })
        number("Scrollback", range: 500...100_000, step: 500, unit: "lines", get: { Double(Prefs.terminalScrollback) }, set: { Prefs.terminalScrollback = Int($0) })
        checkbox("Notify when a background terminal finishes", label: "Agents", help: "Badge and dock bounce when a background tab stops producing output.",
                 get: { Prefs.terminalNotifyOnIdle }, set: { Prefs.terminalNotifyOnIdle = $0 })
        checkbox("Alert when an agent finishes or needs input", label: "Alerts", help: "Tab dot, Dock badge / bounce and a macOS notification (not while you are looking at that tab). Uses Claude Code hooks (see docs/claude-code-alerts.md) with the terminal bell and title as fallback.",
                 get: { Prefs.terminalAgentAlerts }, set: { Prefs.terminalAgentAlerts = $0 })

        section("Claude Code")
        checkbox("IDE integration", label: "Enable", help: "Lets the claude CLI connect to this window (selection, diffs, diagnostics) over a localhost-only WebSocket with a random token. Applies to terminals started afterwards.",
                 get: { Prefs.claudeBridgeEnabled }, set: { Prefs.claudeBridgeEnabled = $0 })

        section("AI CLI launchers")
        row("Built in", infoLabel { Self.builtInAgents.joined(separator: "\n") })
        let legacy = textField(width: 320, placeholder: "e.g. claude --model opus", label: "Default agent command",
                               get: { UserDefaults.standard.string(forKey: "terminal.agentCommand") ?? "" },
                               set: { UserDefaults.standard.set($0.trimmingCharacters(in: .whitespaces), forKey: "terminal.agentCommand") })
        row("Default agent", legacy, help: "The “AI agent” entry in the terminal's Run menu.")

        agentsView.isRichText = false
        agentsView.isAutomaticQuoteSubstitutionEnabled = false
        agentsView.isAutomaticDashSubstitutionEnabled = false
        agentsView.isAutomaticTextReplacementEnabled = false
        agentsView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        agentsView.textContainerInset = NSSize(width: 4, height: 4)
        agentsView.isVerticallyResizable = true
        agentsView.autoresizingMask = [.width]
        agentsView.setAccessibilityLabel("Extra AI CLI launchers, one per line as Title|command")
        agentsView.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = agentsView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 420).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        row("Extra launchers", scroll, help: "One per line as Title|command, e.g. “Qwen|qwen”. They appear in the terminal's Run menu.")
        let status = infoLabel { [weak self] in self?.agentsSummary() ?? "" }
        agentsStatus = status
        row(nil, status)
        onRefresh { [weak self] in
            guard let self, self.agentsView.window?.firstResponder !== self.agentsView, self.agentsView.string != Prefs.terminalAgents else { return }
            self.agentsView.string = Prefs.terminalAgents
        }
        restoreButton()
    }

    private func agentsSummary() -> String {
        let p = Self.parseAgents(Prefs.terminalAgents)
        var s = "\(p.valid.count) extra launcher\(p.valid.count == 1 ? "" : "s")"
        if !p.invalid.isEmpty { s += " · ignoring line\(p.invalid.count == 1 ? "" : "s") " + p.invalid.map(String.init).joined(separator: ", ") + " (use Title|command)" }
        return s
    }

    override func restoreDefaults() { SettingsDefaults.restoreTerminal(); agentsView.string = "" }
}

extension TerminalPane: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        Prefs.terminalAgents = agentsView.string
    }
}
