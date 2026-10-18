import AppKit

/// An AI coding CLI that can be launched in its own terminal tab.
struct TerminalAgent: Equatable {
    var title: String       // tab title and menu label
    var command: String     // typed into the shell (so aliases and the login PATH apply)
    var builtIn = false
}

enum TerminalAgents {
    /// (binary looked up on PATH, entries offered when found)
    static let known: [(binary: String, entries: [TerminalAgent])] = [
        ("claude", [TerminalAgent(title: "Claude Code", command: "claude", builtIn: true),
                    TerminalAgent(title: "Claude Code: continue", command: "claude --continue", builtIn: true),
                    TerminalAgent(title: "Claude Code: resume", command: "claude --resume", builtIn: true)]),
        ("gemini", [TerminalAgent(title: "Gemini CLI", command: "gemini", builtIn: true)]),
        ("codex", [TerminalAgent(title: "Codex", command: "codex", builtIn: true)]),
        ("opencode", [TerminalAgent(title: "OpenCode", command: "opencode", builtIn: true)]),
        ("aider", [TerminalAgent(title: "Aider", command: "aider", builtIn: true)]),
    ]

    /// Known CLIs found on `path` (default: the resolved login-shell PATH).
    static func detected(path: String? = nil) -> [TerminalAgent] {
        known.flatMap { TerminalEnvironment.which($0.binary, path: path) != nil ? $0.entries : [] }
    }

    /// `Title|command` per line (blank lines and `#` comments skipped; a line without `|` uses the command as its title).
    static func parseCustom(_ text: String) -> [TerminalAgent] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if let bar = line.firstIndex(of: "|") {
                let title = line[..<bar].trimmingCharacters(in: .whitespaces)
                let command = line[line.index(after: bar)...].trimmingCharacters(in: .whitespaces)
                guard !command.isEmpty else { return nil }
                return TerminalAgent(title: title.isEmpty ? command : title, command: command)
            }
            return TerminalAgent(title: line, command: line)
        }
    }

    /// Detected CLIs, then `Prefs.terminalAgents`, then the legacy `terminal.agentCommand` slot. Duplicate commands are dropped.
    static func all(path: String? = nil, custom: String? = nil, legacy: String? = nil) -> [TerminalAgent] {
        var list = detected(path: path)
        var extra = parseCustom(custom ?? Prefs.terminalAgents)
        let old = (legacy ?? UserDefaults.standard.string(forKey: "terminal.agentCommand") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !old.isEmpty { extra.append(TerminalAgent(title: "AI agent: \(old)", command: old)) }
        for a in extra where !list.contains(where: { $0.command == a.command }) { list.append(a) }
        return list
    }

    // MARK: last used

    private static var memoryLast: String?
    /// Command of the agent started most recently (the "Agent" button's primary action).
    static var lastUsedCommand: String? {
        get { AppEnv.headless ? memoryLast : UserDefaults.standard.string(forKey: "terminal.lastAgent") }
        set { if AppEnv.headless { memoryLast = newValue } else { UserDefaults.standard.set(newValue, forKey: "terminal.lastAgent") } }
    }

    /// The agent the button launches: last used if still available, else the first available.
    static func primary(in agents: [TerminalAgent]) -> TerminalAgent? {
        if let c = lastUsedCommand, let a = agents.first(where: { $0.command == c }) { return a }
        return agents.first
    }
}
