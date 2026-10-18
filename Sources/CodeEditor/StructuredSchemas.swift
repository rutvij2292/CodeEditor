import Foundation

/// Small offline "schemas" for key / value completion, in a compact indented table format (see `SchemaTable.parse`):
///   `key = v1|v2|v3  # documentation`   (2-space indent = child; key `*` = any name; `@name` = shared value list;
///   `+kv` after the key = list items look like `KEY=value`).
enum StructuredSchemas {
    static let lists: [String: String] = [
        "@bool": "true|false",
        "@runners": "ubuntu-latest|ubuntu-24.04|ubuntu-22.04|ubuntu-20.04|windows-latest|windows-2022|windows-2019|macos-latest|macos-14|macos-13|macos-12|self-hosted",
        "@events": "push|pull_request|pull_request_target|workflow_dispatch|workflow_call|workflow_run|schedule|release|issues|issue_comment|create|delete|fork|watch|repository_dispatch|deployment|deployment_status|page_build|status|check_run|check_suite|discussion|discussion_comment|label|milestone|merge_group|public|registry_package|pull_request_review|pull_request_review_comment",
        "@actions": "actions/checkout@v4|actions/setup-node@v4|actions/setup-python@v5|actions/setup-java@v4|actions/setup-go@v5|actions/setup-dotnet@v4|actions/cache@v4|actions/upload-artifact@v4|actions/download-artifact@v4|actions/github-script@v7|actions/labeler@v5|actions/stale@v9|actions/configure-pages@v5|actions/deploy-pages@v4|actions/upload-pages-artifact@v3|actions/dependency-review-action@v4|shivammathur/setup-php@v2|ramsey/composer-install@v3|pnpm/action-setup@v4|oven-sh/setup-bun@v2|docker/setup-buildx-action@v3|docker/setup-qemu-action@v3|docker/login-action@v3|docker/build-push-action@v6|docker/metadata-action@v5|github/codeql-action/init@v3|github/codeql-action/analyze@v3|aws-actions/configure-aws-credentials@v4|codecov/codecov-action@v4|softprops/action-gh-release@v2|peaceiris/actions-gh-pages@v4|JamesIves/github-pages-deploy-action@v4|peter-evans/create-pull-request@v6|dorny/paths-filter@v3|appleboy/ssh-action@v1|webfactory/ssh-agent@v0.9.0|hashicorp/setup-terraform@v3|gradle/actions/setup-gradle@v4|ruby/setup-ruby@v1|dtolnay/rust-toolchain@stable|Swatinem/rust-cache@v2|cypress-io/github-action@v6|actions/create-github-app-token@v1",
        "@images": "mysql/mysql-server:8.0|mysql:8.0|mysql:8.4|mariadb:11|postgres:16|postgres:15|redis:alpine|redis:7|memcached:alpine|mongo:7|nginx:alpine|nginx:latest|node:20|node:22-alpine|php:8.3-fpm|php:8.3-cli|composer:2|getmeili/meilisearch:latest|typesense/typesense:0.25.2|minio/minio:latest|axllent/mailpit:latest|mailhog/mailhog|selenium/standalone-chromium|phpmyadmin:latest|adminer|rabbitmq:3-management|elasticsearch:8.13.0|opensearchproject/opensearch:2|traefik:v3.0|caddy:2|busybox|alpine:3.20|ubuntu:24.04|localstack/localstack|soketi/soketi:latest-16-alpine|mcr.microsoft.com/mssql/server:2022-latest",
    ]

    static let compose = """
    name # Project name
    version # Obsolete in Compose v2 (kept for old files)
    services # Containers that make up the application
      * # Service name
        image = @images # Image to start the container from
        build # Build configuration
          context # Build context path or URL
          dockerfile # Alternate Dockerfile
          args # Build arguments
          target # Multi-stage build target
          cache_from
          cache_to
          platforms
          ssh
          network = host|none|default
        container_name
        hostname
        domainname
        command
        entrypoint
        environment +kv # Environment variables
          APP_ENV
          APP_DEBUG = true|false
          APP_URL
          WWWUSER = ${WWWUSER}
          LARAVEL_SAIL = 1
          XDEBUG_MODE = ${SAIL_XDEBUG_MODE:-off}
          XDEBUG_CONFIG = client_host=host.docker.internal
          IGNITION_LOCAL_SITES_PATH = ${PWD}
          MYSQL_ROOT_PASSWORD = ${DB_PASSWORD}
          MYSQL_ROOT_HOST = %
          MYSQL_DATABASE = ${DB_DATABASE}
          MYSQL_USER = ${DB_USERNAME}
          MYSQL_PASSWORD = ${DB_PASSWORD}
          MYSQL_ALLOW_EMPTY_PASSWORD = 1
          POSTGRES_DB = ${DB_DATABASE}
          POSTGRES_USER = ${DB_USERNAME}
          POSTGRES_PASSWORD = ${DB_PASSWORD:-secret}
          MARIADB_ROOT_PASSWORD
          MEILI_NO_ANALYTICS = false
          MINIO_ROOT_USER = sail
          MINIO_ROOT_PASSWORD = password
          TZ = UTC
          PUID = 1000
          PGID = 1000
        env_file # Files with environment variables
        ports = 80:80|3306:3306|5432:5432|6379:6379|8080:80|'${APP_PORT:-80}:80'|'${VITE_PORT:-5173}:${VITE_PORT:-5173}'|'${FORWARD_DB_PORT:-3306}:3306'|'${FORWARD_REDIS_PORT:-6379}:6379'
        expose
        volumes = .:/var/www/html|./:/app|sail-mysql:/var/lib/mysql|sail-redis:/data|sail-pgsql:/var/lib/postgresql/data|/var/run/docker.sock:/var/run/docker.sock:ro|./nginx.conf:/etc/nginx/conf.d/default.conf:ro
        networks
        depends_on # Start order
          * # Service name
            condition = service_started|service_healthy|service_completed_successfully
            restart = true|false
            required = true|false
        restart = no|always|on-failure|unless-stopped
        healthcheck
          test = ["CMD", "curl", "-f", "http://localhost"]|["CMD-SHELL", "pg_isready"]|["CMD", "mysqladmin", "ping"]|["CMD", "redis-cli", "ping"]
          interval = 10s|30s|1m
          timeout = 5s|10s
          retries = 3|5
          start_period = 10s|30s
          disable = true|false
        labels
        working_dir
        user
        group_add
        extra_hosts = host.docker.internal:host-gateway
        dns
        privileged = true|false
        tty = true|false
        stdin_open = true|false
        init = true|false
        read_only = true|false
        cap_add = NET_ADMIN|SYS_ADMIN|SYS_PTRACE|NET_RAW
        cap_drop
        devices
        security_opt
        deploy
          replicas
          mode = replicated|global
          resources
            limits
              cpus
              memory
            reservations
              cpus
              memory
          restart_policy
            condition = none|on-failure|any
            delay
            max_attempts
            window
          update_config
          placement
        platform = linux/amd64|linux/arm64
        profiles
        logging
          driver = json-file|syslog|journald|none|local
          options
        pull_policy = always|never|missing|build|if_not_present
        stop_grace_period
        stop_signal = SIGTERM|SIGINT|SIGKILL
        tmpfs
        ulimits
        sysctls
        secrets
        configs
        links
        network_mode = host|bridge|none
        ipc = host|shareable
        pid = host
        mem_limit
        memswap_limit
        cpus
        shm_size
        scale
        extends
          file
          service
        develop
          watch
        runtime
        isolation
    networks
      * # Network name
        driver = bridge|host|overlay|macvlan|none
        driver_opts
        external = true|false
        name
        ipam
          driver
          config
        attachable = true|false
        internal = true|false
        enable_ipv6 = true|false
        labels
    volumes
      * # Volume name
        driver = local
        driver_opts
        external = true|false
        name
        labels
    configs
      *
        file
        external = true|false
        content
    secrets
      *
        file
        environment
        external = true|false
    include
    """

    static let workflow = """
    name # Workflow name shown in the Actions tab
    run-name # Name of each run
    on = @events # Events that trigger the workflow
      push
        branches
        branches-ignore
        tags
        tags-ignore
        paths
        paths-ignore
      pull_request
        types = opened|synchronize|reopened|closed|edited|ready_for_review|labeled|unlabeled|assigned|converted_to_draft|review_requested
        branches
        branches-ignore
        paths
        paths-ignore
      pull_request_target
        types
        branches
        paths
      workflow_dispatch
        inputs
          *
            description
            required = @bool
            default
            type = string|boolean|choice|number|environment
            options
      workflow_call
        inputs
          *
            description
            required = @bool
            default
            type = string|boolean|number
        secrets
          *
            description
            required = @bool
        outputs
          *
            description
            value
      workflow_run
        workflows
        types = completed|requested|in_progress
        branches
      schedule
        cron = '0 0 * * *'|'0 * * * *'|'30 5 * * 1-5'|'0 0 * * 0'|'*/15 * * * *'
      release
        types = published|created|released|prereleased|edited|deleted|unpublished
      issues
        types
      issue_comment
        types = created|edited|deleted
      repository_dispatch
        types
    permissions # GITHUB_TOKEN permissions
      actions = read|write|none
      checks = read|write|none
      contents = read|write|none
      deployments = read|write|none
      id-token = write|read|none
      issues = read|write|none
      discussions = read|write|none
      packages = read|write|none
      pages = read|write|none
      pull-requests = read|write|none
      repository-projects = read|write|none
      security-events = read|write|none
      statuses = read|write|none
    env
    defaults
      run
        shell = bash|pwsh|python|sh|cmd|powershell
        working-directory
    concurrency
      group = ${{ github.workflow }}-${{ github.ref }}
      cancel-in-progress = @bool
    jobs # Jobs of the workflow
      * # Job id
        name
        runs-on = @runners # Runner label
        needs
        if
        permissions
        environment
        outputs
        env
        defaults
        timeout-minutes = 10|15|30|60
        strategy
          matrix
            include
            exclude
            os = [ubuntu-latest, windows-latest, macos-latest]
            node-version = [18.x, 20.x, 22.x]
            php = [8.1, 8.2, 8.3]
            python-version = ['3.10', '3.11', '3.12']
          fail-fast = @bool
          max-parallel
        continue-on-error = @bool
        container
          image = @images
          env
          ports
          volumes
          options
          credentials
        services
          *
            image = @images
            env
            ports
            volumes
            options
            credentials
        concurrency
        uses # Reusable workflow
        with
        secrets = inherit
        steps # Steps of the job
          id
          if = always()|success()|failure()|cancelled()|github.event_name == 'push'|github.ref == 'refs/heads/main'
          name
          uses = @actions
          run
          shell = bash|pwsh|python|sh|cmd|powershell
          with
          env
          continue-on-error = @bool
          timeout-minutes
          working-directory
    """

    /// `with:` inputs of common actions, keyed by action name without @version.
    static let actionInputs: [String: String] = [
        "actions/checkout": "repository|ref|token|ssh-key|path|clean|fetch-depth|fetch-tags|lfs|submodules|persist-credentials|sparse-checkout",
        "actions/setup-node": "node-version|node-version-file|cache|cache-dependency-path|registry-url|scope|check-latest|always-auth|architecture",
        "actions/setup-python": "python-version|python-version-file|cache|cache-dependency-path|architecture|check-latest",
        "actions/setup-java": "java-version|distribution|java-package|cache|architecture|check-latest",
        "actions/setup-go": "go-version|go-version-file|cache|cache-dependency-path|check-latest",
        "actions/cache": "path|key|restore-keys|enableCrossOsArchive|fail-on-cache-miss|lookup-only",
        "actions/upload-artifact": "name|path|retention-days|if-no-files-found|compression-level|overwrite",
        "actions/download-artifact": "name|path|pattern|merge-multiple|run-id|github-token",
        "actions/github-script": "script|github-token|debug|result-encoding",
        "shivammathur/setup-php": "php-version|extensions|coverage|tools|ini-values|ini-file|php-version-file|fail-fast",
        "ramsey/composer-install": "composer-options|dependency-versions|working-directory|ignore-cache|custom-cache-key",
        "pnpm/action-setup": "version|run_install|package_json_file|dest",
        "docker/setup-buildx-action": "version|driver|install|use|platforms",
        "docker/login-action": "registry|username|password|logout|ecr",
        "docker/build-push-action": "context|file|push|tags|labels|platforms|build-args|cache-from|cache-to|target|load|secrets",
        "docker/metadata-action": "images|tags|flavor|labels",
        "aws-actions/configure-aws-credentials": "aws-region|role-to-assume|aws-access-key-id|aws-secret-access-key|role-session-name",
        "codecov/codecov-action": "token|files|flags|fail_ci_if_error|verbose|directory",
        "softprops/action-gh-release": "files|tag_name|name|body|draft|prerelease|generate_release_notes|token",
        "peaceiris/actions-gh-pages": "github_token|publish_dir|publish_branch|cname|force_orphan|keep_files",
        "JamesIves/github-pages-deploy-action": "folder|branch|token|clean|target-folder",
        "peter-evans/create-pull-request": "token|branch|title|body|commit-message|labels|base|delete-branch",
        "actions/upload-pages-artifact": "path|name|retention-days",
        "appleboy/ssh-action": "host|username|key|password|port|script|script_stop",
        "cypress-io/github-action": "build|start|wait-on|browser|record|working-directory",
        "actions/labeler": "repo-token|configuration-path|sync-labels",
        "actions/stale": "repo-token|days-before-stale|days-before-close|stale-issue-message|stale-pr-message",
        "hashicorp/setup-terraform": "terraform_version|cli_config_credentials_token|terraform_wrapper",
        "dorny/paths-filter": "filters|base|ref|token|list-files",
    ]

    static let packageJSON = """
    name # Package name
    version
    description
    keywords
    homepage
    bugs
      url
      email
    license = MIT|ISC|Apache-2.0|BSD-2-Clause|BSD-3-Clause|GPL-3.0-only|GPL-3.0-or-later|LGPL-3.0|MPL-2.0|Unlicense|UNLICENSED
    author
    contributors
    funding
    files
    type = module|commonjs
    main
    module
    browser
    types
    typings
    exports
    imports
    bin
    man
    directories
    repository
      type = git
      url
      directory
    scripts # npm scripts
      * # Script name
      dev = vite|next dev|nuxt dev|astro dev
      build = vite build|next build|tsc|nuxt build|astro build|vue-tsc && vite build
      start = node index.js|next start|vite preview|node server.js
      test = vitest|jest|vitest run|playwright test|node --test
      lint = eslint .|eslint . --fix|next lint
      preview = vite preview
      format = prettier --write .
      typecheck = tsc --noEmit|vue-tsc --noEmit
      prepare = husky
      postinstall
      prepublishOnly
      watch
      clean
      serve
      deploy
      e2e
      coverage
    config
    dependencies # Runtime dependencies
      *
    devDependencies # Development dependencies
      *
    peerDependencies
      *
    peerDependenciesMeta
    optionalDependencies
      *
    bundledDependencies
    overrides
    resolutions
    engines
      node = >=18|>=20|^18.0.0 || >=20.0.0
      npm
      pnpm
      yarn
    os
    cpu
    private = @bool
    publishConfig
      access = public|restricted
      registry
      tag
      provenance = @bool
    workspaces
    sideEffects = @bool
    packageManager = pnpm@9.0.0|npm@10.0.0|yarn@4.0.0|bun@1.1.0
    browserslist
    eslintConfig
    prettier
    jest
    husky
    lint-staged
    volta
      node
      npm
    """

    static let npmPackages = "vue|react|react-dom|axios|lodash|tailwindcss|vite|typescript|@vitejs/plugin-vue|@vitejs/plugin-react|laravel-vite-plugin|@inertiajs/vue3|@inertiajs/react|pinia|vue-router|vitest|jest|eslint|prettier|postcss|autoprefixer|sass|alpinejs|chart.js|dayjs|date-fns|zod|vue-tsc|@vue/test-utils|@types/node|@tailwindcss/forms|@tailwindcss/typography|next|nuxt|svelte|express|webpack|esbuild|rollup|husky|lint-staged|concurrently|cross-env|dotenv|@headlessui/vue|@heroicons/vue|@vueuse/core|laravel-echo|pusher-js|bootstrap|jquery"

    static let composerJSON = """
    name # vendor/package
    description
    type = library|project|metapackage|composer-plugin
    keywords
    homepage
    readme
    time
    license = MIT|proprietary|Apache-2.0|GPL-3.0-or-later|BSD-3-Clause|LGPL-3.0-or-later
    authors
      name
      email
      homepage
      role
    support
      email
      issues
      forum
      wiki
      irc
      source
      docs
      rss
      chat
      security
    funding
      type
      url
    require # Runtime dependencies
      php = ^8.2|^8.3|>=8.1
      laravel/framework = ^11.0|^12.0|^10.0
      laravel/sanctum
      laravel/tinker
      laravel/ui
      laravel/horizon
      laravel/octane
      laravel/socialite
      laravel/telescope
      livewire/livewire
      inertiajs/inertia-laravel
      guzzlehttp/guzzle
      spatie/laravel-permission
      spatie/laravel-medialibrary
      spatie/laravel-data
      barryvdh/laravel-dompdf
      maatwebsite/excel
      league/flysystem-aws-s3-v3
      predis/predis
      ext-json
      ext-mbstring
      ext-pdo
      ext-curl
      ext-intl
    require-dev
      phpunit/phpunit = ^11.0|^10.5
      pestphp/pest
      laravel/pint
      laravel/sail
      laravel/pail
      fakerphp/faker
      mockery/mockery
      nunomaduro/collision
      larastan/larastan
      barryvdh/laravel-debugbar
      barryvdh/laravel-ide-helper
      spatie/laravel-ignition
    conflict
    replace
    provide
    suggest
    autoload
      psr-4
      psr-0
      classmap
      files
      exclude-from-classmap
    autoload-dev
      psr-4
      files
    minimum-stability = stable|RC|beta|alpha|dev
    prefer-stable = @bool
    repositories
      type = composer|vcs|path|package|artifact
      url
      options
    config
      optimize-autoloader = @bool
      sort-packages = @bool
      preferred-install = dist|source|auto
      allow-plugins
      platform
      process-timeout
      vendor-dir
      bin-dir
      cache-dir
      discard-changes
      github-oauth
      secure-http = @bool
    scripts
      post-autoload-dump
      post-update-cmd
      post-install-cmd
      post-root-package-install
      post-create-project-cmd
      pre-install-cmd
      pre-update-cmd
      pre-autoload-dump
      test
      dev
    extra
      laravel
        dont-discover
        providers
        aliases
    bin
    archive
    abandoned
    non-feature-branches
    """

    static let tsconfig = """
    extends
    compilerOptions
      target = ES5|ES2015|ES2016|ES2017|ES2018|ES2019|ES2020|ES2021|ES2022|ES2023|ESNext
      module = CommonJS|ES2015|ES2020|ES2022|ESNext|Node16|NodeNext|Preserve|AMD|UMD|System
      moduleResolution = node|node10|bundler|node16|nodenext|classic
      moduleDetection = auto|legacy|force
      lib = ["ES2022", "DOM", "DOM.Iterable"]|["ESNext"]|["ES2020", "DOM"]
      jsx = preserve|react|react-jsx|react-jsxdev|react-native
      jsxImportSource
      strict = @bool
      noImplicitAny = @bool
      strictNullChecks = @bool
      strictFunctionTypes = @bool
      strictBindCallApply = @bool
      strictPropertyInitialization = @bool
      noImplicitThis = @bool
      useUnknownInCatchVariables = @bool
      alwaysStrict = @bool
      noUnusedLocals = @bool
      noUnusedParameters = @bool
      noImplicitReturns = @bool
      noFallthroughCasesInSwitch = @bool
      noUncheckedIndexedAccess = @bool
      exactOptionalPropertyTypes = @bool
      noImplicitOverride = @bool
      noPropertyAccessFromIndexSignature = @bool
      esModuleInterop = @bool
      allowSyntheticDefaultImports = @bool
      skipLibCheck = @bool
      forceConsistentCasingInFileNames = @bool
      resolveJsonModule = @bool
      isolatedModules = @bool
      verbatimModuleSyntax = @bool
      allowImportingTsExtensions = @bool
      allowJs = @bool
      checkJs = @bool
      maxNodeModuleJsDepth
      outDir
      outFile
      rootDir
      rootDirs
      baseUrl
      paths
      types
      typeRoots
      declaration = @bool
      declarationMap = @bool
      declarationDir
      emitDeclarationOnly = @bool
      sourceMap = @bool
      inlineSourceMap = @bool
      inlineSources = @bool
      noEmit = @bool
      noEmitOnError = @bool
      removeComments = @bool
      importHelpers = @bool
      downlevelIteration = @bool
      incremental = @bool
      composite = @bool
      tsBuildInfoFile
      experimentalDecorators = @bool
      emitDecoratorMetadata = @bool
      useDefineForClassFields = @bool
      preserveSymlinks = @bool
      pretty = @bool
      newLine = lf|crlf
      plugins
    include
    exclude
    files
    references
      path
    compileOnSave = @bool
    watchOptions
      watchFile
      watchDirectory
      fallbackPolling
    ts-node
    """

    static let eslintrc = """
    root = @bool
    env
      browser = @bool
      node = @bool
      es6 = @bool
      es2021 = @bool
      es2022 = @bool
      jest = @bool
      mocha = @bool
      commonjs = @bool
      worker = @bool
      serviceworker = @bool
      jquery = @bool
    extends = eslint:recommended|plugin:vue/vue3-recommended|plugin:vue/vue3-essential|plugin:@typescript-eslint/recommended|plugin:react/recommended|plugin:react-hooks/recommended|plugin:prettier/recommended|prettier|airbnb|airbnb-base|standard|next/core-web-vitals|plugin:import/recommended|plugin:jest/recommended
    parser = @typescript-eslint/parser|vue-eslint-parser|@babel/eslint-parser
    parserOptions
      ecmaVersion = latest|2022|2021|2020|2018|6
      sourceType = module|script|commonjs
      ecmaFeatures
        jsx = @bool
        globalReturn = @bool
      project
      parser
      extraFileExtensions
    plugins = vue|react|react-hooks|@typescript-eslint|import|jest|prettier|jsx-a11y|unicorn|promise
    rules
      * = off|warn|error|"off"|"warn"|"error"
      no-console
      no-debugger
      no-unused-vars
      no-undef
      no-var
      prefer-const
      eqeqeq
      curly
      semi
      quotes
      indent
      comma-dangle
      max-len
      no-multiple-empty-lines
      no-trailing-spaces
      object-curly-spacing
      arrow-parens
      no-empty
      no-shadow
      no-use-before-define
      no-param-reassign
      no-prototype-builtins
      require-await
      no-return-await
      vue/multi-word-component-names
      vue/no-v-html
      vue/require-default-prop
      vue/html-self-closing
      @typescript-eslint/no-explicit-any
      @typescript-eslint/no-unused-vars
      @typescript-eslint/explicit-function-return-type
      @typescript-eslint/no-non-null-assertion
      react/prop-types
      react/react-in-jsx-scope
      react-hooks/rules-of-hooks
      react-hooks/exhaustive-deps
      import/order
      import/no-unresolved
    overrides
      files
      excludedFiles
      rules
      extends
      parser
      env
      parserOptions
      plugins
    settings
    globals
    ignorePatterns
    noInlineConfig = @bool
    reportUnusedDisableDirectives = @bool
    """
}

/// Parsed schema table.
final class SchemaNode {
    let key: String
    var doc = ""
    var values: [String] = []
    var kv = false
    var children: [SchemaNode] = []
    var wildcard: SchemaNode? { children.first { $0.key == "*" } }
    var named: [SchemaNode] { children.filter { $0.key != "*" } }
    init(_ key: String) { self.key = key }

    func child(_ name: String) -> SchemaNode? { children.first { $0.key == name } ?? wildcard }
    func walk(_ path: [String]) -> SchemaNode? {
        var cur: SchemaNode? = self
        for p in path { cur = cur?.child(p); if cur == nil { return nil } }
        return cur
    }
}

enum SchemaTable {
    private static var cache: [String: SchemaNode] = [:]

    static func parse(_ text: String, id: String) -> SchemaNode {
        if let c = cache[id] { return c }
        let root = SchemaNode("")
        var stack: [(indent: Int, node: SchemaNode)] = [(-1, root)]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let indentSpaces = raw.prefix { $0 == " " }.count
            let body = raw.dropFirst(indentSpaces)
            guard !body.isEmpty else { continue }
            // "<key>[ +kv][ = values][ # doc]" ; values may contain '#'-free text only
            var rest = String(body)
            var doc = ""
            if let r = rest.range(of: " # ") { doc = String(rest[r.upperBound...]); rest = String(rest[..<r.lowerBound]) }
            else if rest.hasSuffix(" #") { rest = String(rest.dropLast(2)) }
            var values: [String] = []
            if let r = rest.range(of: " = ") {
                var v = String(rest[r.upperBound...])
                rest = String(rest[..<r.lowerBound])
                if let list = StructuredSchemas.lists[v] { v = list }
                values = v.split(separator: "|").map(String.init)
            }
            var kv = false
            if rest.hasSuffix(" +kv") { kv = true; rest = String(rest.dropLast(4)) }
            let node = SchemaNode(rest.trimmingCharacters(in: .whitespaces))
            node.doc = doc; node.values = values; node.kv = kv
            while let last = stack.last, last.indent >= indentSpaces { stack.removeLast() }
            stack.last?.node.children.append(node)
            stack.append((indentSpaces, node))
        }
        cache[id] = root
        return root
    }

    /// Schema for a file, or nil.
    static func forFile(_ url: URL) -> SchemaNode? {
        let name = url.lastPathComponent.lowercased()
        let path = url.standardizedFileURL.path
        let ext = url.pathExtension.lowercased()
        if [".eslintrc", ".eslintrc.json", ".eslintrc.yml", ".eslintrc.yaml"].contains(name) { return parse(StructuredSchemas.eslintrc, id: "eslintrc") }
        if ext == "yml" || ext == "yaml" {
            if name.hasPrefix("docker-compose") || name.hasPrefix("compose.") || name.hasPrefix("compose-") { return parse(StructuredSchemas.compose, id: "compose") }
            if path.contains("/.github/workflows/") { return parse(StructuredSchemas.workflow, id: "workflow") }
            return nil
        }
        if name == "package.json" { return parse(StructuredSchemas.packageJSON, id: "package") }
        if name == "composer.json" { return parse(StructuredSchemas.composerJSON, id: "composer") }
        if ext == "json", name.hasPrefix("tsconfig") || name.hasPrefix("jsconfig") { return parse(StructuredSchemas.tsconfig, id: "tsconfig") }
        return nil
    }
}
