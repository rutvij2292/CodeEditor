import Foundation

/// CE_SELFTEST: each native language engine is separately switchable and the external servers they replace stay stopped by default.
enum SelfTestEngineSwitches {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("engines: " + name, ok()) }

    static func run() {
        let d = UserDefaults.standard
        let keys = [NativePy.enabledKey, NativeJS.nativeOnlyKey, NativeVue.nativeOnlyKey, NativeWeb.enabledKey, NativeWeb.nativeOnlyKey, NativeWeb.tailwindEnabledKey, NativeWeb.tailwindNativeOnlyKey, NativePHP.nativeOnlyKey]
        let saved = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }
        keys.forEach { d.removeObject(forKey: $0) }

        func u(_ n: String) -> URL { URL(fileURLWithPath: "/p/" + n) }
        check("no Cmd-hover link look on plain JS / TS files", ["a.js", "a.ts", "a.tsx", "a.jsx", "a.mjs", "a.cts"].allSatisfy { !NativeEngines.allowsLinkHighlight(u($0)) })
        check("...but still on PHP, Vue, CSS and Python files", ["a.php", "a.vue", "a.css", "a.py", "a.blade.php"].allSatisfy { NativeEngines.allowsLinkHighlight(u($0)) })
        check("defaults: Python engine off (opt-in), Volar and the TypeScript server not started",
              !NativePy.enabled && NativeEngines.suppressesServer("volar") && NativeEngines.suppressesServer("typescript", root: FileManager.default.temporaryDirectory))
        check("defaults: intelephense, html, css and tailwind servers are not started",
              ["intelephense", "html", "css", "tailwind"].allSatisfy { !LanguageServerPrefs.isEnabled($0) })
        NativeWeb.nativeOnly = false
        check("html/css servers come back with their own switch", LanguageServerPrefs.isEnabled("html") && LanguageServerPrefs.isEnabled("css"))
        check("...without starting the tailwind server", !LanguageServerPrefs.isEnabled("tailwind"))
        NativeWeb.tailwindNativeOnly = false
        check("tailwind server has its own switch", LanguageServerPrefs.isEnabled("tailwind"))
        NativeWeb.nativeOnly = true
        check("...independent of html/css", LanguageServerPrefs.isEnabled("tailwind") && !LanguageServerPrefs.isEnabled("html"))
        NativeWeb.tailwindEnabled = false
        let web = NWProject.shared(root: FileManager.default.temporaryDirectory.path)
        check("tailwind engine off: no theme, no discovery", web.tailwind(near: nil) == nil && !NativeWeb.tailwindActive(for: FileManager.default.temporaryDirectory.appendingPathComponent("a.html")))
    }
}
