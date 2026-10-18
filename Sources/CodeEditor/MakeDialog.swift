import AppKit

/// "Artisan Make…" sheet: type (any make:* command), name, the common flags that type supports. Runs the command
/// off the main thread and hands back the files named in its "created successfully" output.
final class MakeDialog: NSObject {
    private static var current: MakeDialog?

    /// Flags worth a checkbox (only offered when the chosen command defines them as plain switches).
    static let commonFlags = ["--migration", "--controller", "--factory", "--seeder", "--resource", "--api", "--invokable", "--all", "--force", "--pest"]
    /// Frequently used types first, the rest alphabetically.
    private static let preferred = ["model", "controller", "migration", "request", "resource", "seeder", "factory", "middleware", "policy",
                                    "livewire", "job", "event", "listener", "mail", "notification", "command", "test", "component", "rule", "provider"]

    static func ordered(_ commands: [ArtisanCommand]) -> [ArtisanCommand] {
        func rank(_ c: ArtisanCommand) -> Int { preferred.firstIndex(of: String(c.name.dropFirst(5))) ?? preferred.count }
        return commands.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name < $1.name }
    }

    /// The switches offered for a command, in `commonFlags` order.
    static func flags(for c: ArtisanCommand) -> [ArtisanOption] {
        commonFlags.compactMap { f in c.options.first { $0.name == f && !$0.acceptsValue } }
    }

    /// Arguments for `php artisan`: `make:x Name --flag ... --no-interaction --no-ansi`.
    static func arguments(command: ArtisanCommand, name: String, flags: [String]) -> [String] {
        [command.name, name] + flags + ["--no-interaction", "--no-ansi"]
    }

    static func present(over window: NSWindow, commands: [ArtisanCommand], project: LaravelProject, completion: @escaping ([URL]) -> Void) {
        let d = MakeDialog(commands: ordered(commands), project: project, window: window, completion: completion)
        current = d
        d.show()
    }

    private let commands: [ArtisanCommand]
    private let project: LaravelProject
    private weak var window: NSWindow?
    private let completion: ([URL]) -> Void
    private let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField()
    private var boxes: [NSButton] = []
    private let alert = NSAlert()
    private static let slots = 10

    private init(commands: [ArtisanCommand], project: LaravelProject, window: NSWindow, completion: @escaping ([URL]) -> Void) {
        self.commands = commands
        self.project = project
        self.window = window
        self.completion = completion
    }

    private func show() {
        guard let window else { return }
        alert.messageText = "Artisan Make"
        alert.informativeText = "Create a class with php artisan make:*"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let width: CGFloat = 400, rows = (Self.slots + 1) / 2
        let height: CGFloat = 30 + 30 + CGFloat(rows) * 22 + 4
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        typePopup.frame = NSRect(x: 0, y: 0, width: width, height: 26)
        for c in commands { typePopup.addItem(withTitle: String(c.name.dropFirst(5))); typePopup.lastItem?.toolTip = c.summary }
        typePopup.target = self
        typePopup.action = #selector(typeChanged)
        nameField.frame = NSRect(x: 0, y: 32, width: width, height: 24)
        nameField.placeholderString = "Name (e.g. Post or Admin/PostController)"
        view.addSubview(typePopup)
        view.addSubview(nameField)
        for i in 0..<Self.slots {
            let b = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            b.frame = NSRect(x: CGFloat(i % 2) * (width / 2), y: 66 + CGFloat(i / 2) * 22, width: width / 2, height: 20)
            b.font = .systemFont(ofSize: 12)
            boxes.append(b)
            view.addSubview(b)
        }
        alert.accessoryView = view
        typeChanged()
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn { self.run() }
            MakeDialog.current = nil
        }
        alert.window.initialFirstResponder = nameField
        alert.window.makeFirstResponder(nameField)
    }

    private var selected: ArtisanCommand { commands[max(0, typePopup.indexOfSelectedItem)] }

    @objc private func typeChanged() {
        let flags = Self.flags(for: selected)
        for (i, b) in boxes.enumerated() {
            if i < flags.count {
                b.isHidden = false
                b.state = .off
                b.title = (flags[i].shortcut.isEmpty ? "" : flags[i].shortcut + "  ") + flags[i].name
                b.toolTip = flags[i].detail
                b.identifier = NSUserInterfaceItemIdentifier(flags[i].name)
            } else {
                b.isHidden = true
                b.identifier = nil
            }
        }
    }

    private func run() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { fail("Enter a name."); return }
        let flags = boxes.filter { !$0.isHidden && $0.state == .on }.compactMap { $0.identifier?.rawValue }
        let args = Self.arguments(command: selected, name: name, flags: flags)
        guard let php = Artisan.findPHP() else { fail(ArtisanError.noPHP.message); return }
        let project = self.project
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let out = Artisan.execute(php: php, arguments: ["artisan"] + args, cwd: project.root)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let out else { self.fail("Could not start php."); return }
                if out.timedOut { self.fail("php artisan timed out."); return }
                let text = out.stdout + "\n" + out.stderr
                let files = Artisan.parseCreated(text, root: project.root)
                if out.status != 0 || files.isEmpty {
                    let shown = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.fail(shown.isEmpty ? "php artisan exited with status \(out.status)." : String(shown.prefix(600)))
                    return
                }
                self.completion(files)
            }
        }
    }

    private func fail(_ message: String) {
        let a = NSAlert()
        a.messageText = "make failed"
        a.informativeText = message
        a.alertStyle = .warning
        if let window { a.beginSheetModal(for: window) { _ in } } else { a.runModal() }
    }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }
