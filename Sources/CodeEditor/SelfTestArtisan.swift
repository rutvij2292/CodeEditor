import AppKit

/// Headless checks for the Artisan palette / route browser / make dialog logic, using a fake `php` script.
enum SelfTestArtisan {
    private static let listJSON = #"""
    {"application":{"name":"Laravel Framework","version":"11.0.0"},"commands":[
    {"name":"migrate","description":"Run the database migrations","hidden":false,"usage":["migrate [options]"],"definition":{"arguments":{},"options":{
      "--seed":{"name":"--seed","shortcut":"","accept_value":false,"description":"Seed"},
      "--help":{"name":"--help","shortcut":"-h","accept_value":false,"description":"Display help"}}}},
    {"name":"make:model","description":"Create a new Eloquent model class","hidden":false,"usage":["make:model [options] [--] <name>"],"definition":{"arguments":{
      "name":{"name":"name","is_required":true,"is_array":false,"description":"The name"}},"options":{
      "--migration":{"name":"--migration","shortcut":"-m","accept_value":false,"description":"Create a migration"},
      "--force":{"name":"--force","shortcut":"","accept_value":false,"description":"Overwrite"},
      "--pivot":{"name":"--pivot","shortcut":"-p","accept_value":false,"description":"Pivot"},
      "--connection":{"name":"--connection","shortcut":"","accept_value":true,"description":"db"}}}},
    {"name":"make:controller","description":"Create a new controller class","hidden":false,"usage":["make:controller [options] [--] <name>"],"definition":{"arguments":{
      "name":{"name":"name","is_required":true,"is_array":false,"description":"The name"}},"options":{
      "--resource":{"name":"--resource","shortcut":"-r","accept_value":false,"description":"Resource"},
      "--api":{"name":"--api","shortcut":"","accept_value":false,"description":"API"}}}},
    {"name":"user:grant","description":"Grant a role","hidden":false,"usage":["user:grant <email> <role>"],"definition":{"arguments":{
      "role":{"name":"role","is_required":true,"is_array":false,"description":"r"},
      "email":{"name":"email","is_required":true,"is_array":false,"description":"e"}},"options":{}}},
    {"name":"help","description":"Display help","definition":{"arguments":{},"options":{}}},
    {"name":"secret","description":"Hidden one","hidden":true,"definition":{"arguments":{},"options":{}}}]}
    """#

    private static let routesJSON = #"""
    [{"domain":null,"method":"GET|HEAD","uri":"users/{user}","name":"users.show","action":"App\\Http\\Controllers\\UserController@show","middleware":["web"]},
     {"domain":null,"method":"GET|HEAD","uri":"/","name":null,"action":"Closure","middleware":["web"]},
     {"domain":null,"method":"POST","uri":"api/login","name":"login","action":"App\\Http\\Controllers\\LoginController","middleware":["api"]}]
    """#

    static func run(done: @escaping () -> Void) {
        let check = SelfTest.check
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-artisan-\(getpid())")
        func write(_ rel: String, _ text: String) {
            let u = dir.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        

        // Pure parsing.
        let cmds = Artisan.parseCommands(Data(("Deprecated: noise\n" + listJSON + "\nmore noise").utf8)) ?? []
        check("artisan list: parses through PHP warnings, drops help/hidden", cmds.map(\.name) == ["make:controller", "make:model", "migrate", "user:grant"])
        let model = cmds.first { $0.name == "make:model" }
        check("artisan list: description, required arg, shortcut", model?.summary == "Create a new Eloquent model class"
              && model?.requiredArguments.map(\.name) == ["name"] && model?.options.first { $0.name == "--migration" }?.shortcut == "-m")
        check("artisan list: global options removed", cmds.first { $0.name == "migrate" }?.options.map(\.name) == ["--seed"])
        check("artisan list: argument order recovered from usage", cmds.first { $0.name == "user:grant" }?.arguments.map(\.name) == ["email", "role"]
              && cmds.first { $0.name == "user:grant" }?.argumentHint == "<email> <role>")
        check("artisan list: garbage returns nil", Artisan.parseCommands(Data("not json".utf8)) == nil)

        let routes = Artisan.parseRoutes(Data(routesJSON.utf8)) ?? []
        check("route list: parses 3 routes", routes.count == 3)
        check("route list: method/uri/name/action", routes.first == ArtisanRoute(method: "GET|HEAD", uri: "/users/{user}", name: "users.show",
              action: "App\\Http\\Controllers\\UserController@show") && routes[0].displayMethod == "GET" && routes[1].name.isEmpty && routes[2].displayMethod == "POST")
        check("route rows: title/detail", RouteBrowser.items(routes) { _ in }.first.map { $0.title == "GET  /users/{user}   users.show" && $0.detail == "UserController@show" } == true)

        let created = Artisan.parseCreated("""

           \u{1B}[30;44m INFO \u{1B}[39;49m Model [/proj/app/Models/Post.php] created successfully.
           INFO  Migration [database/migrations/2024_01_01_000000_create_posts_table.php] created successfully.
           INFO  Model [/proj/app/Models/Post.php] created successfully.
        """, root: URL(fileURLWithPath: "/proj"))
        check("make output: absolute + relative paths, ANSI stripped, deduped",
              created.map(\.path) == ["/proj/app/Models/Post.php", "/proj/database/migrations/2024_01_01_000000_create_posts_table.php"])
        check("make output: no match", Artisan.parseCreated("ERROR  Model already exists.", root: dir).isEmpty)

        // Dialog / palette helpers.
        check("make dialog: flags offered are the supported plain switches", model.map { MakeDialog.flags(for: $0).map(\.name) } == ["--migration", "--force"])
        check("make dialog: types ordered with model first", MakeDialog.ordered(cmds.filter { $0.name.hasPrefix("make:") }).map(\.name) == ["make:model", "make:controller"])
        if let model {
            check("make dialog: artisan arguments", MakeDialog.arguments(command: model, name: "Post", flags: ["--migration"])
                  == ["make:model", "Post", "--migration", "--no-interaction", "--no-ansi"])
        }
        check("inline invocation: command + args", ArtisanPalette.inlineInvocation("migrate --seed", in: cmds).map { $0.0.name == "migrate" && $0.1 == "--seed" } == true
              && ArtisanPalette.inlineInvocation("migr --seed", in: cmds) == nil && ArtisanPalette.inlineInvocation("migrate", in: cmds) == nil)
        if let grant = cmds.first(where: { $0.name == "user:grant" }) {
            check("missing arguments", ArtisanPalette.missingArguments(grant, typed: "").count == 2
                  && ArtisanPalette.missingArguments(grant, typed: "'a b' --x").map(\.name) == ["role"]
                  && ArtisanPalette.missingArguments(grant, typed: "a admin").isEmpty)
        }
        let items = ArtisanPalette.commandItems(cmds) { _ in }
        check("palette filter: fuzzy on name", ArtisanPalette.filter(items, query: "mkmod").first?.title == "make:model"
              && ArtisanPalette.filter(items, query: "zzzqq").isEmpty && ArtisanPalette.filter(items, query: "").count == items.count)
        check("palette filter: matches the description", ArtisanPalette.filter(items, query: "eloquent").first?.title == "make:model")
        check("command line: plain and quoted", Artisan.commandLine(php: "/nonpath/bin/php", command: "migrate", args: " --seed ", cdTo: "/a b")
              == "cd '/a b' && '/nonpath/bin/php' artisan migrate --seed")

        // Fixture project + fake php.
        write("artisan", "<?php\n")
        write("composer.json", #"{"require":{"laravel/framework":"^11"},"autoload":{"psr-4":{"App\\":"app/"}}}"#)
        write("routes/web.php", "<?php\nRoute::get('/users/{user}', [UserController::class, 'show']);\nRoute::get('/', function () { return 1; });\n")
        write("app/Http/Controllers/UserController.php", "<?php\nnamespace App\\Http\\Controllers;\nclass UserController {\n    public function index() {}\n    public function show() {}\n}\n")
        write("app/Http/Controllers/LoginController.php", "<?php\nnamespace App\\Http\\Controllers;\nclass LoginController {\n    public function __invoke() {}\n}\n")
        let log = dir.appendingPathComponent("php.log").path
        write("bin/php", """
        #!/bin/sh
        echo "$2" >> '\(log)'
        case "$2" in
        list) echo 'PHP Deprecated: something'; cat <<'EOF'
        \(listJSON)
        EOF
        ;;
        route:list) cat <<'EOF'
        \(routesJSON)
        EOF
        ;;
        make:model) mkdir -p app/Models; echo '<?php' > app/Models/Post.php; echo "   INFO  Model [$PWD/app/Models/Post.php] created successfully." ;;
        *) echo "unknown" >&2; exit 3 ;;
        esac
        """)
        let php = dir.appendingPathComponent("bin/php").path
        chmod(php, 0o755)
        Artisan.phpOverride = php
        check("php detection honours the override", Artisan.findPHP() == php)

        let p = LaravelProject(root: dir)
        func calls() -> Int { ((try? String(contentsOfFile: log)) ?? "").split(separator: "\n").count }
        let direct = ArtisanCatalog.fetch(p, args: ["list", "--format=json"], parse: Artisan.parseCommands)
        check("fake php: list fetched and parsed", (try? direct.get().count) == 4)
        let bad = ArtisanCatalog.fetch(p, args: ["nope"], parse: Artisan.parseCommands)
        check("fake php: failure surfaces stderr", { if case .failure(.failed(let m)) = bad { return m.contains("unknown") }; return false }())
        let notLaravel = ArtisanCatalog.fetch(LaravelProject(root: dir.appendingPathComponent("bin")), args: ["list"], parse: Artisan.parseCommands)
        check("not a laravel project degrades", { if case .failure(.notLaravel) = notLaravel { return true }; return false }())
        Artisan.phpOverride = dir.appendingPathComponent("missing").path
        let noPHPOverride = Artisan.findPHP() != Artisan.phpOverride
        Artisan.phpOverride = php
        check("php override that does not exist is ignored", noPHPOverride)

        // Async path + cache + invalidation. The callbacks hop to the main queue, so poll with asyncAfter (the harness
        // itself occupies the main queue while it runs, hence the continuation style).
        func expect<T>(_ start: (@escaping (T) -> Void) -> Void, then: @escaping (T?) -> Void) {
            var got: T?
            start { got = $0 }
            let end = Date().addingTimeInterval(20)
            func poll() {
                if got != nil || Date() > end { then(got) } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll() } }
            }
            poll()
        }
        let before = calls()
        expect({ done in ArtisanCatalog.shared.commands(p) { done($0) } }) { first in
            let afterFirst = calls()
            expect({ done in ArtisanCatalog.shared.commands(p) { done($0) } }) { second in
                check("catalog: async load runs php once, second call is cached", (try? first?.get().count) == 4 && (try? second?.get().count) == 4
                      && afterFirst == before + 1 && calls() == afterFirst)
                write("routes/web.php", "<?php\n// changed\nRoute::get('/users/{user}', [UserController::class, 'show']);\nRoute::get('/', function () { return 1; });\n")
                expect({ done in ArtisanCatalog.shared.commands(p) { done($0) } }) { _ in
                    check("catalog: touching routes/ invalidates the cache", calls() == afterFirst + 1)
                    expect({ done in ArtisanCatalog.shared.routes(p) { done($0) } }) { rs in
                        check("catalog: routes load", (try? rs?.get().count) == 3)
                        routeTargets(rs.flatMap { try? $0.get() })
                        makeCheck()
                        try? fm.removeItem(at: dir); Artisan.phpOverride = nil
                        done()
                    }
                }
            }
        }

        func routeTargets(_ rs: [ArtisanRoute]?) {
        if let rs {
            let show = RouteBrowser.target(for: rs[0], in: p)
            check("route target: controller method line", show?.url.lastPathComponent == "UserController.php" && show?.line == 5)
            check("route target: invokable controller", RouteBrowser.target(for: rs[2], in: p)?.line == 4)
            let closure = RouteBrowser.target(for: rs[1], in: p)
            check("route target: closure route falls back to the routes file", closure?.url.lastPathComponent == "web.php" && closure?.line == 4)
        } else { check("route target: routes available", false) }
        }

        func makeCheck() {
        // make:model through the same runner the dialog uses, then output -> files.
        if let model, let out = Artisan.execute(php: php, arguments: ["artisan"] + MakeDialog.arguments(command: model, name: "Post", flags: []), cwd: dir) {
            let files = Artisan.parseCreated(out.stdout, root: dir)
            check("make: output names a file that exists", files.count == 1 && fm.fileExists(atPath: files[0].path) && files[0].lastPathComponent == "Post.php")
        } else { check("make: ran", false) }
        }
    }
}
