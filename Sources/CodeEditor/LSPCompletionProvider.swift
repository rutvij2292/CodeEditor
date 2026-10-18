import AppKit

/// CompletionProvider backed by a language server (one instance per server id).
final class LSPCompletionProvider: CompletionProvider {
    let serverId: String
    private var inflight: (client: LSPClient, id: Int)?
    private let work = DispatchQueue(label: "codeeditor.lsp.completion", qos: .userInitiated)

    init(serverId: String) { self.serverId = serverId }

    var triggerCharacters: [String] {
        let mgr = LanguageServerManager.shared
        if let inst = mgr.instances.values.first(where: { $0.config.id == serverId && $0.isInitialized }) {
            // Quote, bracket and comma triggers are too noisy for an auto-opening popup.
            return inst.triggerCharacters.filter { !["(", ",", " ", "'", "\"", "[", "`"].contains($0) }
        }
        return LanguageServerConfig.table.first { $0.id == serverId }?.defaultTriggers ?? []
    }

    func cancel() {
        if let f = inflight { f.client.cancel(f.id) }
        inflight = nil
    }

    func complete(_ context: CompletionContext,
                  deliver: @escaping (_ items: [CompletionItem], _ isIncomplete: Bool) -> Void) {
        cancel()
        let mgr = LanguageServerManager.shared
        guard let session = mgr.session(forURL: context.fileURL), let inst = session.instance(serverId),
              inst.supports("completionProvider"), let client = inst.client else { deliver([], false); return }
        session.flushChanges()
        let table = LSPLineTable(context.text as NSString)
        var ctx: [String: Any] = ["triggerKind": context.triggerCharacter != nil ? 2 : 1]
        if let t = context.triggerCharacter { ctx["triggerCharacter"] = t }
        let params: [String: Any] = ["textDocument": ["uri": session.uri],
                                     "position": table.lspPosition(context.caret), "context": ctx]
        let canResolve = ((inst.capabilities["completionProvider"] as? [String: Any])?["resolveProvider"] as? Bool) == true
        let id = client.request("textDocument/completion", params, timeout: 10, on: work) { result in
            guard case .success(let value) = result else { deliver([], false); return }
            var rawItems: [[String: Any]] = []
            var incomplete = false
            if let a = value as? [[String: Any]] { rawItems = a }
            else if let d = value as? [String: Any] {
                rawItems = (d["items"] as? [[String: Any]]) ?? []
                incomplete = (d["isIncomplete"] as? Bool) ?? false
            }
            let items = rawItems.map { Self.map($0, table: table, client: canResolve ? client : nil) }
            deliver(items, incomplete)
        }
        inflight = (client, id)
    }

    // MARK: Mapping

    static func kind(_ n: Int) -> CompletionKind {
        switch n {
        case 1: return .text
        case 2: return .method
        case 3: return .function
        case 4: return .constructor
        case 5: return .field
        case 6: return .variable
        case 7: return .class
        case 8: return .interface
        case 9: return .module
        case 10: return .property
        case 11, 12: return .value
        case 13: return .enum
        case 14: return .keyword
        case 15: return .snippet
        case 16: return .color
        case 17: return .file
        case 18: return .value
        case 19: return .folder
        case 20: return .enumMember
        case 21: return .constant
        case 22: return .struct
        case 23: return .value
        case 24: return .operator
        case 25: return .typeParameter
        default: return .text
        }
    }

    static func map(_ raw: [String: Any], table: LSPLineTable, client: LSPClient?) -> CompletionItem {
        let label = (raw["label"] as? String) ?? ""
        var item = CompletionItem(label: label, insertText: label,
                                  kind: kind((raw["kind"] as? NSNumber)?.intValue ?? 1))
        var insert = (raw["insertText"] as? String) ?? label
        if let edit = raw["textEdit"] as? [String: Any] {
            if let t = edit["newText"] as? String { insert = t }
            if let r = (edit["range"] ?? edit["replace"]) as? [String: Any], let nr = table.range(fromLSP: r) { item.replaceRange = nr }
        }
        item.insertText = insert
        item.isSnippet = (raw["insertTextFormat"] as? NSNumber)?.intValue == 2
        var detail = (raw["detail"] as? String) ?? ""
        if let ld = raw["labelDetails"] as? [String: Any] {
            let extra = ((ld["detail"] as? String) ?? "") + ((ld["description"] as? String).map { " " + $0 } ?? "")
            if detail.isEmpty { detail = extra.trimmingCharacters(in: .whitespaces) }
        }
        item.detail = detail
        item.documentation = LSPUIParse.documentation(raw["documentation"])
        item.sortText = raw["sortText"] as? String
        item.filterText = raw["filterText"] as? String
        item.deprecated = (raw["deprecated"] as? Bool) == true
            || ((raw["tags"] as? [NSNumber])?.contains { $0.intValue == 1 } ?? false)
        item.additionalEdits = additionalEdits(raw, table: table)
        if let client, raw["documentation"] == nil || raw["additionalTextEdits"] == nil {
            item.resolve = { done in
                client.request("completionItem/resolve", raw, timeout: 5) { result in
                    guard case .success(let v) = result, let resolved = v as? [String: Any] else { done(item); return }
                    var updated = item
                    updated.resolve = nil
                    let doc = LSPUIParse.documentation(resolved["documentation"])
                    if !doc.isEmpty { updated.documentation = doc }
                    if let d = resolved["detail"] as? String, !d.isEmpty { updated.detail = d }
                    let edits = additionalEdits(resolved, table: table)
                    if !edits.isEmpty { updated.additionalEdits = edits }
                    done(updated)
                }
            }
        }
        return item
    }

    private static func additionalEdits(_ raw: [String: Any], table: LSPLineTable) -> [(range: NSRange, text: String)] {
        ((raw["additionalTextEdits"] as? [[String: Any]]) ?? []).compactMap { e in
            guard let r = e["range"] as? [String: Any], let range = table.range(fromLSP: r) else { return nil }
            return (range, (e["newText"] as? String) ?? "")
        }
    }
}
