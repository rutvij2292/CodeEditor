import AppKit

/// Menu bar with PhpStorm's macOS key equivalents (derived from its bundled keymap).
enum MainMenu {
    private static func fn(_ code: Int) -> String { String(UnicodeScalar(UInt32(code))!) }
    private static let up = fn(NSUpArrowFunctionKey), down = fn(NSDownArrowFunctionKey)
    private static let f12 = fn(NSF12FunctionKey), f1 = fn(NSF1FunctionKey)
    private static let backspace = "\u{7f}"

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        item.target = target
        return item
    }

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem($0.isSeparatorItem ? NSMenuItem.separator() : $0) }
        top.submenu = menu
        return top
    }

    private static let sep = NSMenuItem.separator()

    static func build(app: AppDelegate) -> NSMenu {
        let a = app
        let main = NSMenu()

        main.addItem(menu("CodeEditor", [
            item("Hide CodeEditor", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            sep,
            item("Quit CodeEditor", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = a
        recent.submenu = recentMenu
        main.addItem(menu("File", [
            item("Open Project…", #selector(AppDelegate.openProjectPanel(_:)), "o", [.command, .control], target: a),
            recent,
            item("Recent Projects…", #selector(AppDelegate.showRecentProjects(_:)), "p", [.command, .shift], target: a),
            sep,
            item("Save", #selector(AppDelegate.saveFile(_:)), "s", target: a),
            item("Save All", #selector(AppDelegate.saveAll(_:)), "s", [.command, .option], target: a),
            sep,
            item("Close Tab", #selector(AppDelegate.closeTab(_:)), "w", target: a),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
        ]))

        let find = NSMenu(title: "Find")
        for (title, key, mods, tag) in [("Find…", "f", NSEvent.ModifierFlags.command, NSFindPanelAction.showFindPanel),
                                        ("Find Next", "g", .command, .next),
                                        ("Find Previous", "g", [.command, .shift], .previous)] as [(String, String, NSEvent.ModifierFlags, NSFindPanelAction)] {
            let i = item(title, #selector(NSTextView.performFindPanelAction(_:)), key, mods)
            i.tag = Int(tag.rawValue)
            find.addItem(i)
        }
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find
        main.addItem(menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            sep,
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            sep,
            findItem,
        ]))

        main.addItem(menu("Code", [
            item("Duplicate Line", Selector(("duplicateLine:")), "d"),
            item("Delete Line", Selector(("deleteLine:")), backspace),
            item("Move Line Up", Selector(("moveLineUp:")), up, [.option, .shift]),
            item("Move Line Down", Selector(("moveLineDown:")), down, [.option, .shift]),
            item("Comment with Line Comment", Selector(("toggleComment:")), "/"),
            item("Join Lines", Selector(("joinLines:")), "j", [.control, .shift]),
            item("Toggle Case", Selector(("toggleCase:")), "u", [.command, .shift]),
            sep,
            item("Extend Selection", Selector(("extendSelection:")), up, [.option]),
            item("Shrink Selection", Selector(("shrinkSelection:")), down, [.option]),
            item("Select Next Occurrence", Selector(("selectNextOccurrence:")), "g", [.control]),
            item("Unselect Occurrence", Selector(("unselectPreviousOccurrence:")), "g", [.control, .shift]),
            item("Select All Occurrences", Selector(("selectAllOccurrences:")), "g", [.control, .command]),
            sep,
            item("Reformat Code", Selector(("reformatCode:")), "l", [.command, .option]),
            sep,
            item("Basic Completion", Selector(("triggerCompletion:")), " ", [.control]),
            item("Parameter Info", Selector(("showParameterInfo:")), "p"),
            item("Quick Documentation", Selector(("showQuickDocumentation:")), "j", [.control]),
            item("Go to Declaration", Selector(("goToDefinition:")), "b"),
        ]))

        main.addItem(menu("Navigate", [
            item("Go to File…", #selector(AppDelegate.goToFile(_:)), "o", [.command, .shift], target: a),
            item("Go to Class…", #selector(AppDelegate.goToClass(_:)), "o", target: a),
            item("Go to Symbol…", #selector(AppDelegate.goToSymbol(_:)), "o", [.command, .option], target: a),
            item("File Structure", #selector(AppDelegate.fileStructure(_:)), f12, [.command], target: a),
            item("Recent Files", #selector(AppDelegate.recentFiles(_:)), "e", target: a),
            item("Search Everywhere", #selector(AppDelegate.searchEverywhere(_:)), "", target: a),
            item("Find Action…", #selector(AppDelegate.findAction(_:)), "a", [.command, .shift], target: a),
            item("Go to Line…", #selector(AppDelegate.goToLine(_:)), "l", target: a),
            sep,
            item("Back", #selector(AppDelegate.goBack(_:)), "[", target: a),
            item("Forward", #selector(AppDelegate.goForward(_:)), "]", target: a),
            item("Previous Tab", #selector(AppDelegate.previousTab(_:)), "{", [.command, .shift], target: a),
            item("Next Tab", #selector(AppDelegate.nextTab(_:)), "}", [.command, .shift], target: a),
            sep,
            item("Move Caret to Matching Brace", #selector(BracketColorizer.moveCaretToMatchingBrace(_:)), "m", [.command, .shift], target: BracketColorizer.shared),
        ]))

        main.addItem(menu("Git", [
            item("Commit…", #selector(AppDelegate.commitChanges(_:)), "k", target: a),
            item("Push…", #selector(AppDelegate.pushChanges(_:)), "k", [.command, .shift], target: a),
            item("Update Project (Pull)", #selector(AppDelegate.updateProject(_:)), "t", target: a),
            item("Fetch", #selector(AppDelegate.fetchChanges(_:)), "", target: a),
            sep,
            item("Show Git Panel", #selector(AppDelegate.toggleGit(_:)), "9", target: a),
        ]))

        main.addItem(menu("View", [
            item("Project Tree", #selector(AppDelegate.focusTree(_:)), "1", target: a),
            item("Commit Panel", #selector(AppDelegate.commitChanges(_:)), "0", target: a),
            item("Select Opened File", #selector(AppDelegate.selectOpenedFile(_:)), f1, [.option], target: a),
            item("Collapse All in Tree", #selector(AppDelegate.collapseAll(_:)), "-", target: a),
            sep,
            appearanceMenu(a),
            item("Bracket Pair Colorization", #selector(BracketColorizer.toggleBracketColorization(_:)), target: BracketColorizer.shared),
        ]))

        main.addItem(menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ]))
        return main
    }

    private static func appearanceMenu(_ a: AppDelegate) -> NSMenuItem {
        let top = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Appearance")
        sub.delegate = a
        for (title, sel) in [("System", #selector(AppDelegate.themeSystem(_:))), ("Light", #selector(AppDelegate.themeLight(_:))),
                             ("Dark", #selector(AppDelegate.themeDark(_:)))] {
            sub.addItem(item(title, sel, target: a))
        }
        top.submenu = sub
        return top
    }

    /// "⌃⌥⇧⌘D" style text for a menu item's key equivalent.
    static func shortcutText(for item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        var out = ""
        if m.contains(.control) { out += "⌃" }
        if m.contains(.option) { out += "⌥" }
        if m.contains(.shift) { out += "⇧" }
        if m.contains(.command) { out += "⌘" }
        let key = item.keyEquivalent
        switch key.unicodeScalars.first!.value {
        case UInt32(NSUpArrowFunctionKey): out += "↑"
        case UInt32(NSDownArrowFunctionKey): out += "↓"
        case UInt32(NSLeftArrowFunctionKey): out += "←"
        case UInt32(NSRightArrowFunctionKey): out += "→"
        case 0x7f: out += "⌫"
        case 13: out += "↩"
        case UInt32(NSF1FunctionKey): out += "F1"
        case UInt32(NSF12FunctionKey): out += "F12"
        default: out += key.uppercased()
        }
        return out
    }
}
