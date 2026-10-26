import AppKit

// Thin adapters from the native engines to `NativeEngine`. They only forward: no engine internals live here, and the Settings
// rows, help texts and preference keys are exactly the ones the engines always had.

private func off(_ key: String) { UserDefaults.standard.removeObject(forKey: key) }

private func mapRename(_ r: NativePHPUI.RenameStart) -> NativeRenameOutcome {
    switch r { case .handled: return .handled; case .notNative: return .notNative; case .refused(let why): return .refused(why) }
}

private func mapRename(_ r: NativeJSUI.RenameStart) -> NativeRenameOutcome {
    switch r { case .handled: return .handled; case .notNative: return .notNative; case .refused(let why): return .refused(why) }
}

// MARK: PHP

struct PHPEngine: NativeEngine {
    let id = "php"
    let displayName = "PHP"
    let priority = 30
    let completionRank = 100          // FastTier registers last: it wins score ties when deduping against the other providers
    let emptyHoverIsAnswer = true
    let supportsSignatureHelp = true

    func handles(_ url: URL) -> Bool { NativePHP.handles(url) }
    func lookup(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) { NativePHP.lookupAsync(url: url, text: text, offset: offset, completion: completion) }
    func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool { NativePHP.goToDefinition(in: tab, at: offset) }
    func findUsages(_ w: ProjectWindow, tab: EditorTab) -> Bool { NativePHPUI.findUsages(w) }
    func rename(_ w: ProjectWindow) -> NativeRenameOutcome { mapRename(NativePHPUI.rename(w)) }
    func signatureHelp(url: URL, text: NSString, caret: Int, completion: @escaping (NativeSigOutcome) -> Void) {
        NativePHP.signatureHelpAsync(url: url, text: text, caret: caret) { outcome in
            switch outcome {
            case .help(let help): completion(.help(help.lspPayload))
            case .notInCall: completion(.notInCall)
            case .unknown: completion(.unknown)
            }
        }
    }
    func hoverDiagnostics(for tab: EditorTab?) -> [LSPDiagnostic] { NativePHPDiagController.hoverDiagnostics(for: tab) }
    func registerCompletion() { FastTier.register() }
    func startDiagnostics() { NativePHPDiagController.start() }
    // invalidate: FastTier.invalidate (the caller of the fan-out) already drops the PHP project's sections.
    func trimMemory() { NativePHP.trimMemory() }
    func installMemoryHooks() { NativePHP.installMemoryHooks() }
    func resetPrefs() { off(NativePHP.nativeOnlyKey); NativePHPDiag.resetPrefs() }
    func suppressesServer(_ id: String, root: URL?) -> Bool { id == "intelephense" && NativePHP.nativeOnly }   // Settings > Languages > native PHP engine only

    var settingsSections: [NativeSettingsSection] {
        let groups = NPDiagGroup.allCases.map { g in
            NativeSettingsItem.toggle(NativeSettingsToggle(
                title: g.title, accessibility: "PHP diagnostics: \(g.title)",
                help: g == .syntax ? "Native checks run after edits settle, for the open file only. Rules stay silent when they cannot be certain; with Intelephense running the same problem is never listed twice." : nil,
                get: { g.enabled },
                set: { on in g.enabled = on; NotificationCenter.default.post(name: NativePHPDiagController.settingsDidChange, object: nil) }))
        }
        let severity = NativeSettingsItem.choice(NativeSettingsChoice(
            label: "Undefined class severity", accessibility: "Severity of undefined classes", options: ["Warning", "Error"],
            get: { NativePHPDiag.classSeverity == 1 ? 1 : 0 },
            set: { i in NativePHPDiag.classSeverity = i == 1 ? 1 : 2; NotificationCenter.default.post(name: NativePHPDiagController.settingsDidChange, object: nil) }))
        return [
            NativeSettingsSection(title: "PHP", items: [.toggle(NativeSettingsToggle(
                title: "Use native PHP engine only (stop Intelephense)", accessibility: "Use native PHP engine only",
                help: "Definition, hover, find usages, rename, signature help and diagnostics come from Kode's built-in PHP engine (about 0 MB extra). Intelephense (160-1100 MB) is not started; turn this off to run it alongside. See docs/native-php.md.",
                get: { NativePHP.nativeOnly }, set: { NativePHP.setNativeOnly($0) }))]),
            NativeSettingsSection(title: "PHP diagnostics", items: groups + [severity]),
        ]
    }
}

// MARK: Python

struct PythonEngine: NativeEngine {
    let id = "python"
    let displayName = "Python"
    let priority = 30
    let emptyHoverIsAnswer = true
    let providesSessionUI = true       // native Python needs the session UI (hover, Cmd-click) although it has no server

    func handles(_ url: URL) -> Bool { NativePy.handles(url) }
    func lookup(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) { NativePy.lookupAsync(url: url, text: text, offset: offset, completion: completion) }
    func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool { NativePy.goToDefinition(in: tab, at: offset) }
    func findUsages(_ w: ProjectWindow, tab: EditorTab) -> Bool { NativePyUI.findUsages(tab: tab) }
    func hoverDiagnostics(for tab: EditorTab?) -> [LSPDiagnostic] { NativePyDiagController.hoverDiagnostics(for: tab) }
    func registerCompletion() { NativePy.registerCompletion() }
    func startDiagnostics() { NativePyDiagController.start() }
    func trimMemory() { NativePy.trimMemory() }
    // installMemoryHooks: Python installs its hooks lazily on first use (NativePy.prepare), as before.
    func resetPrefs() { off(NativePy.enabledKey); PyDiagGroup.resetPrefs() }

    var settingsSections: [NativeSettingsSection] {
        let groups = PyDiagGroup.allCases.map { g in
            NativeSettingsItem.toggle(NativeSettingsToggle(
                title: "Python: " + g.title, accessibility: "Python diagnostics: \(g.title)",
                help: g == .syntax ? "Checks run after edits settle, for the open file only, and stay silent when they cannot be certain (unresolved imports need a discovered virtualenv)." : nil,
                get: { g.enabled },
                set: { on in g.enabled = on; NotificationCenter.default.post(name: NativePyDiagController.settingsDidChange, object: nil) }))
        }
        return [NativeSettingsSection(title: "Python", items: [.toggle(NativeSettingsToggle(
            title: "Use native Python engine", accessibility: "Use native Python engine",
            help: "Go to definition, hover with docstrings, find usages, completion and diagnostics for .py files from Kode's built-in Python index (no pyright / pylsp process, a few MB while idle). Imports resolve through the project, its virtualenv (.venv, venv, poetry, pipenv, pyenv, conda) and the standard library.",
            get: { NativePy.enabled },
            set: { on in NativePy.enabled = on; NotificationCenter.default.post(name: NativePyDiagController.settingsDidChange, object: nil) }))] + groups)]
    }
}

// MARK: HTML / CSS / Tailwind

struct WebEngine: NativeEngine {
    let id = "web"
    let displayName = "HTML / CSS / Tailwind"
    let priority = 40

    func handles(_ url: URL) -> Bool { NativeWeb.handles(url) }
    func lookup(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) { NativeWeb.lookupAsync(url: url, text: text, offset: offset, completion: completion) }
    func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool { NativeWeb.goToDefinition(in: tab, at: offset) }
    func registerCompletion() { NativeWeb.register() }
    func startDiagnostics() { NativeWebDiagController.start() }
    func invalidate(root: URL) { NativeWeb.invalidate(root: root) }
    func invalidate(root: URL, paths: [String]) { NativeWeb.invalidate(root: root, paths: paths) }
    func trimMemory() { NativeWeb.trimMemory() }
    func installMemoryHooks() { NativeWeb.installMemoryHooks() }
    func resetPrefs() {
        for k in [NativeWeb.enabledKey, NativeWeb.nativeOnlyKey, NativeWeb.tailwindEnabledKey, NativeWeb.tailwindNativeOnlyKey] { off(k) }
    }
    func suppressesServer(_ id: String, root: URL?) -> Bool {
        if NativeWeb.managedServerIds.contains(id), NativeWeb.enabled, NativeWeb.nativeOnly { return true }      // native HTML / CSS only
        return id == NativeWeb.tailwindServerId && NativeWeb.enabled && NativeWeb.tailwindEnabled && NativeWeb.tailwindNativeOnly   // native Tailwind only
    }
    func suppressesBuiltinCompletion(_ topic: NativeBuiltinCompletionTopic, for url: URL) -> Bool {
        switch topic {
        case .html, .css: return NativeWeb.handles(url)               // NativeHTMLService / NativeCSSService answer these files
        case .tailwind: return NativeWeb.tailwindActive(for: url)      // the project's real theme answers (NativeTailwind*.swift)
        }
    }

    var settingsSections: [NativeSettingsSection] {
        func toggle(_ title: String, _ acc: String, _ help: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> NativeSettingsItem {
            .toggle(NativeSettingsToggle(title: title, accessibility: acc, help: help, get: get, set: set))
        }
        return [
            NativeSettingsSection(title: "HTML / CSS", items: [
                toggle("Native HTML and CSS services", "Native HTML and CSS services",
                       "Completion, hover and go to definition for HTML and CSS come from Kode itself (no node process).",
                       { NativeWeb.enabled }, { NativeWeb.enabled = $0 }),
                toggle("Use native HTML / CSS only (stop the external servers)", "Use native HTML CSS only",
                       "Does not start the HTML and CSS language servers (about 100-165 MB). Diagnostics and formatting from those servers are unavailable meanwhile.",
                       { NativeWeb.nativeOnly }, { NativeWeb.setNativeOnly($0) }),
            ]),
            NativeSettingsSection(title: "Tailwind CSS", items: [
                toggle("Native Tailwind engine", "Native Tailwind engine",
                       "Class completion and hover from the project's tailwind.config.* or @theme (no node process). It only loads in projects that use Tailwind; switched off, nothing Tailwind-related runs.",
                       { NativeWeb.tailwindEnabled }, { NativeWeb.setTailwindEnabled($0) }),
                toggle("Use native Tailwind only (stop the Tailwind server)", "Use native Tailwind only",
                       "Does not start the Tailwind language server (about 345 MB). Configs that need JavaScript (presets, plugins) get no answer meanwhile.",
                       { NativeWeb.tailwindNativeOnly }, { NativeWeb.setTailwindNativeOnly($0) }),
            ]),
        ]
    }
}

// MARK: JavaScript / TypeScript

struct JSEngine: NativeEngine {
    let id = "js"
    let displayName = "JavaScript / TypeScript"
    let priority = 20
    let supportsSignatureHelp = true

    func handles(_ url: URL) -> Bool { NativeJS.handles(url) }
    func lookup(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) { NativeJS.lookupAsync(url: url, text: text, offset: offset, completion: completion) }
    func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool { NativeJS.goToDefinition(in: tab, at: offset) }
    func findUsages(_ w: ProjectWindow, tab: EditorTab) -> Bool { NativeJSUI.findUsages(w) }
    func rename(_ w: ProjectWindow) -> NativeRenameOutcome { mapRename(NativeJSUI.rename(w)) }
    func signatureHelp(url: URL, text: NSString, caret: Int, completion: @escaping (NativeSigOutcome) -> Void) {
        NativeJS.signatureHelpAsync(url: url, text: text, caret: caret) { outcome in
            switch outcome {
            case .help(let payload): completion(.help(payload))
            case .notInCall: completion(.notInCall)
            case .unknown: completion(.unknown)
            }
        }
    }
    func allowsLinkHighlight(for url: URL) -> Bool { NativeJS.allowsLinkHighlight(url) }
    func hoverDiagnostics(for tab: EditorTab?) -> [LSPDiagnostic] { NativeJSDiagController.hoverDiagnostics(for: tab) }
    func registerCompletion() { NativeJSCompletion.register() }
    func startDiagnostics() { NativeJSDiagController.start() }
    func invalidate(root: URL) { NJSRefs.dropFileList() }       // native JS find usages: the project's file listing is stale
    func trimMemory() { NativeJS.trimMemory() }
    func installMemoryHooks() { NativeJS.installMemoryHooks() }
    func resetPrefs() {
        for k in [NativeJS.enabledKey, NativeJS.nativeOnlyKey, NativeJSDiag.syntaxKey, NativeJSAutoImport.key, NativeJSDiag.enabledKey] { off(k) }
    }
    /// Opt-in: native JS / TS only (Settings > Languages). Root-specific (Vue projects keep the server), so only asked with a root.
    func suppressesServer(_ id: String, root: URL?) -> Bool {
        guard id == "typescript", let root else { return false }
        return NativeJS.suppressesTypeScriptServer(root: root)
    }

    var settingsSections: [NativeSettingsSection] {
        func reschedule() { for ctl in NativeJSDiagController.controllers.values { ctl.schedule(initial: true) } }
        func toggle(_ title: String, _ acc: String, _ help: String?, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> NativeSettingsItem {
            .toggle(NativeSettingsToggle(title: title, accessibility: acc, help: help, get: get, set: set))
        }
        return [NativeSettingsSection(title: "JavaScript / TypeScript", items: [
            toggle("Native JavaScript / TypeScript engine", "Native JavaScript and TypeScript engine",
                   "Go to definition, hover, find usages, import and member completion come from Kode's built-in parser first (tsconfig paths, node_modules, re-exports, classes); the TypeScript server answers whatever native cannot be certain about. Turn off to leave everything to the server.",
                   { NativeJS.enabled }, { NativeJS.enabled = $0; NativeJS.trimMemory() }),
            toggle("Do not start the TypeScript server (native JS / TS only)", "Do not start the TypeScript server",
                   "Saves the server's 230 MB - 1 GB. You keep go to definition, hover, find usages, import and member completion and missing / unused import checks; you lose rename, type errors, completion and hover for inferred types, signature help and quick fixes. Vue projects always keep the server. Applies to projects opened afterwards.",
                   { NativeJS.nativeOnly }, { NativeJS.nativeOnly = $0 }),
            toggle("Native JS / TS diagnostics (missing relative imports, unused imports)", "Native JavaScript and TypeScript diagnostics", nil,
                   { NativeJSDiag.enabled }, { NativeJSDiag.enabled = $0; reschedule() }),
            toggle("Report unclosed brackets (syntax)", "Native syntax diagnostics for unclosed brackets",
                   "Only the repairs tree-sitter is sure about (a missing ) ] or }); other parse errors are never reported because the grammar lacks some newer syntax.",
                   { NativeJSDiag.syntaxEnabled }, { NativeJSDiag.syntaxEnabled = $0; reschedule() }),
            toggle("Report unknown names and wrong argument counts (TypeScript)", "Native type diagnostics for unknown names and argument counts",
                   "Off by default. Cannot find name (TS2304) and wrong argument count (TS2554) for single functions, only in TypeScript files the tsconfig includes, and silent in projects with global declaration files.",
                   { NativeJSDiag.typesEnabled }, { NativeJSDiag.typesEnabled = $0; reschedule() }),
            toggle("Auto-import suggestions while typing", "Auto-import suggestions",
                   "Exported names of other project files and dependencies appear in the completion list and add the import when accepted.",
                   { NativeJSAutoImport.enabled }, { NativeJSAutoImport.enabled = $0 }),
        ])]
    }
}

// MARK: Vue

struct VueEngine: NativeEngine {
    let id = "vue"
    let displayName = "Vue"
    let priority = 10
    let underlinesHitRange = true

    func handles(_ url: URL) -> Bool { NativeVue.handles(url) }
    func lookup(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) { NativeVue.lookupAsync(url: url, text: text, offset: offset, completion: completion) }
    func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool { NativeVue.goToDefinition(in: tab, at: offset) }
    func findUsages(_ w: ProjectWindow, tab: EditorTab) -> Bool { NativeVueUI.findUsages(w) }
    func registerCompletion() { NativeVue.register() }
    func invalidate(root: URL) { NativeVue.invalidate(root: root) }
    func invalidate(root: URL, paths: [String]) { NativeVue.invalidate(root: root, paths: paths) }
    func trimMemory() { NativeVue.trimMemory() }
    func installMemoryHooks() { NativeVue.installMemoryHooks() }
    func resetPrefs() { off(NativeVue.enabledKey); off(NativeVue.nativeOnlyKey) }
    func suppressesServer(_ id: String, root: URL?) -> Bool { id == "volar" && NativeVue.enabled && NativeVue.nativeOnly }

    /// Continues the JavaScript / TypeScript section (no heading of its own), as the row always did.
    var settingsSections: [NativeSettingsSection] {
        [NativeSettingsSection(title: nil, items: [.toggle(NativeSettingsToggle(
            title: "Native Vue template service", accessibility: "Native Vue template service",
            help: "In .vue templates: go to definition, hover, find usages and completion for custom component tags, their props / events / slots, template variables, assets and router links come from Kode itself (imports, components option, global and auto-imported components, aliases). The Vue language server only answers what native cannot be certain about.",
            get: { NativeVue.enabled }, set: { NativeVue.enabled = $0; NativeVue.trimMemory() })),
            .toggle(NativeSettingsToggle(
            title: "Do not start Volar / the TypeScript server for Vue projects", accessibility: "Do not start Volar for Vue projects",
            help: "Saves the Volar + TypeScript server pair (about 750 MB - 1 GB). You keep native template navigation, hover, find usages and completion; you lose template type checking, type errors, rename and inferred-type hover. Takes effect for projects opened afterwards.",
            get: { NativeVue.nativeOnly }, set: { NativeVue.nativeOnly = $0 }))])]
    }
}
