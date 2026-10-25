import AppKit

/// Entry point of the completion feature: registers the built-in providers and attaches a controller to every tab.
enum CompletionSystem {
    /// Set by the integrator (ProjectWindow owns the index): current project symbols; used by the SymbolProvider when non-nil.
    static var symbolProvider: (() -> [SymbolIndex.Entry])?
    /// Identifier characters typed before the popup opens automatically.
    static var autoOpenMinChars = 2
    /// Delay between the last keystroke and the (auto) request, seconds.
    static var debounce: TimeInterval = 0.04

    private static var started = false
    private static var controllers: [ObjectIdentifier: CompletionController] = [:]

    static func controller(for tab: EditorTab) -> CompletionController? { controllers[ObjectIdentifier(tab)] }

    static func start() {
        guard !started else { return }
        started = true
        registerBuiltins()
        EditorEvents.onOpen { tab in
            guard !tab.isLargeFile else { return }
            controllers[ObjectIdentifier(tab)] = CompletionController(tab: tab)
        }
        EditorEvents.onClose { tab in
            controllers.removeValue(forKey: ObjectIdentifier(tab))?.detach()
        }
    }

    private static func registerBuiltins() {
        let web = ["html", "htm", "vue", "php", "phtml"]
        let jsExts = ["js", "jsx", "ts", "tsx", "mjs", "cjs", "vue", "html", "htm", "php", "phtml"]
        CompletionRegistry.register(BuiltinProvider(WordProvider.generate))
        CompletionRegistry.register(BuiltinProvider(triggers: ["$", ">", ":"], PHPCompletion.generate), forExtensions: ["php", "phtml"])
        CompletionRegistry.register(BuiltinProvider(triggers: ["."], JSCompletion.generate), forExtensions: jsExts)
        CompletionRegistry.register(BuiltinProvider(triggers: ["<", "/", " ", "="], HTMLCompletion.generate), forExtensions: web)
        CompletionRegistry.register(BuiltinProvider(triggers: ["@", "{"], BladeCompletion.generate), forExtensions: ["php"])
        CompletionRegistry.register(BuiltinProvider(triggers: ["@", ":"], CSSCompletion.generate), forExtensions: ["css", "scss", "less", "sass", "vue", "html", "htm", "php"])
        CompletionRegistry.register(BuiltinProvider(triggers: [":", "-"], TailwindCompletion.generate),
                                    forExtensions: ["html", "htm", "vue", "php", "phtml", "jsx", "tsx", "js", "ts", "css", "scss"])
        CompletionRegistry.register(BuiltinProvider(SnippetCompletion.generate),
                                    forExtensions: ["php", "phtml", "js", "jsx", "ts", "tsx", "mjs", "html", "htm", "vue"])
        CompletionRegistry.register(BuiltinProvider(LiveTemplateCompletion.generate), forExtensions: LiveTemplateCompletion.extensions)
        CompletionRegistry.register(SymbolCompletionProvider(), forExtensions: ["php", "phtml", "js", "jsx", "ts", "tsx", "mjs", "vue"])
        StructuredCompletion.register()   // YAML / JSON key + value completion (StructuredCompletion.swift)
        NativeEngines.registerCompletions()   // native engines (Web, JS, Vue, Python, then PHP's FastTier last: it wins score ties when deduping)
    }
}
