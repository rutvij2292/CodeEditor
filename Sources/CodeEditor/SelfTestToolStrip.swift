import AppKit

/// CE_SELFTEST: the left tool-window icon strip exists, maps to the real tools, follows visibility and honours the pref.
enum SelfTestToolStrip {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run(w: ProjectWindow) {
        guard let strip = w.toolStrip else { check("tool strip: installed", false); return }
        Prefs.showToolStrip = true
        w.window.contentView?.layoutSubtreeIfNeeded()
        check("tool strip: visible by default, ~40 pt wide, at the far left",
              !strip.isHidden && abs(strip.frame.width - 40) < 0.5 && strip.frame.minX == 0 && w.window.contentViewController is ToolStripContainerController)
        check("tool strip: sits left of the split views", strip.frame.maxX <= w.rootSplit.view.frame.minX + 0.5)
        let all = ToolStripView.top + ToolStripView.middle + ToolStripView.bottomGroup
        check("tool strip: every entry has a button, icon, tooltip and VoiceOver label",
              all.allSatisfy { e in
                  guard let b = strip.buttons[e.id] else { return false }
                  return b.image != nil && (b.toolTip ?? "").hasPrefix(e.title) && b.accessibilityLabel() != nil
              })
        check("tool strip: overflow entries have icons", ToolStripView.overflow.allSatisfy { ToolStripView.icon($0.symbol, $0.title) != nil })
        check("tool strip: tooltips carry shortcuts", strip.buttons["git"]?.toolTip == "Git (⌘9)" && strip.buttons["project"]?.toolTip == "Project (⌘1)")

        // Bottom tools: click shows, click again hides; active follows the panel.
        w.bottom.hide()
        let problems = strip.entry(id: "problems")!
        check("tool strip: problems idle", !strip.isActive(problems))
        strip.buttons["problems"]?.performClick(nil)
        check("tool strip: problems button shows the tool", w.bottom.isVisible && w.bottom.selectedID == "problems" && strip.isActive(problems))
        check("tool strip: highlight drawn on the active button", strip.buttons["problems"]?.layer?.backgroundColor != nil)
        let git = strip.entry(id: "git")!
        w.bottom.show("git")
        check("tool strip: active follows tab switch", strip.isActive(git) && !strip.isActive(problems) && strip.buttons["problems"]?.layer?.backgroundColor == nil)
        strip.buttons["git"]?.performClick(nil)
        check("tool strip: clicking the active tool hides it", !w.bottom.isVisible && !strip.isActive(git))
        for id in ["structure", "bookmarks", "tests"] {
            strip.buttons[id]?.performClick(nil)
            check("tool strip: \(id) button opens the \(id) tool", w.bottom.isVisible && w.bottom.selectedID == id)
            w.bottom.hide()
        }

        // Sidebar button follows the sidebar.
        let project = strip.entry(id: "project")!
        check("tool strip: project active state matches the sidebar", strip.isActive(project) == w.isSidebarVisible)
        w.termDock.sidebarItem.isCollapsed = true
        strip.refresh()
        check("tool strip: collapsed sidebar clears the project highlight", !strip.isActive(project) && strip.buttons["project"]?.layer?.backgroundColor == nil)
        w.termDock.sidebarItem.isCollapsed = false
        strip.refresh()
        check("tool strip: expanded sidebar highlights the project button", strip.isActive(project))

        // Problems badge dot.
        w.setToolPanelBadge("3", for: "problems")
        check("tool strip: problems badge dot appears", strip.buttons["problems"]?.toolTip?.contains("3") == true && strip.buttons["problems"]?.subviews.contains { !$0.isHidden && $0.frame.width == 8 } == true)
        w.setToolPanelBadge(nil, for: "problems")
        check("tool strip: badge dot clears", strip.buttons["problems"]?.toolTip == "Problems (⌘5)")

        // Preference hides it and gives the space back.
        Prefs.showToolStrip = false
        w.window.contentView?.layoutSubtreeIfNeeded()
        check("tool strip: pref off hides it and frees the width", strip.isHidden && strip.frame.width < 1)
        Prefs.showToolStrip = true
        w.window.contentView?.layoutSubtreeIfNeeded()
        check("tool strip: pref on restores it", !strip.isHidden && abs(strip.frame.width - 40) < 0.5)
        check("tool strip: pref registered for the View menu", AppDelegate.preferenceToggles["showToolStrip"] != nil && Prefs.allKeys.contains("showToolStrip"))
        w.bottom.hide()
        w.focusEditor()
    }
}
