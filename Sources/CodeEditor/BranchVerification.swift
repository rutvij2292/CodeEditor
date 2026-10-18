import AppKit

/// CE_SNAPSHOT=1 CE_PICKER=branches|branch-actions|branch-search|branch-new|branch-dirty|branch-delete: headless renders of the
/// branch widget, popup, sheet and notices (see Verification.swift). Needs a Git folder as the project.
enum BranchVerification {
    static func isBranchPicker(_ p: String?) -> Bool { p?.hasPrefix("branch") == true }

    /// Called ~0.4 s after launch; waits for the Git root to resolve, then drives the UI.
    static func start(_ picker: String, _ w: ProjectWindow) {
        if AppEnv.value("CE_BRANCH_TALL") != nil { BranchPopup.maxHeight = 1000 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            switch picker {
            case "branches", "branch-expanded":
                if let r = w.gitRoot { BranchFavorites.toggle("main", for: r) }
                w.showBranchPopup()
                if picker == "branch-expanded" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { BranchPopup.pressToggleAll(); BranchPopup.pressToggleAll() } }
            case "branch-actions":
                if let r = w.gitRoot { BranchFavorites.toggle("main", for: r) }
                w.showBranchPopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { BranchPopup.selectTitle(AppEnv.value("CE_BRANCH_ROW") ?? "login-form"); BranchPopup.pressRight() }
            case "branch-search":
                w.showBranchPopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { BranchPopup.type("log") }
            case "branch-new":
                w.branches.loadBranchList { _ in
                    w.branches.newBranch(from: nil)
                    NewBranchSheet.setName(AppEnv.value("CE_BRANCH_NAME") ?? "feature/login-form")
                }
            case "branch-keys":
                w.showBranchPopup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    func log(_ s: String) { fputs("keys: \(s)\n", stderr) }
                    BranchPopup.selectTitle("feature"); BranchPopup.pressLeft()
                    log("left on expanded folder collapses -> rows contain login-form: \(BranchPopup.shownTitles.contains("login-form"))")
                    BranchPopup.pressRight()
                    log("right on collapsed folder expands -> \(BranchPopup.shownTitles.contains("login-form"))")
                    BranchPopup.selectTitle("login-form"); BranchPopup.pressRight()
                    log("right on branch opens menu: \(BranchPopup.menuOpen) first=\(BranchPopup.menuTitles.first ?? "")")
                    BranchPopup.pressDown(); BranchPopup.pressDown()
                    for _ in 0..<9 { BranchPopup.pressDown() }
                    BranchPopup.pressRight()
                    log("right on submenu row opens child; escape closes only child: ")
                    BranchPopup.pressEscape()
                    log("menu still open after first escape: \(BranchPopup.menuOpen)")
                    BranchPopup.pressLeft()
                    log("left closes the menu: open=\(!BranchPopup.menuOpen) popup=\(BranchPopup.isShown)")
                    BranchPopup.pressEscape()
                    log("escape closes popup: \(!BranchPopup.isShown)")
                }
            case "branch-dirty": w.branches.checkout("bugfix/null-pointer")
            case "branch-delete":
                w.branches.loadBranchList { _ in
                    if let e = w.branches.lastList.local.first(where: { $0.name == "feature/login-form" }) { w.branches.run(.delete, entry: e) }
                }
            default: break
            }
        }
    }

    /// Writes `<shot>_widget_light.png`, `_widget_dark.png` and the picker-specific popup / sheet / notice render.
    static func finish(_ picker: String, shot: String, _ w: ProjectWindow) {
        func path(_ suffix: String) -> String { shot.replacingOccurrences(of: ".png", with: "_\(suffix).png") }
        w.branches.widget.snapshot(to: path("widget_light"), dark: false)
        w.branches.widget.snapshot(to: path("widget_dark"), dark: true)
        switch picker {
        case "branches", "branch-expanded", "branch-actions", "branch-search": BranchPopup.snapshot(to: path("popup"))
        case "branch-new": NewBranchSheet.snapshot(to: path("sheet"))
        default: if let v = BranchNotice.lastView { Verification.render(v, to: path("notice")) }
        }
        fputs("branch widget: \"\(w.branches.widget.branch)\" ahead \(w.branches.widget.ahead) behind \(w.branches.widget.behind) dirty \(w.branches.widget.dirty) visible \(w.branches.widgetVisible)\n", stderr)
        fputs("popup rows: \(BranchPopup.shownTitles.joined(separator: " | "))\n", stderr)
        fputs("notice: \(BranchNotice.lastTitle) \(BranchNotice.lastButtons)\n", stderr)
    }
}
