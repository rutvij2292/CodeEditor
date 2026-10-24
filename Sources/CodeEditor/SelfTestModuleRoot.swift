import Foundation

/// Modular Laravel (nwidart): every module has its own composer.json, but the project root is the application above it.
enum SelfTestModuleRoot {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }
    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-modroot-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        func put(_ rel: String, _ text: String) {
            let u = root.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        put("composer.json", "{\"autoload\":{\"psr-4\":{\"App\\\\\":\"app/\",\"Modules\\\\\":\"Modules/\"}}}")
        put("artisan", "#!/usr/bin/env php\n")
        put("app/Helper/DataTable/TableBuilder.php", "<?php\nnamespace App\\Helper\\DataTable;\nclass TableBuilder {}\n")
        put("Modules/Users/composer.json", "{\"autoload\":{\"psr-4\":{\"Modules\\\\Users\\\\\":\"\",\"Modules\\\\Users\\\\App\\\\\":\"app/\"}}}")
        put("Modules/Users/app/Services/UserService.php", "<?php\nnamespace Modules\\Users\\app\\Services;\nclass UserService {}\n")
        let code = "<?php\n\nnamespace Modules\\Users\\app\\Http\\Controllers;\n\nuse App\\Helper\\DataTable\\TableBuilder;\nuse App\\Helper\\DataTable\\Missing;\nuse Modules\\Users\\app\\Services\\UserService;\n\nclass UsersController\n{\n    public function index() { return [new TableBuilder, new UserService, Missing::class]; }\n}\n"
        put("Modules/Users/app/Http/Controllers/UsersController.php", code)
        let file = root.appendingPathComponent("Modules/Users/app/Http/Controllers/UsersController.php")

        check("module root: a module's composer.json does not become the project root", FastTier.root(for: file) == root.path)
        let plain = fm.temporaryDirectory.appendingPathComponent("ce-modroot2-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: plain)
        defer { try? fm.removeItem(at: plain) }
        try? fm.createDirectory(at: plain.appendingPathComponent("sub/src"), withIntermediateDirectories: true)
        try? "{}".write(to: plain.appendingPathComponent("sub/composer.json"), atomically: true, encoding: .utf8)
        check("module root: without artisan / vendor the nearest composer.json still wins", FastTier.root(for: plain.appendingPathComponent("sub/src/A.php")) == plain.appendingPathComponent("sub").path)

        guard let r = FastTier.root(for: file) else { check("module root: project found", false); return }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        let list = fp.queue.sync { NativePHPDiag.analyze(url: file, text: code as NSString, fp: fp) }
        let undefined = list.filter { $0.code == "undefined-class" }.map(\.message)
        check("module root: existing App\\ imports are not reported (only the missing class is)", undefined == ["Undefined class 'App\\Helper\\DataTable\\Missing'"])
    }
}
