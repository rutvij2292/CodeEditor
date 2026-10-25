import Foundation

/// How to start one server process for one project root (resolved lazily, per launch).
struct LSPLaunch {
    var executable: String
    var args: [String]
    var env: [String: String] = [:]
    /// Replaces `LanguageServerConfig.initializationOptions` when set.
    var initializationOptions: [String: Any]?
    /// The server publishes diagnostics only on request (LSP 3.17 `textDocument/diagnostic`), e.g. the native TypeScript server.
    var pullDiagnostics = false
    /// "native" / "tsserver" for the TypeScript entry, shown in logs and used to decide restarts.
    var variant = ""
}

/// Per-server user preferences (UserDefaults `lsp.<id>.enabled`, default true).
enum LanguageServerPrefs {
    static func key(_ id: String) -> String { "lsp.\(id).enabled" }
    static func isEnabled(_ id: String) -> Bool {
        if id == "intelephense", NativePHP.nativeOnly { return false }      // Settings > Languages > native PHP engine only
        if NativeWeb.managedServerIds.contains(id), NativeWeb.enabled, NativeWeb.nativeOnly { return false }   // native HTML / CSS only
        if id == NativeWeb.tailwindServerId, NativeWeb.enabled, NativeWeb.tailwindEnabled, NativeWeb.tailwindNativeOnly { return false }   // native Tailwind only
        return UserDefaults.standard.object(forKey: key(id)) as? Bool ?? true
    }
    static func setEnabled(_ id: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: key(id)) }
    /// Files larger than this are never sent to a language server.
    static let maxFileBytes = 2 * 1024 * 1024
    /// Optional private npm prefix (`npm install --prefix <this> typescript@5 @vue/typescript-plugin`).
    static var privateServersDir: String { NSHomeDirectory() + "/Library/Application Support/CodeEditor/servers" }
}

/// Discovery of the TypeScript / Vue / Tailwind pieces that vary by machine and project.
///
/// TypeScript server choice (first match wins):
///  1. native TypeScript 7 (`tsc --lsp --stdio`, a Go binary, ~65 MB instead of ~550 MB for tsserver): project
///     `node_modules/@typescript/typescript-<os>-<arch>/lib/tsc`, then the global TypeScript 7 platform package, then the
///     private servers dir. Not used for Vue projects (it cannot load `@vue/typescript-plugin`) nor when
///     `CE_TS_MODE=tsserver` / `lsp.typescript.preferTsserver` is set.
///  2. `typescript-language-server --stdio` with `tsserver.path` = the project's `node_modules/typescript/lib/tsserver.js`,
///     else a global TypeScript 5/6 lib, else VS Code's bundled TypeScript, else the private install.
enum LanguageServerLaunch {
    static let fm = FileManager.default

    static var platformPackage: String {
        #if arch(arm64)
        return "typescript-darwin-arm64"
        #else
        return "typescript-darwin-x64"
        #endif
    }

    /// `~/.nvm/versions/node/*/lib/node_modules` (newest first) plus the usual global prefixes and the private dir.
    static func globalModuleDirs() -> [String] {
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        var dirs = ((try? fm.contentsOfDirectory(atPath: nvm)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "\(nvm)/\($0)/lib/node_modules" }
        dirs += ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules", NSHomeDirectory() + "/.volta/tools/image/packages",
                 LanguageServerPrefs.privateServersDir + "/node_modules"]
        return dirs
    }

    /// `node_modules` directories from `root` up to (excluding) the home directory / filesystem root.
    static func ancestorModuleDirs(from root: URL) -> [String] {
        var out: [String] = []
        var dir = root.standardizedFileURL
        let home = NSHomeDirectory()
        while dir.path != "/" && dir.path != home {
            out.append(dir.appendingPathComponent("node_modules").path)
            dir = dir.deletingLastPathComponent()
        }
        return out
    }

    static func isFile(_ p: String) -> Bool { fm.fileExists(atPath: p) }

    // MARK: TypeScript

    static func vsCodeTypeScriptLib() -> String {
        "/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/node_modules/typescript/lib"
    }

    /// A TypeScript `lib` directory with a working `tsserver.js` and `typescript.js` (TypeScript 7 has neither).
    static func tsserverLib(root: URL) -> String? {
        var candidates = ancestorModuleDirs(from: root).map { $0 + "/typescript/lib" }
        candidates += globalModuleDirs().map { $0 + "/typescript/lib" }
        candidates.append(vsCodeTypeScriptLib())
        return candidates.first { isFile($0 + "/tsserver.js") && isFile($0 + "/typescript.js") }
    }

    static func nativeTypeScript(root: URL) -> String? {
        var bases: [String] = []
        for nm in ancestorModuleDirs(from: root) { bases += ["\(nm)/@typescript", "\(nm)/typescript/node_modules/@typescript"] }
        for nm in globalModuleDirs() { bases += ["\(nm)/typescript/node_modules/@typescript", "\(nm)/@typescript"] }
        for b in bases {
            let tsc = "\(b)/\(platformPackage)/lib/tsc"
            if fm.isExecutableFile(atPath: tsc) { return tsc }
            let tsgo = "\(b)/native-preview-darwin-\(platformPackage.hasSuffix("arm64") ? "arm64" : "x64")/lib/tsgo"
            if fm.isExecutableFile(atPath: tsgo) { return tsgo }
        }
        return nil
    }

    static func readPackageJSON(_ dir: URL) -> String {
        (try? String(contentsOf: dir.appendingPathComponent("package.json"), encoding: .utf8)) ?? ""
    }

    /// True when the project depends on Vue (then the TypeScript server must be a real tsserver with the Vue plugin).
    static func isVueProject(_ root: URL) -> Bool {
        let p = readPackageJSON(root)
        return p.contains("\"vue\"") || p.contains("\"@vue/") || p.contains("\"nuxt\"")
    }

    /// Directory handed to tsserver as the plugin probe location (contains node_modules/@vue/typescript-plugin).
    static func vuePluginLocation(root: URL) -> String? {
        var locations: [String] = []
        for nm in ancestorModuleDirs(from: root) + globalModuleDirs() {
            locations.append(nm + "/@vue/language-server")                 // plugin nested in the language server package
            locations.append((nm as NSString).deletingLastPathComponent)   // plugin installed next to it
        }
        return locations.first { isFile($0 + "/node_modules/@vue/typescript-plugin/package.json") }
            .map { ($0 as NSString).standardizingPath }
    }

    static var typescriptPreferences: [String: Any] {
        ["includeCompletionsForModuleExports": true, "includeCompletionsWithInsertText": true,
         "includeAutomaticOptionalChainCompletions": true, "quotePreference": "auto",
         "importModuleSpecifierPreference": "relative", "allowIncompleteCompletions": true]
    }

    static func typescript(root: URL, manager: LanguageServerManager) -> LSPLaunch? {
        if NativeJS.suppressesTypeScriptServer(root: root), !manager.vueRoots.contains(root.path) { return nil }      // opt-in: native JS / TS only (Settings > Languages)
        let env = AppEnv.value("CE_TS_MODE")
        let forceNode = env == "tsserver" || UserDefaults.standard.bool(forKey: "lsp.typescript.preferTsserver")
            || manager.vueRoots.contains(root.path) || isVueProject(root)
        if !forceNode, env != "tsserver", let native = nativeTypeScript(root: root) {
            return LSPLaunch(executable: native, args: ["--lsp", "--stdio"], pullDiagnostics: true, variant: "native")
        }
        guard let exe = manager.resolveExecutable(["typescript-language-server"]) else { return nil }
        // RAM: by default typescript-language-server runs a second "syntax" tsserver (+~110 MB) and a typings-installer
        // process (+~50 MB, runs npm). Measured on a Vue project: 630 MB -> 330 MB without them. maxTsServerMemory is a
        // runaway safety net only (the live program graph is ~270 MB; lower caps barely help and risk out-of-memory restarts).
        var opts: [String: Any] = ["preferences": typescriptPreferences, "hostInfo": "CodeEditor",
                                   "disableAutomaticTypingAcquisition": true]
        var tsserverOpts: [String: Any] = ["useSyntaxServer": "never", "maxTsServerMemory": 1024]
        if let lib = tsserverLib(root: root) { tsserverOpts["path"] = lib + "/tsserver.js" }
        opts["tsserver"] = tsserverOpts
        if forceNode, let loc = vuePluginLocation(root: root) {
            opts["plugins"] = [["name": "@vue/typescript-plugin", "location": loc, "languages": ["vue"], "configNamespace": "typescript"]]
        }
        return LSPLaunch(executable: exe, args: ["--stdio"], initializationOptions: opts, variant: "tsserver")
    }

    // MARK: Vue

    static func vue(root: URL, manager: LanguageServerManager) -> LSPLaunch? {
        guard let exe = manager.resolveExecutable(["vue-language-server"]) else { return nil }
        var args = ["--stdio"]
        var opts: [String: Any] = ["vue": ["hybridMode": true]]
        if let lib = tsserverLib(root: root) {
            args.append("--tsdk=\(lib)")            // Volar 3 reads the TypeScript location from the command line
            opts["typescript"] = ["tsdk": lib]      // older Volar builds read it from initializationOptions
        }
        return LSPLaunch(executable: exe, args: args, initializationOptions: opts, variant: "volar")
    }

    // MARK: Tailwind

    static let tailwindConfigs = ["tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", "tailwind.config.mjs"]

    /// Nearest directory (from the file upwards) holding a tailwind.config.* or a package.json that depends on Tailwind
    /// (covers Tailwind v4's CSS-first setup, `@import "tailwindcss"`).
    static func tailwindRoot(for file: URL) -> URL? {
        var dir = file.deletingLastPathComponent().standardizedFileURL
        let home = NSHomeDirectory()
        while dir.path != "/" && dir.path != home {
            if tailwindConfigs.contains(where: { isFile(dir.appendingPathComponent($0).path) }) { return dir }
            let pkg = readPackageJSON(dir)
            if pkg.contains("\"tailwindcss\"") || pkg.contains("\"@tailwindcss/") { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: Optional private install

    /// Installs TypeScript 5 and the Vue TypeScript plugin into the private servers dir (only used when neither the
    /// project, a global install nor VS Code provides a tsserver). Never run automatically.
    static func installPrivateTypeScript(completion: @escaping (Bool) -> Void) {
        guard let npm = LanguageServerManager.shared.resolveExecutable(["npm"]) else { completion(false); return }
        try? fm.createDirectory(atPath: LanguageServerPrefs.privateServersDir, withIntermediateDirectories: true)
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: npm)
            p.arguments = ["install", "--prefix", LanguageServerPrefs.privateServersDir, "--no-audit", "--no-fund", "typescript@5",
                           "@vue/typescript-plugin"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = (npm as NSString).deletingLastPathComponent + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            let ok = ((try? p.run()) != nil) && { p.waitUntilExit(); return p.terminationStatus == 0 }()
            DispatchQueue.main.async {
                LanguageServerManager.shared.resetExecutableCache()
                completion(ok)
            }
        }
    }
}
