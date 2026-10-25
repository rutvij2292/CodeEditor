import AppKit

/// Menu bar with PhpStorm's macOS key equivalents (derived from its bundled keymap).
enum MainMenu {
    private static func fn(_ code: Int) -> String { String(UnicodeScalar(UInt32(code))!) }
    private static let up = fn(NSUpArrowFunctionKey), down = fn(NSDownArrowFunctionKey),
        left = fn(NSLeftArrowFunctionKey), right = fn(NSRightArrowFunctionKey)
    private static let f12 = fn(NSF12FunctionKey), f1 = fn(NSF1FunctionKey), f2 = fn(NSF2FunctionKey), f3 = fn(NSF3FunctionKey)
    private static let f6 = fn(NSF6FunctionKey), f7 = fn(NSF7FunctionKey)
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

        main.addItem(menu(Brand.name, [
            item("About \(Brand.name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
            sep,
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ",", target: a),
            sep,
            item("Hide \(Brand.name)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            sep,
            item("Quit \(Brand.name)", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = a
        recent.submenu = recentMenu
        main.addItem(menu("File", [
            item("New File…", #selector(NewFileSupport.show(_:)), "n", target: NewFileSupport.shared),
            item("Open Project…", #selector(AppDelegate.openProjectPanel(_:)), "o", [.command, .control], target: a),
            recent,
            item("Open Project in New Instance…", #selector(AppDelegate.openProjectInNewInstancePanel(_:)), target: a),
            item("Recent Projects…", #selector(AppDelegate.showRecentProjects(_:)), "p", [.command, .shift], target: a),
            item("Reopen Windows on Launch", #selector(AppDelegate.toggleReopenWindows(_:)), target: a),
            sep,
            item("Save", #selector(AppDelegate.saveFile(_:)), "s", target: a),
            item("Save All", #selector(AppDelegate.saveAll(_:)), "s", [.command, .option], target: a),
            item("Reload Project from Disk", #selector(AppDelegate.reloadProjectFromDisk(_:)), "y", [.command, .option], target: a),
            item("Auto-Save on Focus Loss", #selector(AppDelegate.toggleAutoSaveFocus(_:)), target: a),
            item("Auto-Save on Tab Switch", #selector(AppDelegate.toggleAutoSaveTabSwitch(_:)), target: a),
            item("Local History…", #selector(AppDelegate.showLocalHistory(_:)), target: a),
            sep,
            item("Close Tab", #selector(AppDelegate.closeTab(_:)), "w", target: a),
            item("Reopen Closed Tab", #selector(AppDelegate.reopenClosedTab(_:)), "t", [.command, .shift], target: a),
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
            item("Find in Files…", #selector(AppDelegate.findInFiles(_:)), "f", [.command, .shift], target: a),
            item("Replace in Files…", #selector(AppDelegate.replaceInFiles(_:)), "r", [.command, .shift], target: a),
            sep,
            item("Send @File to Terminal", #selector(AppDelegate.sendFileToTerminal(_:)), "f", [.command, .option, .control], target: a),
            item("Send Selection Reference to Terminal", #selector(AppDelegate.sendSelectionReferenceToTerminal(_:)), "k", [.command, .option, .control], target: a),
            item("Send Selection Text to Terminal", #selector(AppDelegate.sendSelectionTextToTerminal(_:)), "k", [.command, .option, .shift], target: a),
            item("Ask Claude About Selection…", #selector(AppDelegate.askClaudeAboutSelection(_:)), "/", [.command, .option], target: a),
            item("Send Selection to Claude (@mention)", #selector(AppDelegate.sendSelectionToClaude(_:)), "j", [.command, .option], target: a),
            item("Write Claude Prompt…", #selector(AppDelegate.showClaudeComposer(_:)), "\r", [.command, .shift], target: a),
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
            sep,
            // Folding commands live on CodeTextView (nil target: disabled until the responder chain provides them).
            item("Fold Code Block", Selector(("foldCurrent:")), "-"),
            item("Unfold Code Block", Selector(("unfoldCurrent:")), "="),
            item("Fold All", Selector(("foldAll:")), "_", [.command, .shift]),
            item("Unfold All", Selector(("unfoldAll:")), "+", [.command, .shift]),
            item("Select Next Occurrence", Selector(("selectNextOccurrence:")), "g", [.control]),
            item("Unselect Occurrence", Selector(("unselectPreviousOccurrence:")), "g", [.control, .shift]),
            item("Select All Occurrences", Selector(("selectAllOccurrences:")), "g", [.control, .command]),
            item("Add Caret Above", Selector(("addCaretAbove:")), ""),
            item("Add Caret Below", Selector(("addCaretBelow:")), ""),
            sep,
            item("Reformat Code", #selector(AppDelegate.reformatCode(_:)), "l", [.command, .option], target: a),
            item("Show Quick Fixes and Actions…", #selector(AppDelegate.showQuickFixes(_:)), "\r", [.option], target: a),
            item("Edit Live Templates…", #selector(LiveTemplates.openTemplatesFile(_:)), "", target: LiveTemplates.shared),
            item("Optimize PHP Imports", #selector(PHPImportActions.optimizeImports(_:)), "o", [.control, .option], target: PHPImportActions.shared),
            item("Format Document", #selector(AppDelegate.formatDocument(_:)), "l", [.command, .option, .shift], target: a),
            item("Toggle Soft Wrap", Selector(("toggleSoftWrap:")), ""),
            item("Format JSON", #selector(ViewerSystem.formatJSON(_:)), target: ViewerSystem.shared),
            item("Minify JSON", #selector(ViewerSystem.minifyJSON(_:)), target: ViewerSystem.shared),
            sep,
            item("Basic Completion", Selector(("triggerCompletion:")), " ", [.control]),
            item("Smart Completion", Selector(("triggerSmartCompletion:")), " ", [.control, .shift]),
            item("Complete Current Statement", Selector(("completeCurrentStatement:")), "\r", [.command, .shift]),
            item("Parameter Info", Selector(("showParameterInfo:")), "p"),
            item("Quick Documentation", Selector(("showQuickDocumentation:")), "j", [.control]),
            item("Go to Declaration", Selector(("goToDefinition:")), "b"),
            item("Go to Implementation", #selector(NativePHPNav.goToImplementation(_:)), "b", [.command, .option], target: NativePHPNav.shared),
            item("Go to Type Declaration", #selector(NativePHPNav.goToTypeDeclaration(_:)), "b", [.control, .shift], target: NativePHPNav.shared),
        ]))

        main.addItem(menu("Navigate", [
            item("Toggle Bookmark", #selector(AppDelegate.toggleBookmark(_:)), f3, [], target: a),
            item("Next Bookmark", #selector(AppDelegate.nextBookmark(_:)), f3, [.option], target: a),
            item("Previous Bookmark", #selector(AppDelegate.previousBookmark(_:)), f3, [.option, .shift], target: a),
            sep,
            item("Go to File…", #selector(AppDelegate.goToFile(_:)), "o", [.command, .shift], target: a),
            item("Go to Class…", #selector(AppDelegate.goToClass(_:)), "o", target: a),
            item("Go to Symbol…", #selector(AppDelegate.goToSymbol(_:)), "o", [.command, .option], target: a),
            item("File Structure", #selector(AppDelegate.fileStructure(_:)), f12, [.command], target: a),
            item("Recent Files", #selector(AppDelegate.recentFiles(_:)), "e", target: a),
            item("Recent Locations", #selector(RecentLocationsSupport.show(_:)), "e", [.command, .shift], target: RecentLocationsSupport.shared),
            item("Plans…", #selector(PlanSupport.showPlans(_:)), "p", [.command, .option], target: PlanSupport.shared),
            item("Plan Changes Since Last Viewed…", #selector(PlanSupport.showPlanChanges(_:)), target: PlanSupport.shared),
            item("Mark Plan as Reviewed", #selector(PlanSupport.markReviewed(_:)), target: PlanSupport.shared),
            item("Add Plan Review Comment…", #selector(PlanSupport.addReviewComment(_:)), target: PlanSupport.shared),
            item("Search Everywhere", #selector(AppDelegate.searchEverywhere(_:)), "", target: a),
            item("Find Action…", #selector(AppDelegate.findAction(_:)), "a", [.command, .shift], target: a),
            item("Focus Breadcrumbs", #selector(AppDelegate.focusBreadcrumbs(_:)), up, [.command, .option], target: a),
            item("Go to Line…", #selector(AppDelegate.goToLine(_:)), "l", target: a),
            sep,
            item("Artisan Commands…", #selector(AppDelegate.artisanPalette(_:)), target: a),
            item("Laravel Routes…", #selector(AppDelegate.routeBrowser(_:)), target: a),
            item("Artisan Make…", #selector(AppDelegate.artisanMake(_:)), target: a),
            sep,
            item("Next Problem", #selector(AppDelegate.nextProblem(_:)), f2, [], target: a),
            item("Previous Problem", #selector(AppDelegate.previousProblem(_:)), f2, [.shift], target: a),
            item("Find Usages", #selector(AppDelegate.findUsages(_:)), f7, [.option], target: a),
            item("Rename…", #selector(AppDelegate.renameSymbol(_:)), f6, [.shift], target: a),
            sep,
            item("Back", #selector(AppDelegate.goBack(_:)), "[", target: a),
            item("Forward", #selector(AppDelegate.goForward(_:)), "]", target: a),
            item("Back (Alt)", #selector(AppDelegate.goBack(_:)), left, [.command, .option], target: a),
            item("Forward (Alt)", #selector(AppDelegate.goForward(_:)), right, [.command, .option], target: a),
            item("Previous Tab", #selector(AppDelegate.previousTab(_:)), "{", [.command, .shift], target: a),
            item("Next Tab", #selector(AppDelegate.nextTab(_:)), "}", [.command, .shift], target: a),
            sep,
            item("Move Caret to Matching Brace", #selector(BracketColorizer.moveCaretToMatchingBrace(_:)), "m", [.command, .shift], target: BracketColorizer.shared),
        ]))

        main.addItem(TestActions.menuItem())
        main.addItem(menu("Git", [
            item("Commit…", #selector(AppDelegate.commitChanges(_:)), "k", target: a),
            item("Push…", #selector(AppDelegate.pushChanges(_:)), "k", [.command, .shift], target: a),
            item("Update Project (Pull)", #selector(AppDelegate.updateProject(_:)), "t", target: a),
            item("Fetch", #selector(AppDelegate.fetchChanges(_:)), "", target: a),
            item("Branches…", #selector(AppDelegate.showBranches(_:)), "b", [.command, .option], target: a),
            item("New Branch…", #selector(AppDelegate.newBranch(_:)), "", target: a),
            item("Resolve Pull Request Conflicts…", #selector(AppDelegate.resolvePullRequest(_:)), "p", [.command, .option, .shift], target: a),
            item("Show History for File", #selector(AppDelegate.showFileHistory(_:)), "", target: a),
            item("Annotate with Git Blame", #selector(AppDelegate.toggleBlameAnnotations(_:)), "a", [.command, .option], target: a),
            toggleItem("Toggle Inline Blame", "inlineBlame", a),
            item("Review Diff with Claude…", #selector(AppDelegate.reviewDiffWithClaude(_:)), "", target: a),
            sep,
            item("Show Git Panel", #selector(AppDelegate.toggleGit(_:)), "9", target: a),
        ]))

        main.addItem(menu("View", [
            item("Project Tree", #selector(AppDelegate.focusTree(_:)), "1", target: a),
            item("Toggle Sidebar", #selector(AppDelegate.toggleSidebar(_:)), "\\", target: a),
            item("Focus Editor", #selector(AppDelegate.focusEditor(_:)), "\u{1b}", target: a),
            item("Editor", #selector(AppDelegate.focusEditor(_:)), "2", target: a),
            item("Claude Code", #selector(AppDelegate.showClaudeTool(_:)), "3", target: a),
            item("Find Tool Window", #selector(AppDelegate.showFindTool(_:)), "4", target: a),
            item("Problems Tool Window", #selector(AppDelegate.showProblemsTool(_:)), "5", target: a),
            item("Structure Tool Window", #selector(AppDelegate.showStructureTool(_:)), "7", target: a),
            item("TODO Tool Window", #selector(AppDelegate.showTodoTool(_:)), "8", target: a),
            item("Bookmarks Tool Window", #selector(AppDelegate.showBookmarksTool(_:)), "2", [.command, .option], target: a),
            item("HTTP Client Tool Window", #selector(AppDelegate.showHttpTool(_:)), "8", [.command, .option], target: a),
            item("Claude Changes Tool Window", #selector(AppDelegate.showClaudeChangesTool(_:)), "", target: a),
            item("Last Tool Window", #selector(AppDelegate.jumpToLastTool(_:)), f12, [], target: a),
            item("Hide All Tool Windows", #selector(AppDelegate.hideAllTools(_:)), f12, [.command, .shift], target: a),
            sep,
            item("Select Opened File", #selector(AppDelegate.selectOpenedFile(_:)), f1, [.option], target: a),
            item("Terminal", #selector(AppDelegate.showTerminal(_:)), f12, [.option], target: a),
            item("Focus Terminal", #selector(AppDelegate.focusTerminal(_:)), "`", [.control], target: a),
            item("Maximize Terminal", #selector(AppDelegate.maximizeTerminal(_:)), target: a),
            item("Collapse All in Tree", #selector(AppDelegate.collapseAll(_:)), "-", [.command, .control], target: a),
            item("Include vendor in Go to File", #selector(AppDelegate.toggleIncludeVendor(_:)), target: a),
            item("Format on Save", #selector(AppDelegate.toggleFormatOnSave(_:)), target: a),
            item("Restart Language Servers", #selector(AppDelegate.restartLanguageServers(_:)), target: a),
            sep,
            item("Cycle Source / Split / Preview", #selector(ViewerSystem.cycleMode(_:)), "v", [.command, .option, .control], target: ViewerSystem.shared),
            item("Source Only", #selector(ViewerSystem.showSource(_:)), target: ViewerSystem.shared),
            item("Split View", #selector(ViewerSystem.showSplit(_:)), target: ViewerSystem.shared),
            item("Preview Only", #selector(ViewerSystem.showPreview(_:)), target: ViewerSystem.shared),
            sep,
            item("Split Right", #selector(AppDelegate.splitEditorRight(_:)), "\\", [.command, .option], target: a),
            item("Unsplit", #selector(AppDelegate.unsplitEditor(_:)), target: a),
            sep,
            toggleItem("Toolbar", "showToolbar", a),
            toggleItem("Tool Window Icons", "showToolStrip", a),
            toggleItem("Breadcrumbs", "showBreadcrumbs", a),
            toggleItem("Inline Git Blame", "inlineBlame", a),
            toggleItem("Indent Guides", "showIndentGuides", a),
            toggleItem("Current Line", "highlightCurrentLine", a),
            toggleItem("Line Numbers", "showLineNumbers", a),
            toggleItem("Soft Wrap", "softWrap", a),
            sep,
            appearanceMenu(a),
            item("Bracket Pair Colorization", #selector(BracketColorizer.toggleBracketColorization(_:)), target: BracketColorizer.shared),
        ]))

        main.addItem(menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ]))
        KeymapStore.apply(to: main)       // user shortcut overrides (Settings > Keymap)
        return main
    }

    /// A View/Git menu checkmark item bound to a `Prefs` Boolean (see `AppDelegate.togglePreference`).
    private static func toggleItem(_ title: String, _ key: String, _ a: AppDelegate) -> NSMenuItem {
        let i = item(title, #selector(AppDelegate.togglePreference(_:)), target: a)
        i.representedObject = key
        return i
    }

    /// Shortcuts bound to more than one menu item ("⌘K: Commit…, Foo"). Empty when every key equivalent is unique.
    static func duplicateShortcuts(in menu: NSMenu) -> [String] {
        var seen: [String: [String]] = [:]
        func walk(_ m: NSMenu, path: String) {
            for i in m.items where !i.isSeparatorItem {
                if let sub = i.submenu { walk(sub, path: path + i.title + " › ") }
                guard !i.keyEquivalent.isEmpty else { continue }
                let mask = i.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift])
                seen[shortcutText(for: i) + "|" + String(mask.rawValue), default: []].append(path + i.title)
            }
        }
        for top in menu.items { if let sub = top.submenu { walk(sub, path: top.title + " › ") } }
        // AppKit injects Dictation / Emoji items into Edit (each twice under one title): not ours.
        return seen.filter { Set($0.value).count > 1 }.map { String($0.key.split(separator: "|")[0]) + ": " + $0.value.joined(separator: ", ") }.sorted()
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
        case 0x1B: out += "⎋"
        case 9: out += "⇥"
        case UInt32(NSF1FunctionKey)...UInt32(NSF12FunctionKey): out += "F\(key.unicodeScalars.first!.value - UInt32(NSF1FunctionKey) + 1)"
        case 0x20: out += "Space"
        case 0x2D, 0x5F: out += "−"        // - and _ (shifted)
        case 0x3D, 0x2B: out += "="        // = and + (shifted)
        default: out += key.uppercased()
        }
        return out
    }
}
