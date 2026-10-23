import AppKit

/// File > New File (Cmd-N): a QuickPicker-style popup that takes `dir/sub/file.ext`, creates the folders, seeds a template.
enum NewFile {
    enum Plan: Equatable {
        case hint, invalid(String), exists(URL), create(URL, hint: String)
    }

    /// Splits and validates a typed relative path; no I/O except the exists check.
    static func plan(_ typed: String, in dir: URL) -> Plan {
        var q = typed.trimmingCharacters(in: .whitespaces)
        while q.hasPrefix("/") { q.removeFirst() }
        if q.isEmpty { return .hint }
        if q.hasSuffix("/") { return .invalid("Add a file name after the folder") }
        let parts = q.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for p in parts where !FileOperations.isValid(name: p) { return .invalid("“\(p)” is not a valid name") }
        var url = dir
        for p in parts { url.appendPathComponent(p.trimmingCharacters(in: .whitespaces)) }
        if FileManager.default.fileExists(atPath: url.path) { return .exists(url) }
        return .create(url, hint: template(for: url).hint)
    }

    /// Starter content and a one-line description by extension. PHP classes get a namespace from composer PSR-4.
    static func template(for url: URL) -> (content: String, hint: String) {
        let stem = url.deletingPathExtension().lastPathComponent
        switch url.pathExtension.lowercased() {
        case "php":
            if url.lastPathComponent.hasSuffix(".blade.php") { return ("", "Blade view") }
            if let first = stem.first, first.isUppercase, let ns = namespace(forDirectory: url.deletingLastPathComponent()) {
                return ("<?php\n\nnamespace \(ns);\n\nclass \(stem)\n{\n    //\n}\n", "PHP class \(ns)\\\(stem)")
            }
            return ("<?php\n\n", "PHP file")
        case "vue":
            return ("<script setup>\n</script>\n\n<template>\n  <div></div>\n</template>\n", "Vue component")
        case "jsx", "tsx":
            return ("export default function \(stem)() {\n  return <div></div>\n}\n", "React component")
        case "js", "mjs", "cjs": return ("", "JavaScript file")
        case "ts": return ("", "TypeScript file")
        case "md": return ("# \(stem)\n", "Markdown document")
        default: return ("", "Empty file")
        }
    }

    static func namespace(forDirectory dir: URL) -> String? {
        guard let lp = LaravelProject.find(for: dir.appendingPathComponent("x")) else { return nil }
        let d = dir.standardizedFileURL.path
        for (prefix, dirs) in lp.psr4 {
            for base in dirs where d == base || d.hasPrefix(base + "/") {
                var ns = prefix.hasSuffix("\\") ? String(prefix.dropLast()) : prefix
                let rest = d.dropFirst(base.count).split(separator: "/").joined(separator: "\\")
                if !rest.isEmpty { ns += (ns.isEmpty ? "" : "\\") + rest }
                return ns.isEmpty ? nil : ns
            }
        }
        return nil
    }

    @discardableResult
    static func create(at url: URL) throws -> URL {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { throw FileOperations.OpError.exists(url.lastPathComponent) }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(template(for: url).content.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }
}

extension ProjectWindow {
    /// Selected tree folder, else the folder of the current file, else the project root.
    var newFileDirectory: URL? {
        if let u = tree.selectedURL, (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return u }
        if let id = tabs.selectedID, editors[id] != nil { return URL(fileURLWithPath: id).deletingLastPathComponent() }
        return root
    }

    func showNewFile(in dirOverride: URL? = nil) {
        guard let dir = dirOverride ?? newFileDirectory else { return }
        let rel = FileOperations.relativePath(dir, to: root)
        let shownDir = dir.standardizedFileURL.path == root?.standardizedFileURL.path ? "project root" : rel + "/"
        QuickPicker.present(over: window, placeholder: "New file in \(shownDir) (dir/sub/name.ext)", items: [], provider: { [weak self] q in
            switch NewFile.plan(q, in: dir) {
            case .hint:
                return [PickerItem(title: "Type a name or relative path", detail: "folders are created as needed", symbol: "doc.badge.plus") {}]
            case .invalid(let why):
                return [PickerItem(title: why, symbol: "exclamationmark.triangle") {}]
            case .exists(let url):
                return [PickerItem(title: "Open existing \(FileOperations.relativePath(url, to: dir))", detail: "already exists", symbol: "doc.text") {
                    self?.open(url)
                }]
            case .create(let url, let hint):
                return [PickerItem(title: "Create \(FileOperations.relativePath(url, to: dir))  (\(hint))", detail: "",
                                   symbol: FileIcon.symbol(forExtension: url.pathExtension)) { self?.finishNewFile(url) }]
            }
        })
    }

    private func finishNewFile(_ url: URL) {
        do {
            try NewFile.create(at: url)
            tree.refresh()
            tree.reveal(url)
            tree.onChange?(.created(url))
            open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// Menu target for File > New File.
final class NewFileSupport: NSObject {
    static let shared = NewFileSupport()
    @objc func show(_ sender: Any?) { (NSApp.delegate as? AppDelegate)?.active?.showNewFile() }
}
