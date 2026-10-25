import AppKit

/// Headless checks for the native Python language service: grammar, imports (relative, package, venv site-packages),
/// go to definition for names / members / imports, hover with docstrings, find usages, completion. Snippets mark the pointer with `§`.
enum SelfTestNativePy {
    static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("py: " + name, ok()) }
    static func put(_ root: URL, _ rel: String, _ text: String) { SelfTestNativePHP.put(root, rel, text) }

    static func fixtureRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ce-py-\(getpid())")
    }

    static func buildFixture(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
        put(root, "pyproject.toml", "[project]\nname = \"demo\"\n")
        // a venv whose base interpreter lives in the fixture too (stdlib: os.py)
        put(root, ".venv/pyvenv.cfg", "home = \(root.path)/base/bin\nversion = 3.12.1\n")
        put(root, ".venv/lib/python3.12/site-packages/fancylib/__init__.py", "from .core import Engine\n__version__ = '1'\n")
        put(root, ".venv/lib/python3.12/site-packages/fancylib/core.py", """
        \"\"\"Core of fancylib.\"\"\"
        class Engine:
            \"\"\"A fancy engine.\"\"\"
            def run(self, fuel: int = 1) -> "Engine":
                \"\"\"Run the engine.

                Burns fuel.
                \"\"\"
                return self
        """)
        put(root, "base/lib/python3.12/os.py", "\"\"\"OS module.\"\"\"\nimport posixpath as path\nsep = '/'\ndef getcwd():\n    \"\"\"Return the cwd.\"\"\"\n    return ''\n")
        put(root, "base/lib/python3.12/typing.py", "Optional = object()\n")
        put(root, "base/lib/python3.12/dataclasses.py", "def dataclass(c): return c\n")
        put(root, "base/lib/python3.12/json.py", "def dumps(o): return ''\n")
        put(root, "base/lib/python3.12/posixpath.py", "def join(a, *p):\n    \"\"\"Join paths.\"\"\"\n    return a\n")
        put(root, "app/__init__.py", "from .models import User, Base\nfrom . import utils\n__all__ = ['User']\n")
        put(root, "app/models.py", """
        \"\"\"Models module docs.\"\"\"
        from dataclasses import dataclass
        from typing import Optional


        class Base:
            \"\"\"Base docs.

            More text.
            \"\"\"
            table: str = "base"

            def save(self) -> "Base":
                \"\"\"Persist the object.\"\"\"
                return self

            @property
            def label(self) -> str:
                return "x"


        class User(Base):
            name: str

            def __init__(self, name: str, age: int = 3):
                self.name = name
                self.profile = Profile(name)
                self._age = age

            def greet(self, other: "User") -> Optional["User"]:
                \"\"\"Say hi.\"\"\"
                return other

            @classmethod
            def make(cls, name):
                return cls(name)

            @staticmethod
            def helper(x):
                return x

            def save(self):
                super().save()
                return self


        class Profile:
            def __init__(self, bio):
                self.bio = bio

            def render(self):
                return self.bio
        """)
        put(root, "app/utils.py", """
        import os
        from .models import User as U

        CONST = 5


        def make_user(name):
            return U(name)


        def pick(flag: bool) -> U:
            ...
        """)
        put(root, "main.py", """
        import app.models
        from app import User, utils
        from app.models import Base as B
        import fancylib
        from fancylib.core import Engine

        u = User("a")
        x = utils.make_user("bob")
        e = Engine()
        """)
    }

    static func mark(_ s: String) -> (String, Int) {
        let r = (s as NSString).range(of: "§")
        precondition(r.location != NSNotFound)
        return (s.replacingOccurrences(of: "§", with: ""), r.location)
    }

    /// Lookup in `rel` (path inside the fixture) with the given snippet as live buffer text.
    static var lastLive: (path: String, text: String)?

    static func look(_ root: URL, _ rel: String, _ snippet: String) -> NPHit? {
        let (text, off) = mark(snippet)
        lastLive = (root.appendingPathComponent(rel).standardizedFileURL.path, text)
        let hit = NativePy.lookup(url: root.appendingPathComponent(rel), text: text as NSString, offset: off)
        if AppEnv.value("CE_PYDEBUG") != nil {
            let d = decl(root, hit)
            fputs("PYDEBUG \(snippet.replacingOccurrences(of: "\n", with: "\\n")) -> \(d.map { "\($0.name) \($0.rel):\($0.line)" } ?? "nil") kind=\(hit?.kind ?? "-")\n", stderr)
        }
        return hit
    }

    /// The identifier at the first target's offset, and the target file's relative path.
    static func decl(_ root: URL, _ hit: NPHit?) -> (name: String, rel: String, line: Int)? {
        guard let t = hit?.targets.first,
              let text = (lastLive?.path == t.path ? lastLive?.text : nil) ?? (try? String(contentsOfFile: t.path, encoding: .utf8)) else { return nil }
        let ns = text as NSString
        var end = t.offset
        while end < ns.length, PyRefs.isWord(ns.character(at: end)) { end += 1 }
        let rel = t.path.hasPrefix(root.path + "/") ? String(t.path.dropFirst(root.path.count + 1)) : t.path
        return (ns.substring(with: NSRange(location: t.offset, length: end - t.offset)), rel, t.line)
    }

    static func run() {
        let root = fixtureRoot()
        buildFixture(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = NativePy.project(for: root.appendingPathComponent("main.py"))
        project.queue.sync { project.resetEnv() }

        // grammar
        check("python grammar highlights", Languages.key(forFileName: "x.py") == "python" && Languages.grammar(forKey: "python")?.highlights != nil)
        check("py handles", NativePy.handles(URL(fileURLWithPath: "/a/b.py")) && !NativePy.handles(URL(fileURLWithPath: "/a/b.php")))

        // environment discovery
        let env = project.queue.sync { project.env }
        check("venv found", env.venv?.hasSuffix("/.venv") == true && env.site.contains { $0.hasSuffix("python3.12/site-packages") })
        check("stdlib via pyvenv.cfg home", env.stdlib.first?.hasSuffix("base/lib/python3.12") == true)

        // go to definition: same file
        var h = look(root, "main.py", "def f(a):\n    return a\nvalue = §f(1)\n")
        check("name -> def", decl(root, h)?.name == "f" && decl(root, h)?.line == 1)
        h = look(root, "main.py", "def f(a):\n    return §a\n")
        check("param usage -> param", decl(root, h)?.name == "a" && decl(root, h)?.line == 1)
        h = look(root, "main.py", "x = 1\nx = 2\nprint(§x)\n")
        check("variable -> preceding binding", decl(root, h)?.line == 2)
        h = look(root, "main.py", "class A:\n    def m(self):\n        return self.n()\n    def n(self): pass\nA().§m()\n")
        check("method on instance", decl(root, h)?.name == "m")
        h = look(root, "main.py", "class A:\n    def m(self):\n        return self.§n()\n    def n(self): pass\n")
        check("self.method", decl(root, h)?.name == "n" && decl(root, h)?.line == 4)

        // imports
        h = look(root, "main.py", "from app import §User\n")
        check("from package import re-export -> class in models", decl(root, h)?.name == "User" && decl(root, h)?.rel == "app/models.py")
        h = look(root, "main.py", "from app.models import §Base as B\n")
        check("from x import name as alias (name)", decl(root, h)?.name == "Base" && decl(root, h)?.rel == "app/models.py")
        h = look(root, "main.py", "from app.models import Base as §B\n")
        check("alias identifier -> definition", decl(root, h)?.name == "Base")
        h = look(root, "main.py", "import app.§models\n")
        check("import a.b component -> module file", h?.targets.first?.path.hasSuffix("app/models.py") == true && h?.kind == "module")
        h = look(root, "main.py", "import §app.models\n")
        check("import a.b first component -> package __init__", h?.targets.first?.path.hasSuffix("app/__init__.py") == true)
        h = look(root, "app/utils.py", "from .§models import User as U\n")
        check("relative module component", h?.targets.first?.path.hasSuffix("app/models.py") == true)
        h = look(root, "app/utils.py", "from .models import §User as U\n")
        check("relative import name", decl(root, h)?.name == "User" && decl(root, h)?.rel == "app/models.py")
        h = look(root, "app/utils.py", "from . import §models\n")
        check("from . import submodule", h?.kind == "module" && h?.targets.first?.path.hasSuffix("app/models.py") == true)
        h = look(root, "main.py", "from fancylib.core import §Engine\n")
        check("site-packages class", decl(root, h)?.name == "Engine" && decl(root, h)?.rel.hasSuffix("site-packages/fancylib/core.py") == true)
        h = look(root, "main.py", "from fancylib import §Engine\n")
        check("site-packages re-export", decl(root, h)?.name == "Engine")
        h = look(root, "main.py", "import os\nos.§getcwd()\n")
        check("stdlib function (venv base)", decl(root, h)?.name == "getcwd")
        h = look(root, "main.py", "import os\nos.path.§join('a')\n")
        check("os.path.join via import alias chain", decl(root, h)?.name == "join" && decl(root, h)?.rel.hasSuffix("posixpath.py") == true)

        // names through imports / types
        h = look(root, "main.py", "from app import User\nu = User('a')\nu.§greet(u)\n")
        check("member of imported class instance", decl(root, h)?.name == "greet" && decl(root, h)?.rel == "app/models.py")
        h = look(root, "main.py", "from app import User\nu = User('a')\nu.§save()\n")
        check("override resolves in subclass first", decl(root, h)?.name == "save" && decl(root, h)?.line == 42)
        h = look(root, "main.py", "from app import User\nu = User('a')\nu.§label\n")
        check("inherited property", decl(root, h)?.name == "label")
        h = look(root, "main.py", "from app import User\nu = User('a')\nu.§profile\n")
        check("instance attribute from __init__", decl(root, h)?.name == "profile")
        h = look(root, "main.py", "from app import User\nu = User('a')\nu.profile.§render()\n")
        check("attribute chain through ctor-assigned attribute", decl(root, h)?.name == "render")
        h = look(root, "main.py", "from app import User\nu = User.make('a')\nu.§greet(u)\n")
        check("classmethod returns cls(...)", decl(root, h)?.name == "greet")
        h = look(root, "main.py", "from app import utils\nutils.make_user('b').§greet(None)\n")
        check("inferred return type of function", decl(root, h)?.name == "greet")
        h = look(root, "main.py", "from app import utils\nutils.pick(True).§greet(None)\n")
        check("annotated return type through alias import", decl(root, h)?.name == "greet")
        h = look(root, "main.py", "from app import User\ndef f(p: User):\n    p.§name\n")
        check("annotated parameter", decl(root, h)?.name == "name")
        h = look(root, "main.py", "from app import User\ndef f(p: 'User | None'):\n    p.§name\n")
        check("string annotation with None is not guessed", h == nil || decl(root, h)?.name == "name")
        h = look(root, "main.py", "from typing import Optional\nfrom app import User\ndef f(p: Optional[User]):\n    p.§name\n")
        check("Optional[X] parameter", decl(root, h)?.name == "name")
        h = look(root, "main.py", "from app import User\ndef f(ps: list[User]):\n    for p in ps:\n        p.§name\n")
        check("for over list[X]", decl(root, h)?.name == "name")
        h = look(root, "main.py", "from fancylib import Engine\nEngine().run().§run()\n")
        check("method returning forward-ref class", decl(root, h)?.name == "run")
        h = look(root, "main.py", "from app.models import User\nUser(§name='a')\n")
        check("keyword argument -> __init__ param", decl(root, h)?.name == "name" && decl(root, h)?.line == 25)
        h = look(root, "main.py", "import fancylib\nfancylib.core.§Engine\n")
        check("submodule through package attribute", decl(root, h)?.name == "Engine")
        h = look(root, "main.py", "import unknownpkg\nunknownpkg.§thing\n")
        check("unresolved module member is silent", h == nil)
        h = look(root, "main.py", "print(§undefined_name_xyz)\n")
        check("unknown name is silent", h == nil)
        h = look(root, "main.py", "def f(x):\n    return x.§anything\n")
        check("untyped receiver is silent", h == nil)
        h = look(root, "main.py", "class A:\n    def __init__(self):\n        self.v = 1\n    def m(self):\n        return self.§v\n")
        check("self.attr assigned in __init__", decl(root, h)?.name == "v" && decl(root, h)?.line == 3)
        h = look(root, "main.py", "with open('f') as §fh:\n    pass\n")
        check("declaration returns itself", decl(root, h)?.name == "fh")
        h = look(root, "main.py", "try:\n    pass\nexcept ValueError as err:\n    print(§err)\n")
        check("except-as binding", decl(root, h)?.name == "err")
        h = look(root, "main.py", "sq = [§n for n in range(3)]\n")
        check("comprehension variable", decl(root, h)?.name == "n")
        h = look(root, "main.py", "class A:\n    x = 1\n    def m(self):\n        return §x\n")
        check("class scope is not visible from methods", h == nil)

        // hover
        h = look(root, "main.py", "from app.models import §User\n")
        check("hover class has signature", h?.markdown.contains("class User(Base)") == true)
        h = look(root, "main.py", "from app import User\nUser('a').§greet(None)\n")
        check("hover method shows docstring", h?.markdown.contains("Say hi.") == true && h?.markdown.contains("def greet(self, other: \"User\")") == true)
        h = look(root, "main.py", "from app.models import Base\n§Base\n")
        check("hover class docstring (cleandoc)", h?.markdown.contains("Base docs.\n\nMore text.") == true)
        h = look(root, "main.py", "import §fancylib\n")
        check("hover module", h?.markdown.contains("(module) fancylib") == true)
        h = look(root, "main.py", "import os\nos.§getcwd()\n")
        check("hover stdlib docstring", h?.markdown.contains("Return the cwd.") == true)
        h = look(root, "main.py", "from fancylib import Engine\nEngine().§run()\n")
        check("hover from site-packages with docstring", h?.markdown.contains("Burns fuel.") == true)
        h = look(root, "main.py", "from app import User\nu = User('a')\n§u\n")
        check("hover variable shows inferred type", h?.markdown.contains("(variable) u: User") == true)

        // find usages
        usageChecks(root, project)
        completionChecks(root, project)
        perfChecks(root, project)
    }
}
