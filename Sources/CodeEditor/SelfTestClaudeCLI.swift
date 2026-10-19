import AppKit

/// CE_SELFTEST: the Claude Code CLI runner (fake `claude` script), prompt building and the Ask Claude panel. Never calls the real CLI.
enum SelfTestClaudeCLI {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run(w: ProjectWindow, then done: @escaping () -> Void) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-claudecli-\(getpid())")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let fake = dir.appendingPathComponent("claude")
        let argsFile = dir.appendingPathComponent("args"), stdinFile = dir.appendingPathComponent("stdin"), envFile = dir.appendingPathComponent("env")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argsFile.path)'
        cat > '\(stdinFile.path)'
        printf '%s' "${ANTHROPIC_API_KEY:-unset}" > '\(envFile.path)'
        if [ -n "$FAKE_CLAUDE_FAIL" ]; then echo "login required" >&2; exit 1; fi
        printf '```\\nfix: handle empty cart\\n```\\n'
        """
        try? script.write(to: fake, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        setenv("CE_CLAUDE_BIN", fake.path, 1)
        setenv("ANTHROPIC_API_KEY", "sk-test-should-not-leak", 1)

        check("claude cli: fake binary is found", ClaudeCLI.executable() == fake.path)
        check("claude cli: fenced message is cleaned", ClaudeCLI.cleanCommitMessage("```\nfix: x\n\nbody\n```") == "fix: x\n\nbody")
        check("claude cli: quoted message is cleaned", ClaudeCLI.cleanCommitMessage("\"fix: x\"") == "fix: x")
        let prompt = ClaudeCLI.commitPrompt(branch: "main", recentSubjects: ["Add cart"], stat: " a.php | 2 +-", diff: "+x")
        check("claude cli: commit prompt carries branch, style and diff", prompt.contains("Branch: main") && prompt.contains("- Add cart") && prompt.contains("+x"))
        let chat = ClaudeCLI.chatPrompt(path: "a.php", startLine: 3, endLine: 4, code: "echo 1;", turns: [.init(question: "why?", answer: "because"), .init(question: "and?", answer: nil)])
        check("claude cli: chat prompt carries code and earlier turns", chat.contains("echo 1;") && chat.contains("Assistant: because") && chat.contains("User: and?"))

        _ = ClaudeCLI.run(prompt: "hello prompt") { result in
            var text = ""
            if case .success(let t) = result { text = t }
            check("claude cli: success returns stdout", text.contains("fix: handle empty cart"))
            let args = (try? String(contentsOf: argsFile)) ?? ""
            check("claude cli: runs print mode with no tools and no session files",
                  args.contains("-p") && args.contains("--no-session-persistence") && args.contains("--tools") && args.contains("--model"))
            check("claude cli: prompt arrives on stdin", ((try? String(contentsOf: stdinFile)) ?? "") == "hello prompt")
            check("claude cli: API key is stripped so billing stays on the subscription", ((try? String(contentsOf: envFile)) ?? "") == "unset")

            setenv("FAKE_CLAUDE_FAIL", "1", 1)
            _ = ClaudeCLI.run(prompt: "x") { result in
                var msg = ""
                if case .failure(let f) = result { msg = f.message }
                check("claude cli: failure surfaces stderr", msg.contains("login required"))
                unsetenv("FAKE_CLAUDE_FAIL")

                let ctx = ClaudeAskPanel.Context(path: "app/Cart.php", startLine: 3, endLine: 9, code: "echo 1;\necho 2;")
                var pasted = ""
                ClaudeAskPanel.present(over: w.window, context: ctx, cwd: nil) { pasted = $0 }
                ClaudeAskPanel.dismiss()
                check("claude ask panel: opens and closes headlessly", pasted.isEmpty)

                unsetenv("CE_CLAUDE_BIN")
                unsetenv("ANTHROPIC_API_KEY")
                try? fm.removeItem(at: dir)
                done()
            }
        }
    }
}
