import AppKit

/// CE_SELFTEST: code-action parsing / ordering (the server round trip needs a live language server).
enum SelfTestCodeActions {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run() {
        let config = LanguageServerConfig(id: "fake", name: "Fake", extensions: ["ts"], languageIds: [:], executables: [], args: [],
                                          rootMarkers: [], installHint: "", reportMissing: false, defaultTriggers: [],
                                          initializationOptions: { _ in [:] }, settings: [:])
        let inst = LSPServerInstance(config: config, root: URL(fileURLWithPath: "/tmp"), manager: LanguageServerManager.shared)
        let raw: [[String: Any]] = [
            ["title": "Organize imports", "kind": "source.organizeImports"],
            ["title": "Extract to function", "kind": "refactor.extract.function"],
            ["title": "Add missing import", "kind": "quickfix", "isPreferred": true, "edit": ["changes": [String: Any]()]],
            ["title": "Disabled thing", "kind": "refactor", "disabled": ["reason": "nope"]],
            ["title": "Fix spelling", "kind": "quickfix"],
            ["title": "Run server command", "command": "server.doIt", "arguments": [1]],
            ["kind": "quickfix"],
        ]
        let parsed = LSPCodeAction.parse(raw, instance: inst)
        check("code actions: disabled and untitled entries are dropped", parsed.count == 5)
        let sorted: [String] = LSPCodeAction.sorted(parsed).map { $0.title }
        let expected: [String] = ["Add missing import", "Fix spelling", "Extract to function", "Organize imports", "Run server command"]
        check("code actions: preferred first, then quick fixes, refactors, source", sorted == expected)
        let command = parsed.first { $0.title == "Run server command" }
        check("code actions: a bare Command is wrapped so it can be executed",
              (command?.raw["command"] as? [String: Any])?["command"] as? String == "server.doIt")
        check("code actions: kind labels", parsed.first { $0.title == "Organize imports" }?.kindLabel == "Organize Imports"
              && parsed.first { $0.title == "Extract to function" }?.kindLabel == "Extract"
              && parsed.first { $0.title == "Fix spelling" }?.kindLabel == "Quick Fix")
        check("code actions: nothing parses from null", LSPCodeAction.parse(NSNull(), instance: inst).isEmpty)
    }
}
