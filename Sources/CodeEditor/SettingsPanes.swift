import AppKit

extension SettingsPane {
    /// Popup of installed monospaced families: bundled "JetBrains Mono" first (stored as ""), then "System Monospaced",
    /// then the rest. The list loads off the main thread.
    func fontFamilyPopup(label: String, get: @escaping () -> String, set: @escaping (String) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.translatesAutoresizingMaskIntoConstraints = false
        p.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        p.setAccessibilityLabel(label)
        var families: [String] = []
        func title(for stored: String) -> String {
            stored.isEmpty ? FontRegistry.bundledFamily : stored
        }
        func rebuild() {
            p.removeAllItems()
            p.addItem(withTitle: FontRegistry.bundledFamily)
            p.addItem(withTitle: FontCatalog.systemMonospaced)
            p.addItems(withTitles: families.filter { $0 != FontRegistry.bundledFamily })
            let cur = get()
            if !cur.isEmpty, p.item(withTitle: cur) == nil { p.addItem(withTitle: cur) }
            p.selectItem(withTitle: title(for: cur))
        }
        rebuild()
        FontCatalog.monospacedFamilies { list in families = list; rebuild() }
        p.target = action { c in
            guard let p = c as? NSPopUpButton else { return }
            set(p.indexOfSelectedItem == 0 ? "" : (p.titleOfSelectedItem ?? ""))
        }
        p.action = #selector(SettingsAction.fire(_:))
        onRefresh { p.selectItem(withTitle: title(for: get())) }
        return p
    }
}

/// Sample PHP rendered with the real highlighter, so scheme changes are visible without opening a file.
final class SchemePreview: NSView {
    private let textView = NSTextView(frame: .zero)
    private var highlighter: Highlighter?
    static let sample = """
    <?php
    /** @param int|null $id  The user id */
    #[Route('/users')]
    final class Demo extends Base
    {
        public const MAX = 10;
        public function show(User $user, ?int $id = null): string
        {
            $name = $user?->name ?? 'guest'; // fallback
            return Str::title("Hi {$name}") . self::MAX;
        }
    }
    """

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 2000, height: 10_000)
        textView.setAccessibilityLabel("Colour scheme preview")
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor), textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor), textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        textView.string = Self.sample
        highlighter = Highlighter(textView: textView, extension: "php")
        restyle()
        NotificationCenter.default.addObserver(self, selector: #selector(restyle), name: Theme.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func restyle() {
        let font = NSFont(descriptor: Theme.font.fontDescriptor, size: 12) ?? Theme.font
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = CGFloat(Prefs.lineHeightMultiple)
        let attrs = Theme.textAttributes(paragraph: para).merging([.font: font]) { _, new in new }
        textView.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (textView.string as NSString).length))
        textView.backgroundColor = Theme.background
        layer?.borderColor = Theme.palette.divider.cgColor
        layer?.backgroundColor = Theme.background.cgColor
        highlighter?.apply()
    }
}

// MARK: - General

final class GeneralPane: SettingsPane {
    override func build() {
        section("Appearance")
        popup("Theme", ["System", "Light", "Dark"], help: "System follows macOS; Light and Dark override it for the whole app.",
              get: { [ThemeMode.system, .light, .dark].firstIndex(of: Theme.mode) ?? 0 },
              set: { Theme.setMode([ThemeMode.system, .light, .dark][$0]) })

        section("Saving")
        checkbox("Save files when the app loses focus", label: "Auto-save",
                 get: { AutoSave.focusLossEnabled }, set: { AutoSave.focusLossEnabled = $0 })
        checkbox("Save when switching editor tabs", get: { AutoSave.tabSwitchEnabled }, set: { AutoSave.tabSwitchEnabled = $0 })
        number("Save after idle", range: 0...600, step: 1, unit: "seconds (0 = off)", help: "Saves a modified file this long after the last keystroke.",
               get: { AutoSave.idleSeconds }, set: { AutoSave.idleSeconds = $0 })
        checkbox("Format files on save", label: "Formatting", help: "Uses Pint, PHP-CS-Fixer, Prettier or the language server, whichever the project provides.",
                 get: { Formatter.formatOnSave }, set: { Formatter.formatOnSave = $0 })

        section("Energy")
        popup("Power saver", ["Automatic", "Always", "Off"],
              help: "Automatic: on in Low Power Mode, when the Mac runs hot, or on battery at 20% or less. Power saver lengthens debounces, pauses inline blame and live git diff, and shuts idle language servers down sooner.",
              get: { ["auto", "always", "off"].firstIndex(of: Prefs.powerSaver) ?? 0 },
              set: { Prefs.powerSaver = ["auto", "always", "off"][$0] })
        popup("GPU assist", ["Automatic", "On", "Off"],
              help: "Draws the editor text asynchronously. Automatic: only for files over about 2,000 lines, never in power saver or while the window is hidden, and it switches itself off if it measures slower than normal drawing.",
              get: { ["auto", "on", "off"].firstIndex(of: Prefs.gpuAssist) ?? 0 },
              set: { Prefs.gpuAssist = ["auto", "on", "off"][$0] })

        section("Projects")
        checkbox("Restore windows on launch", label: "Startup", get: { SessionStore.reopenOnLaunch }, set: { SessionStore.reopenOnLaunch = $0 })
        checkbox("Include vendor in Go to File", label: "Search",
                 help: "Lists files inside vendor/ in Go to File (slower indexing on large projects).",
                 get: { ProjectIndex.includeVendor },
                 set: { on in
                     ProjectIndex.includeVendor = on
                     (NSApp.delegate as? AppDelegate)?.windows.forEach { $0.reindex() }
                 })
        checkbox("Index vendor classes for Go to Class and Go to Symbol", get: { VendorIndex.enabled }, set: { VendorIndex.enabled = $0 })

        section("Reset")
        row(nil, button("Reset All Settings…") { [weak self] in
            guard let self, self.confirm("Reset all settings?", detail: "Every preference returns to its default value. Open files and projects are not affected.",
                                         button: "Reset") else { return }
            SettingsDefaults.resetAll()
            self.refresh()
        })
        restoreButton()
    }

    override func restoreDefaults() { SettingsDefaults.restoreGeneral() }
}

// MARK: - Editor

final class EditorSettingsPane: SettingsPane {
    private let preview = NSTextField(labelWithString: "")

    override func build() {
        section("Color scheme")
        popup("Light", Theme.lightSchemes.map(\.title), help: "Used when the app appearance is Light (General > Theme).",
              get: { Theme.lightSchemes.firstIndex { $0.id == Prefs.lightScheme } ?? 0 },
              set: { Prefs.lightScheme = Theme.lightSchemes[$0].id })
        popup("Dark", Theme.darkSchemes.map(\.title), help: "Used when the app appearance is Dark.",
              get: { Theme.darkSchemes.firstIndex { $0.id == Prefs.darkScheme } ?? 0 },
              set: { Prefs.darkScheme = Theme.darkSchemes[$0].id })
        let swatch = SchemePreview(frame: .zero)
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.widthAnchor.constraint(equalToConstant: rowWidth - SettingsPane.labelWidth - 10).isActive = true
        swatch.heightAnchor.constraint(equalToConstant: 236).isActive = true
        row("Preview", swatch)

        section("Font")
        row("Font family", fontFamilyPopup(label: "Editor font family", get: { Prefs.editorFontName }, set: { Prefs.editorFontName = $0 }))
        number("Size", range: 8...36, step: 1, unit: "pt", slider: true, get: { Prefs.editorFontSize }, set: { Prefs.editorFontSize = $0 })
        number("Line height", range: 0.9...2.0, step: 0.05, decimals: 2, unit: "×", slider: true,
               get: { Prefs.lineHeightMultiple }, set: { Prefs.lineHeightMultiple = $0 })

        preview.stringValue = "function render(array $rows): ?string { return $rows[0] ?? null; }   0O 1lI"
        preview.isBordered = false
        preview.drawsBackground = true
        preview.lineBreakMode = .byTruncatingTail
        preview.maximumNumberOfLines = 1
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.borderWidth = 1
        preview.setAccessibilityLabel("Font preview")
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.widthAnchor.constraint(equalToConstant: rowWidth - SettingsPane.labelWidth - 10).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 30).isActive = true
        onRefresh { [weak self] in
            guard let self else { return }
            self.preview.font = Theme.font
            self.preview.backgroundColor = Theme.background
            self.preview.textColor = Theme.foreground
            self.preview.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        row("Preview", preview)

        section("Indentation")
        popup("Default indent", ["Spaces", "Tabs"], help: "Used when neither .editorconfig nor the file's own content decides.",
              get: { Prefs.defaultIndentUsesTabs ? 1 : 0 }, set: { Prefs.defaultIndentUsesTabs = $0 == 1 })
        number("Indent size", range: 1...8, step: 1, unit: "columns", get: { Double(Prefs.defaultIndentSize) }, set: { Prefs.defaultIndentSize = Int($0) })

        section("Display")
        checkbox("Line numbers", label: "Show", get: { Prefs.showLineNumbers }, set: { Prefs.showLineNumbers = $0 })
        checkbox("Indent guides", get: { Prefs.showIndentGuides }, set: { Prefs.showIndentGuides = $0 })
        checkbox("Highlight current line", get: { Prefs.highlightCurrentLine }, set: { Prefs.highlightCurrentLine = $0 })
        checkbox("Breadcrumbs", get: { Prefs.showBreadcrumbs }, set: { Prefs.showBreadcrumbs = $0 })
        checkbox("Rainbow brackets", get: { BracketColorizer.enabled }, set: { setRainbowBrackets($0) })
        checkbox("Inline Git blame", get: { Prefs.inlineBlame }, set: { Prefs.inlineBlame = $0 })
        checkbox("Soft-wrap long lines", label: "Wrapping", get: { Prefs.softWrap }, set: { setSoftWrap($0) })

        section("Folding")
        checkbox("Code folding", label: "Enable", get: { Prefs.foldingEnabled }, set: { Prefs.foldingEnabled = $0 })
        checkbox("Fold imports and license headers when a file opens", get: { Prefs.foldImportsOnOpen }, set: { Prefs.foldImportsOnOpen = $0 })

        section("Code completion")
        popup("Open after", ["1 character", "2 characters", "3 characters", "4 characters"],
              help: "Automatic popup only; Ctrl-Space always opens it.",
              get: { Prefs.completionMinChars - 1 }, set: { Prefs.completionMinChars = $0 + 1 })
        number("Delay", range: 0...1000, step: 10, unit: "ms", get: { Double(Prefs.completionDelayMs) }, set: { Prefs.completionDelayMs = Int($0) })
        restoreButton()
    }

    override func restoreDefaults() { SettingsDefaults.restoreEditor() }
}
