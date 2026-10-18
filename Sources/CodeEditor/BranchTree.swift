import Foundation

/// Collapse state of the popup tree (survives reopening within the session).
struct BranchCollapseState: Equatable {
    var collapsed: Set<String> = []
    var expanded: Set<String> = []     // explicit expands that override default-collapsed nodes
}

struct BranchTreeRow: Equatable {
    enum Kind: Equatable {
        case node(folder: Bool, collapsed: Bool, count: Int)
        case branch(BranchEntry)
        case tag
    }
    var kind: Kind
    var title: String
    var key: String
    var depth: Int

    /// "▾ Local", "  ▸ feature/ (3)", "    login-form" — compact form for tests.
    var signature: String {
        let pad = String(repeating: "  ", count: depth)
        switch kind {
        case .node(_, let c, let n): return pad + (c ? "▸ " : "▾ ") + title + (c ? " (\(n))" : "")
        case .branch(let e): return pad + title + (e.isCurrent ? " *" : "")
        case .tag: return pad + title + " [tag]"
        }
    }
}

/// Pure tree building for the branch popup: Recent / Local / Remote (and Tags) sections with prefix folders.
enum BranchTree {
    /// `keys` receives every node key (used by collapse-all / expand-all). `forceExpanded` ignores the collapse state.
    static func flatten(_ l: BranchList, favorites: Set<String>, groupByPrefix: Bool, showTags: Bool,
                        state: BranchCollapseState, forceExpanded: Bool = false, keys: inout [String]) -> [BranchTreeRow] {
        var out: [BranchTreeRow] = []
        func isCollapsed(_ key: String, defaultCollapsed: Bool) -> Bool {
            if forceExpanded { return false }
            if state.collapsed.contains(key) { return true }
            return defaultCollapsed && !state.expanded.contains(key)
        }
        func node(_ title: String, _ key: String, _ depth: Int, folder: Bool, count: Int, defaultCollapsed: Bool = false) -> Bool {
            keys.append(key)
            let c = isCollapsed(key, defaultCollapsed: defaultCollapsed)
            out.append(BranchTreeRow(kind: .node(folder: folder, collapsed: c, count: count), title: title, key: key, depth: depth))
            return c
        }
        func ordered(_ items: [BranchEntry], _ display: (BranchEntry) -> String) -> [BranchEntry] {
            items.sorted {
                let fa = favorites.contains($0.name), fb = favorites.contains($1.name)
                if fa != fb { return fa }
                if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
                return display($0).localizedStandardCompare(display($1)) == .orderedAscending
            }
        }
        func group(_ entries: [BranchEntry], keyPrefix: String, depth: Int, defaultCollapsedFolders: Bool, display: (BranchEntry) -> String) {
            var folders: [String: [BranchEntry]] = [:]
            var plain: [BranchEntry] = []
            for e in entries {
                let d = display(e)
                if groupByPrefix, let slash = d.firstIndex(of: "/") { folders[String(d[..<slash]), default: []].append(e) } else { plain.append(e) }
            }
            for name in folders.keys.sorted() {
                let items = folders[name]!
                let key = keyPrefix + "/" + name
                let hasCurrent = items.contains { $0.isCurrent }
                let c = node(name, key, depth, folder: true, count: items.count, defaultCollapsed: defaultCollapsedFolders && !hasCurrent)
                if c { continue }
                for e in ordered(items, display) {
                    out.append(BranchTreeRow(kind: .branch(e), title: String(display(e).dropFirst(name.count + 1)), key: "b:" + e.name, depth: depth + 1))
                }
            }
            for e in ordered(plain, display) {
                out.append(BranchTreeRow(kind: .branch(e), title: display(e), key: "b:" + e.name, depth: depth))
            }
        }

        let recents = l.recent.compactMap { n in l.local.first { $0.name == n } }
        if !recents.isEmpty, !node("Recent", "recent", 0, folder: false, count: recents.count) {
            group(recents, keyPrefix: "recent", depth: 1, defaultCollapsedFolders: false) { $0.name }
        }
        if !l.local.isEmpty, !node("Local", "local", 0, folder: false, count: l.local.count) {
            group(l.local, keyPrefix: "local", depth: 1, defaultCollapsedFolders: false) { $0.name }
        }
        if !l.remote.isEmpty, !node("Remote", "remote", 0, folder: false, count: l.remote.count) {
            let names = l.remotes.isEmpty ? Array(Set(l.remote.compactMap(\.remote))).sorted() : l.remotes
            for r in names {
                let items = l.remote.filter { $0.remote == r }
                guard !items.isEmpty else { continue }
                if !node(r, "remote:" + r, 1, folder: true, count: items.count) {
                    group(items, keyPrefix: "remote:" + r, depth: 2, defaultCollapsedFolders: true) { $0.shortName }
                }
            }
        }
        if showTags, !l.tags.isEmpty, !node("Tags", "tags", 0, folder: false, count: l.tags.count, defaultCollapsed: true) {
            for t in l.tags { out.append(BranchTreeRow(kind: .tag, title: t, key: "t:" + t, depth: 1)) }
        }
        return out
    }

    /// Toggles `key`: an effectively collapsed node expands, an expanded one collapses.
    static func toggle(_ key: String, currentlyCollapsed: Bool, state: inout BranchCollapseState) {
        if currentlyCollapsed { state.collapsed.remove(key); state.expanded.insert(key) }
        else { state.collapsed.insert(key); state.expanded.remove(key) }
    }

    static func collapseAll(_ l: BranchList, favorites: Set<String>, groupByPrefix: Bool, showTags: Bool) -> BranchCollapseState {
        var keys: [String] = []
        _ = flatten(l, favorites: favorites, groupByPrefix: groupByPrefix, showTags: showTags, state: BranchCollapseState(), forceExpanded: true, keys: &keys)
        return BranchCollapseState(collapsed: Set(keys), expanded: [])
    }

    static func expandAll(_ l: BranchList, favorites: Set<String>, groupByPrefix: Bool, showTags: Bool) -> BranchCollapseState {
        var keys: [String] = []
        _ = flatten(l, favorites: favorites, groupByPrefix: groupByPrefix, showTags: showTags, state: BranchCollapseState(), forceExpanded: true, keys: &keys)
        return BranchCollapseState(collapsed: [], expanded: Set(keys))
    }
}
