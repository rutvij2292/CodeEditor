import AppKit
import CoreText

/// Registers the bundled JetBrains Mono faces (SIL OFL 1.1, see Fonts/OFL.txt) for this process only.
/// Inside an .app they live in Contents/Resources/Fonts; when running the SwiftPM debug binary they are read from the
/// repo's `Fonts/` directory, found by walking up from the executable (.build/<arch>/debug/CodeEditor).
enum FontRegistry {
    static let bundledFamily = "JetBrains Mono"
    private static var done = false
    /// Wall-clock cost of the one-time registration (for the report / diagnostics).
    private(set) static var registrationSeconds: Double = 0

    static func registerBundledFonts() {
        guard !done else { return }
        done = true
        let start = CFAbsoluteTimeGetCurrent()
        guard let dir = fontsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let urls = files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) } as CFArray
        CTFontManagerRegisterFontURLs(urls, .process, true) { _, _ in true }
        registrationSeconds = CFAbsoluteTimeGetCurrent() - start
    }

    static var isAvailable: Bool {
        registerBundledFonts()
        return NSFont(name: "JetBrainsMono-Regular", size: 13) != nil
    }

    private static func fontsDirectory() -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Fonts"), fm.fileExists(atPath: res.path) { return res }
        var url = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<7 {
            guard let u = url else { break }
            let candidate = u.appendingPathComponent("Fonts")
            if fm.fileExists(atPath: candidate.appendingPathComponent("JetBrainsMono-Regular.ttf").path) { return candidate }
            url = u.deletingLastPathComponent()
        }
        return nil
    }
}
