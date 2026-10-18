import Foundation

/// Compact curated completion data. Stored as plain strings and parsed per request (never kept as big dictionaries).
enum CompletionData {
    static func words(_ s: String) -> [String] { s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init) }

    // MARK: PHP

    static let phpKeywords = words("""
    abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty \
    enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if \
    implements include include_once instanceof insteadof interface isset list match namespace new or print private protected \
    public readonly require require_once return static switch throw trait try unset use var while xor yield exit die
    """)
    static let phpMagic = words("__CLASS__ __DIR__ __FILE__ __FUNCTION__ __LINE__ __METHOD__ __NAMESPACE__ __TRAIT__ __construct __destruct __get __set __call __callStatic __toString __invoke __isset __unset __clone __sleep __wakeup")
    static let phpTypes = words("int float string bool array object mixed void null never iterable callable self static parent true false")
    static let phpSuperglobals = words("$_GET $_POST $_SERVER $_SESSION $_COOKIE $_FILES $_ENV $_REQUEST $GLOBALS")

    /// "name(signature): return" per line.
    static let phpFunctions = """
    strlen(string $string): int
    str_contains(string $haystack, string $needle): bool
    str_starts_with(string $haystack, string $needle): bool
    str_ends_with(string $haystack, string $needle): bool
    strpos(string $haystack, string $needle, int $offset = 0): int|false
    stripos(string $haystack, string $needle, int $offset = 0): int|false
    strrpos(string $haystack, string $needle, int $offset = 0): int|false
    substr(string $string, int $offset, ?int $length = null): string
    substr_count(string $haystack, string $needle): int
    substr_replace(array|string $string, array|string $replace, array|int $offset, array|int|null $length = null): array|string
    str_replace(array|string $search, array|string $replace, array|string $subject, int &$count = null): array|string
    str_ireplace(array|string $search, array|string $replace, array|string $subject): array|string
    str_repeat(string $string, int $times): string
    str_pad(string $string, int $length, string $pad_string = " ", int $pad_type = STR_PAD_RIGHT): string
    str_split(string $string, int $length = 1): array
    str_word_count(string $string): int
    strtolower(string $string): string
    strtoupper(string $string): string
    ucfirst(string $string): string
    ucwords(string $string, string $separators = " \\t\\r\\n\\f\\v"): string
    lcfirst(string $string): string
    trim(string $string, string $characters = " \\n\\r\\t\\v\\0"): string
    ltrim(string $string, string $characters = " \\n\\r\\t\\v\\0"): string
    rtrim(string $string, string $characters = " \\n\\r\\t\\v\\0"): string
    explode(string $separator, string $string, int $limit = PHP_INT_MAX): array
    implode(string $separator, ?array $array): string
    join(string $separator, ?array $array): string
    sprintf(string $format, mixed ...$values): string
    printf(string $format, mixed ...$values): int
    number_format(float $num, int $decimals = 0, ?string $decimal_separator = ".", ?string $thousands_separator = ","): string
    nl2br(string $string): string
    htmlspecialchars(string $string, int $flags = ENT_QUOTES, ?string $encoding = null): string
    html_entity_decode(string $string): string
    htmlentities(string $string): string
    strip_tags(string $string, array|string|null $allowed_tags = null): string
    addslashes(string $string): string
    stripslashes(string $string): string
    strcmp(string $string1, string $string2): int
    strcasecmp(string $string1, string $string2): int
    strncmp(string $string1, string $string2, int $length): int
    strrev(string $string): string
    strstr(string $haystack, string $needle, bool $before_needle = false): string|false
    strrchr(string $haystack, string $needle): string|false
    wordwrap(string $string, int $width = 75, string $break = "\\n", bool $cut_long_words = false): string
    md5(string $string, bool $binary = false): string
    sha1(string $string, bool $binary = false): string
    hash(string $algo, string $data, bool $binary = false): string
    crc32(string $string): int
    base64_encode(string $string): string
    base64_decode(string $string, bool $strict = false): string|false
    bin2hex(string $string): string
    hex2bin(string $string): string|false
    urlencode(string $string): string
    urldecode(string $string): string
    rawurlencode(string $string): string
    http_build_query(array|object $data): string
    parse_str(string $string, array &$result): void
    parse_url(string $url, int $component = -1): array|string|int|false|null
    uniqid(string $prefix = "", bool $more_entropy = false): string
    mb_strlen(string $string, ?string $encoding = null): int
    mb_substr(string $string, int $start, ?int $length = null, ?string $encoding = null): string
    mb_strtoupper(string $string): string
    mb_strtolower(string $string): string
    mb_strpos(string $haystack, string $needle, int $offset = 0): int|false
    mb_str_split(string $string, int $length = 1): array
    mb_strimwidth(string $string, int $start, int $width, string $trim_marker = ""): string
    preg_match(string $pattern, string $subject, array &$matches = null, int $flags = 0, int $offset = 0): int|false
    preg_match_all(string $pattern, string $subject, array &$matches = null, int $flags = 0): int|false
    preg_replace(array|string $pattern, array|string $replacement, array|string $subject, int $limit = -1): array|string|null
    preg_replace_callback(array|string $pattern, callable $callback, array|string $subject): array|string|null
    preg_split(string $pattern, string $subject, int $limit = -1, int $flags = 0): array|false
    preg_quote(string $str, ?string $delimiter = null): string
    ctype_digit(mixed $text): bool
    ctype_alpha(mixed $text): bool
    ctype_alnum(mixed $text): bool
    ctype_upper(mixed $text): bool
    ctype_lower(mixed $text): bool
    ctype_space(mixed $text): bool
    similar_text(string $string1, string $string2, float &$percent = null): int
    levenshtein(string $string1, string $string2): int
    password_hash(string $password, string|int|null $algo, array $options = []): string
    password_verify(string $password, string $hash): bool
    random_int(int $min, int $max): int
    random_bytes(int $length): string
    mt_rand(int $min = 0, int $max = mt_getrandmax()): int
    rand(int $min = 0, int $max = getrandmax()): int
    count(Countable|array $value, int $mode = COUNT_NORMAL): int
    array_map(?callable $callback, array $array, array ...$arrays): array
    array_filter(array $array, ?callable $callback = null, int $mode = 0): array
    array_reduce(array $array, callable $callback, mixed $initial = null): mixed
    array_merge(array ...$arrays): array
    array_merge_recursive(array ...$arrays): array
    array_replace(array $array, array ...$replacements): array
    array_combine(array $keys, array $values): array
    array_keys(array $array, mixed $filter_value, bool $strict = false): array
    array_values(array $array): array
    array_key_exists(string|int $key, array $array): bool
    array_key_first(array $array): string|int|null
    array_key_last(array $array): string|int|null
    in_array(mixed $needle, array $haystack, bool $strict = false): bool
    array_search(mixed $needle, array $haystack, bool $strict = false): string|int|false
    array_unique(array $array, int $flags = SORT_STRING): array
    array_flip(array $array): array
    array_reverse(array $array, bool $preserve_keys = false): array
    array_slice(array $array, int $offset, ?int $length = null, bool $preserve_keys = false): array
    array_splice(array &$array, int $offset, ?int $length = null, mixed $replacement = []): array
    array_push(array &$array, mixed ...$values): int
    array_pop(array &$array): mixed
    array_shift(array &$array): mixed
    array_unshift(array &$array, mixed ...$values): int
    array_sum(array $array): int|float
    array_product(array $array): int|float
    array_column(array $array, int|string|null $column_key, int|string|null $index_key = null): array
    array_chunk(array $array, int $length, bool $preserve_keys = false): array
    array_fill(int $start_index, int $count, mixed $value): array
    array_fill_keys(array $keys, mixed $value): array
    array_pad(array $array, int $length, mixed $value): array
    array_diff(array $array, array ...$arrays): array
    array_diff_key(array $array, array ...$arrays): array
    array_intersect(array $array, array ...$arrays): array
    array_intersect_key(array $array, array ...$arrays): array
    array_walk(array|object &$array, callable $callback, mixed $arg): bool
    array_rand(array $array, int $num = 1): int|string|array
    array_count_values(array $array): array
    array_is_list(array $array): bool
    range(string|int|float $start, string|int|float $end, int|float $step = 1): array
    compact(array|string $var_name, array|string ...$var_names): array
    extract(array &$array, int $flags = EXTR_OVERWRITE, string $prefix = ""): int
    sort(array &$array, int $flags = SORT_REGULAR): bool
    rsort(array &$array, int $flags = SORT_REGULAR): bool
    usort(array &$array, callable $callback): bool
    uasort(array &$array, callable $callback): bool
    uksort(array &$array, callable $callback): bool
    ksort(array &$array, int $flags = SORT_REGULAR): bool
    krsort(array &$array, int $flags = SORT_REGULAR): bool
    asort(array &$array, int $flags = SORT_REGULAR): bool
    arsort(array &$array, int $flags = SORT_REGULAR): bool
    shuffle(array &$array): bool
    min(mixed $value, mixed ...$values): mixed
    max(mixed $value, mixed ...$values): mixed
    current(array|object $array): mixed
    key(array|object $array): int|string|null
    next(array|object &$array): mixed
    reset(array|object &$array): mixed
    end(array|object &$array): mixed
    iterator_to_array(Traversable $iterator, bool $preserve_keys = true): array
    is_array(mixed $value): bool
    is_string(mixed $value): bool
    is_int(mixed $value): bool
    is_float(mixed $value): bool
    is_numeric(mixed $value): bool
    is_bool(mixed $value): bool
    is_null(mixed $value): bool
    is_object(mixed $value): bool
    is_callable(mixed $value): bool
    is_iterable(mixed $value): bool
    is_countable(mixed $value): bool
    intval(mixed $value, int $base = 10): int
    floatval(mixed $value): float
    strval(mixed $value): string
    boolval(mixed $value): bool
    gettype(mixed $value): string
    get_debug_type(mixed $value): string
    var_dump(mixed $value, mixed ...$values): void
    var_export(mixed $value, bool $return = false): ?string
    print_r(mixed $value, bool $return = false): string|bool
    serialize(mixed $value): string
    unserialize(string $data, array $options = []): mixed
    json_encode(mixed $value, int $flags = 0, int $depth = 512): string|false
    json_decode(string $json, ?bool $associative = null, int $depth = 512, int $flags = 0): mixed
    json_last_error(): int
    json_last_error_msg(): string
    time(): int
    date(string $format, ?int $timestamp = null): string
    gmdate(string $format, ?int $timestamp = null): string
    strtotime(string $datetime, ?int $baseTimestamp = null): int|false
    mktime(int $hour, ?int $minute = null, ?int $second = null, ?int $month = null, ?int $day = null, ?int $year = null): int|false
    checkdate(int $month, int $day, int $year): bool
    date_default_timezone_set(string $timezoneId): bool
    date_default_timezone_get(): string
    microtime(bool $as_float = false): string|float
    hrtime(bool $as_number = false): array|int|float|false
    usleep(int $microseconds): void
    sleep(int $seconds): int
    file_get_contents(string $filename, bool $use_include_path = false, ?resource $context = null, int $offset = 0, ?int $length = null): string|false
    file_put_contents(string $filename, mixed $data, int $flags = 0): int|false
    fopen(string $filename, string $mode): resource|false
    fclose(resource $stream): bool
    fgets(resource $stream, ?int $length = null): string|false
    fwrite(resource $stream, string $data, ?int $length = null): int|false
    fread(resource $stream, int $length): string|false
    feof(resource $stream): bool
    file_exists(string $filename): bool
    is_file(string $filename): bool
    is_dir(string $filename): bool
    mkdir(string $directory, int $permissions = 0777, bool $recursive = false): bool
    rmdir(string $directory): bool
    unlink(string $filename): bool
    rename(string $from, string $to): bool
    copy(string $from, string $to): bool
    scandir(string $directory, int $sorting_order = SCANDIR_SORT_ASCENDING): array|false
    glob(string $pattern, int $flags = 0): array|false
    realpath(string $path): string|false
    basename(string $path, string $suffix = ""): string
    dirname(string $path, int $levels = 1): string
    pathinfo(string $path, int $flags = PATHINFO_ALL): array|string
    tempnam(string $directory, string $prefix): string|false
    sys_get_temp_dir(): string
    filesize(string $filename): int|false
    filemtime(string $filename): int|false
    is_readable(string $filename): bool
    is_writable(string $filename): bool
    file(string $filename, int $flags = 0): array|false
    fputcsv(resource $stream, array $fields, string $separator = ","): int|false
    fgetcsv(resource $stream, ?int $length = null, string $separator = ","): array|false
    move_uploaded_file(string $from, string $to): bool
    abs(int|float $num): int|float
    ceil(int|float $num): float
    floor(int|float $num): float
    round(int|float $num, int $precision = 0, int $mode = PHP_ROUND_HALF_UP): float
    sqrt(float $num): float
    pow(mixed $num, mixed $exponent): int|float|object
    intdiv(int $num1, int $num2): int
    fmod(float $num1, float $num2): float
    pi(): float
    log(float $num, float $base = M_E): float
    exp(float $num): float
    base_convert(string $num, int $from_base, int $to_base): string
    dechex(int $num): string
    hexdec(string $hex_string): int|float
    decbin(int $num): string
    bindec(string $binary_string): int|float
    define(string $constant_name, mixed $value, bool $case_insensitive = false): bool
    defined(string $constant_name): bool
    constant(string $name): mixed
    function_exists(string $function): bool
    class_exists(string $class, bool $autoload = true): bool
    method_exists(object|string $object_or_class, string $method): bool
    property_exists(object|string $object_or_class, string $property): bool
    get_class(object $object): string
    get_object_vars(object $object): array
    get_parent_class(object|string $object_or_class): string|false
    call_user_func(callable $callback, mixed ...$args): mixed
    call_user_func_array(callable $callback, array $args): mixed
    func_get_args(): array
    is_a(mixed $object_or_class, string $class, bool $allow_string = false): bool
    is_subclass_of(mixed $object_or_class, string $class, bool $allow_string = true): bool
    spl_autoload_register(?callable $callback = null, bool $throw = true, bool $prepend = false): bool
    spl_object_id(object $object): int
    error_log(string $message, int $message_type = 0): bool
    trigger_error(string $message, int $error_level = E_USER_NOTICE): bool
    set_error_handler(?callable $callback, int $error_levels = E_ALL): mixed
    set_exception_handler(?callable $callback): mixed
    ini_set(string $option, string|int|float|bool|null $value): string|false
    error_reporting(?int $error_level = null): int
    phpversion(?string $extension = null): string|false
    memory_get_usage(bool $real_usage = false): int
    memory_get_peak_usage(bool $real_usage = false): int
    header(string $header, bool $replace = true, int $response_code = 0): void
    http_response_code(int $response_code = 0): int|bool
    setcookie(string $name, string $value = "", array|int $expires_or_options = 0): bool
    session_start(array $options = []): bool
    ob_start(): bool
    ob_get_clean(): string|false
    filter_var(mixed $value, int $filter = FILTER_DEFAULT, array|int $options = 0): mixed
    getenv(?string $name = null, bool $local_only = false): array|string|false
    version_compare(string $version1, string $version2, ?string $operator = null): int|bool
    """

    /// Laravel global helpers.
    static let laravelFunctions = """
    route(string $name, mixed $parameters = [], bool $absolute = true): string
    config(array|string|null $key = null, mixed $default = null): mixed
    view(?string $view = null, array $data = [], array $mergeData = []): Illuminate\\Contracts\\View\\View
    auth(?string $guard = null): Illuminate\\Contracts\\Auth\\Guard
    request(array|string|null $key = null, mixed $default = null): mixed
    collect(mixed $value = []): Illuminate\\Support\\Collection
    response(string $content = "", int $status = 200, array $headers = []): Illuminate\\Http\\Response
    redirect(?string $to = null, int $status = 302): Illuminate\\Routing\\Redirector
    to_route(string $route, mixed $parameters = [], int $status = 302): RedirectResponse
    session(array|string|null $key = null, mixed $default = null): mixed
    abort(int $code, string $message = "", array $headers = []): never
    abort_if(bool $boolean, int $code, string $message = ""): void
    abort_unless(bool $boolean, int $code, string $message = ""): void
    back(int $status = 302, array $headers = []): RedirectResponse
    old(?string $key = null, mixed $default = null): mixed
    cache(mixed ...$arguments): mixed
    logger(?string $message = null, array $context = []): mixed
    now(?DateTimeZone $tz = null): Illuminate\\Support\\Carbon
    today(?DateTimeZone $tz = null): Illuminate\\Support\\Carbon
    optional(mixed $value = null, ?callable $callback = null): mixed
    tap(mixed $value, ?callable $callback = null): mixed
    value(mixed $value, mixed ...$args): mixed
    dd(mixed ...$vars): never
    dump(mixed ...$vars): void
    env(string $key, mixed $default = null): mixed
    app(?string $abstract = null, array $parameters = []): mixed
    url(?string $path = null, mixed $parameters = [], ?bool $secure = null): string
    asset(string $path, ?bool $secure = null): string
    trans(?string $key = null, array $replace = [], ?string $locale = null): mixed
    __(?string $key = null, array $replace = [], ?string $locale = null): string
    validator(array $data = [], array $rules = [], array $messages = []): Validator
    bcrypt(string $value, array $options = []): string
    storage_path(string $path = ""): string
    base_path(string $path = ""): string
    public_path(string $path = ""): string
    resource_path(string $path = ""): string
    database_path(string $path = ""): string
    config_path(string $path = ""): string
    data_get(mixed $target, string|array|int|null $key, mixed $default = null): mixed
    blank(mixed $value): bool
    filled(mixed $value): bool
    throw_if(mixed $condition, Throwable|string $exception = "RuntimeException", mixed ...$parameters): mixed
    throw_unless(mixed $condition, Throwable|string $exception = "RuntimeException", mixed ...$parameters): mixed
    retry(int|array $times, callable $callback, int $sleepMilliseconds = 0): mixed
    with(mixed $value, ?callable $callback = null): mixed
    event(mixed ...$args): array|null
    dispatch(mixed $job): PendingDispatch
    info(string $message, array $context = []): void
    report(Throwable|string $exception): void
    rescue(callable $callback, mixed $rescue = null, bool $report = true): mixed
    resolve(string $name, array $parameters = []): mixed
    csrf_token(): string
    csrf_field(): Illuminate\\Support\\HtmlString
    method_field(string $method): Illuminate\\Support\\HtmlString
    e(string $value, bool $doubleEncode = true): string
    class_basename(string|object $class): string
    str(?string $string = null): Illuminate\\Support\\Stringable
    """

    static let eloquentStatic = """
    where(column, operator, value)|Builder
    whereIn(column, values)|Builder
    whereNull(column)|Builder
    whereNotNull(column)|Builder
    whereBetween(column, values)|Builder
    orWhere(column, operator, value)|Builder
    find(id)|Model|null
    findOrFail(id)|Model
    findMany(ids)|Collection
    first()|Model|null
    firstOrFail()|Model
    firstWhere(column, value)|Model|null
    firstOrCreate(attributes, values)|Model
    firstOrNew(attributes, values)|Model
    updateOrCreate(attributes, values)|Model
    all(columns)|Collection
    get(columns)|Collection
    create(attributes)|Model
    insert(values)|bool
    upsert(values, uniqueBy, update)|int
    query()|Builder
    with(relations)|Builder
    withCount(relations)|Builder
    has(relation)|Builder
    whereHas(relation, callback)|Builder
    orderBy(column, direction)|Builder
    orderByDesc(column)|Builder
    latest(column)|Builder
    oldest(column)|Builder
    pluck(column, key)|Collection
    count()|int
    max(column)|mixed
    min(column)|mixed
    sum(column)|mixed
    avg(column)|mixed
    exists()|bool
    paginate(perPage)|LengthAwarePaginator
    simplePaginate(perPage)|Paginator
    destroy(ids)|int
    truncate()|void
    select(columns)|Builder
    take(value)|Builder
    limit(value)|Builder
    chunk(count, callback)|bool
    cursor()|LazyCollection
    factory()|Factory
    withTrashed()|Builder
    onlyTrashed()|Builder
    """

    static let routeMethods = "get(uri, action) post(uri, action) put(uri, action) patch(uri, action) delete(uri, action) options(uri, action) any(uri, action) match(methods, uri, action) resource(name, controller) apiResource(name, controller) resources(resources) group(attributes, routes) prefix(prefix) middleware(middleware) name(name) view(uri, view) redirect(uri, destination) controller(controller) domain(domain) where(name, expression) fallback(action) current() has(name) is(patterns) apiResources(resources)"

    static let facades: [String: String] = [
        "Str": "of(string) slug(title) camel(value) snake(value) kebab(value) studly(value) limit(value, limit) random(length) uuid() contains(haystack, needles) startsWith(haystack, needles) endsWith(haystack, needles) title(value) plural(value) singular(value) upper(value) lower(value) before(subject, search) after(subject, search) replace(search, replace, subject) is(pattern, value) length(value) ucfirst(string) words(value, words)",
        "Arr": "get(array, key, default) set(array, key, value) has(array, keys) only(array, keys) except(array, keys) first(array, callback) last(array, callback) flatten(array) pluck(array, value, key) wrap(value) where(array, callback) random(array) shuffle(array) sort(array) dot(array) forget(array, keys) isAssoc(array) map(array, callback)",
        "DB": "table(table) select(query, bindings) insert(query, bindings) update(query, bindings) delete(query, bindings) statement(query, bindings) transaction(callback) beginTransaction() commit() rollBack() raw(value) connection(name) unprepared(query)",
        "Auth": "user() id() check() guest() attempt(credentials, remember) login(user, remember) logout() guard(name) loginUsingId(id) once(credentials) viaRemember() validate(credentials)",
        "Cache": "get(key, default) put(key, value, ttl) remember(key, ttl, callback) rememberForever(key, callback) forget(key) has(key) forever(key, value) pull(key) add(key, value, ttl) increment(key, value) decrement(key, value) flush() tags(names) lock(name, seconds)",
        "Log": "info(message, context) error(message, context) warning(message, context) debug(message, context) critical(message, context) notice(message, context) alert(message, context) emergency(message, context) channel(name)",
        "Storage": "disk(name) put(path, contents) get(path) exists(path) delete(paths) url(path) path(path) download(path, name) files(directory) allFiles(directory) makeDirectory(path) deleteDirectory(directory) copy(from, to) move(from, to) putFile(path, file) putFileAs(path, file, name) size(path) lastModified(path)",
        "Schema": "create(table, callback) table(table, callback) drop(table) dropIfExists(table) hasTable(table) hasColumn(table, column) rename(from, to) disableForeignKeyConstraints() enableForeignKeyConstraints() getColumnListing(table)",
        "Http": "get(url, query) post(url, data) put(url, data) patch(url, data) delete(url, data) withHeaders(headers) withToken(token) acceptJson() asJson() asForm() timeout(seconds) retry(times, sleep) baseUrl(url) fake(callback) pool(callback) withBody(content, type) attach(name, contents)",
        "Hash": "make(value, options) check(value, hashedValue) needsRehash(hashedValue)",
        "Validator": "make(data, rules, messages) validate(data, rules)",
        "Config": "get(key, default) set(key, value) has(key) all()",
        "Session": "get(key, default) put(key, value) has(key) forget(key) flash(key, value) pull(key) all() flush() regenerate() token() push(key, value)",
        "Gate": "allows(ability, arguments) denies(ability, arguments) check(abilities, arguments) authorize(ability, arguments) define(ability, callback) policy(model, policy) before(callback) forUser(user)",
        "Event": "dispatch(event) listen(events, listener) fake() forget(event) subscribe(subscriber)",
        "Queue": "push(job, data, queue) later(delay, job) size(queue) fake()",
        "Mail": "to(users) send(mailable) queue(mailable) raw(text, callback) fake()",
        "Notification": "send(notifiables, notification) route(channel, route) fake()",
        "Redirect": "to(path) route(name, parameters) back() away(path) action(action) intended(default)",
        "URL": "to(path) route(name, parameters) current() full() previous() asset(path) signedRoute(name, parameters) temporarySignedRoute(name, expiration, parameters)",
        "File": "exists(path) get(path) put(path, contents) delete(paths) copy(path, target) move(path, target) makeDirectory(path) files(directory) isDirectory(path) extension(path) name(path) glob(pattern)",
        "Artisan": "call(command, parameters) output() queue(command, parameters)",
        "Carbon": "now() today() tomorrow() yesterday() parse(time) create(year, month, day) createFromFormat(format, time) createFromTimestamp(timestamp) make(var)",
        "Request": "input(key, default) all() query(key, default) has(key) only(keys) except(keys) file(key) hasFile(key) user() ip() url() fullUrl() path() method() is(patterns) header(key) bearerToken() validate(rules) boolean(key) string(key) integer(key)",
        "Response": "json(data, status, headers) make(content, status, headers) noContent(status) download(file, name, headers) view(view, data) stream(callback) file(path)",
        "Route": "",
    ]

    static let eloquentInstance = "save() update(attributes) delete() fill(attributes) refresh() fresh() toArray() toJson() load(relations) loadMissing(relations) replicate() touch() push() isDirty() isClean() wasChanged() getKey() getAttribute(key) setAttribute(key, value) relationLoaded(relation) is(model) isNot(model) only(attributes) makeHidden(attributes) makeVisible(attributes) append(attributes) forceDelete() restore() trashed() where(column, operator, value) with(relations) orderBy(column, direction) first() get() count() map(callback) filter(callback) pluck(column) toArray() each(callback) sum(column) avg(column) groupBy(key) sortBy(callback) values() keys() unique() reverse() isEmpty() isNotEmpty() contains(value) implode(glue) take(limit) skip(count) chunk(size) flatten() merge(items) collect() reduce(callback, initial) paginate(perPage) push(value) put(key, value) pull(key) firstWhere(key, value) json(data) input(key, default) all() validate(rules) user() has(key) ip() header(key) file(key) id() check()"

    static let requestFamily: [String: String] = [
        "response": "json(data, status, headers) view(view, data, status) download(file, name) redirectTo(path) make(content, status) noContent() stream(callback) file(path) streamDownload(callback, name) withHeaders(headers) setStatusCode(code)",
        "request": "input(key, default) all() query(key, default) has(key) only(keys) except(keys) file(key) hasFile(key) user() ip() url() fullUrl() path() method() is(patterns) header(key) bearerToken() validate(rules) boolean(key) string(key) integer(key) json() merge(input) filled(key) route(param) wantsJson() expectsJson() ajax() cookie(key)",
        "auth": "user() id() check() guest() attempt(credentials, remember) login(user, remember) logout() guard(name) loginUsingId(id) viaRemember() validate(credentials)",
        "redirect": "to(path) route(name, parameters) back() away(path) action(action) intended(default) with(key, value) withErrors(errors) withInput(input)",
        "view": "with(key, value) render() name() getData() getPath()",
        "collect": "map(callback) filter(callback) pluck(key) first(callback) get(key) all() toArray() count() sum(key) avg(key) groupBy(key) sortBy(callback) values() keys() unique() reverse() isEmpty() contains(value) implode(glue) take(limit) each(callback) push(value) flatten() merge(items) reduce(callback, initial) where(key, value) mapWithKeys(callback) chunk(size)",
        "now": "format(format) addDays(value) subDays(value) addHours(value) addMinutes(value) startOfDay() endOfDay() diffForHumans() toDateString() toDateTimeString() timestamp isoFormat(format) isToday() isPast() isFuture() copy() diffInDays(date) startOfMonth() endOfMonth()",
        "session": "get(key, default) put(key, value) has(key) forget(key) flash(key, value) pull(key) all() flush() regenerate() push(key, value)",
    ]

    // MARK: JavaScript / TypeScript

    static let jsKeywords = words("""
    async await break case catch class const continue debugger default delete do else export extends false finally for from function if \
    import in instanceof let new null of return static super switch this throw true try typeof undefined var void while with yield get set \
    constructor as
    """)
    static let tsKeywords = words("interface type enum namespace declare readonly keyof infer abstract implements private public protected satisfies unknown never any string number boolean object symbol bigint is asserts override module")
    static let jsGlobals = words("""
    console window document Math JSON Promise Array Object Number String Date Map Set WeakMap WeakSet Symbol RegExp Error TypeError RangeError \
    fetch setTimeout setInterval clearTimeout clearInterval parseInt parseFloat isNaN isFinite localStorage sessionStorage require module exports process \
    NaN Infinity structuredClone queueMicrotask requestAnimationFrame cancelAnimationFrame URL URLSearchParams FormData AbortController Intl BigInt \
    globalThis alert confirm prompt navigator location history Boolean Function Reflect Proxy Blob File FileReader Headers Request Response Event CustomEvent \
    atob btoa encodeURIComponent decodeURIComponent encodeURI decodeURI Uint8Array Float64Array ArrayBuffer TextEncoder TextDecoder performance
    """)
    static let reactHooks = "useState(initial) useEffect(effect, deps) useRef(initial) useMemo(factory, deps) useCallback(fn, deps) useContext(context) useReducer(reducer, initial) useLayoutEffect(effect, deps) useId() useTransition() useDeferredValue(value) createContext(default) forwardRef(render) memo(component) lazy(loader) Suspense Fragment"
    static let vueApi = "ref(value) reactive(obj) computed(getter) watch(source, callback) watchEffect(effect) onMounted(hook) onUnmounted(hook) onBeforeMount(hook) onBeforeUnmount(hook) onUpdated(hook) onBeforeUpdate(hook) nextTick() toRef(object, key) toRefs(object) toRaw(proxy) unref(ref) isRef(value) provide(key, value) inject(key, default) useSlots() useAttrs() shallowRef(value) readonly(obj) defineAsyncComponent(loader) h(type, props, children) useTemplateRef(key) storeToRefs(store) useRoute() useRouter()"
    static let vueMacros = "defineProps() defineEmits() defineExpose() defineModel() defineOptions() defineSlots() withDefaults(props, defaults)"

    static let jsMembers: [String: String] = [
        "console": "log(...data) error(...data) warn(...data) info(...data) debug(...data) table(data) dir(obj) time(label) timeEnd(label) group(label) groupEnd() assert(condition, ...data) trace() count(label) clear()",
        "Math": "abs(x) ceil(x) floor(x) round(x) max(...values) min(...values) pow(x, y) sqrt(x) random() sign(x) trunc(x) log(x) exp(x) sin(x) cos(x) tan(x) atan2(y, x) hypot(...values) cbrt(x) PI E",
        "JSON": "parse(text) stringify(value, replacer, space)",
        "Promise": "all(iterable) allSettled(iterable) race(iterable) any(iterable) resolve(value) reject(reason) withResolvers()",
        "Array": "isArray(value) from(iterable, mapFn) of(...items)",
        "Object": "keys(obj) values(obj) entries(obj) assign(target, ...sources) freeze(obj) fromEntries(entries) create(proto) defineProperty(obj, prop, descriptor) getPrototypeOf(obj) hasOwn(obj, prop) isFrozen(obj) getOwnPropertyNames(obj)",
        "Number": "isInteger(value) isFinite(value) isNaN(value) parseFloat(string) parseInt(string) MAX_SAFE_INTEGER MIN_SAFE_INTEGER EPSILON isSafeInteger(value)",
        "String": "fromCharCode(...codes) raw(strings, ...values) fromCodePoint(...codes)",
        "Date": "now() parse(string) UTC(year, month)",
        "document": "querySelector(selector) querySelectorAll(selector) getElementById(id) getElementsByClassName(name) createElement(tag) createTextNode(text) addEventListener(type, listener) removeEventListener(type, listener) body head documentElement title cookie readyState",
        "window": "addEventListener(type, listener) removeEventListener(type, listener) location localStorage sessionStorage innerWidth innerHeight scrollTo(x, y) open(url) matchMedia(query) history navigator requestAnimationFrame(callback) getComputedStyle(element) postMessage(message, origin)",
        "localStorage": "getItem(key) setItem(key, value) removeItem(key) clear() key(index) length",
        "sessionStorage": "getItem(key) setItem(key, value) removeItem(key) clear() key(index) length",
        "process": "env argv cwd() exit(code) platform nextTick(callback) on(event, listener) stdout stderr version",
        "Reflect": "get(target, key) set(target, key, value) has(target, key) ownKeys(target) apply(target, thisArg, args)",
        "Intl": "NumberFormat(locale, options) DateTimeFormat(locale, options) Collator(locale) PluralRules(locale) RelativeTimeFormat(locale)",
    ]
    static let jsGenericMembers = "map(callback) filter(callback) reduce(callback, initial) forEach(callback) find(callback) findIndex(callback) some(callback) every(callback) includes(value) indexOf(value) join(separator) slice(start, end) splice(start, count) push(...items) pop() shift() unshift(...items) sort(compare) reverse() concat(...items) flat(depth) flatMap(callback) keys() values() entries() length split(separator) trim() toLowerCase() toUpperCase() replace(pattern, replacement) replaceAll(pattern, replacement) startsWith(search) endsWith(search) padStart(length, fill) padEnd(length, fill) substring(start, end) match(regexp) charAt(index) toString() then(onFulfilled) catch(onRejected) finally(callback) addEventListener(type, listener) hasOwnProperty(prop) toFixed(digits) at(index)"

    // MARK: HTML

    static let htmlTags = words("""
    a abbr address article aside audio b blockquote body br button canvas caption code col colgroup dd details dialog div dl dt em fieldset \
    figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hr html i iframe img input label legend li link main meta nav noscript ol optgroup \
    option p picture pre progress script section select small source span strong style sub summary sup svg table tbody td template textarea tfoot th \
    thead time title tr ul video path circle rect g slot component
    """)
    static let voidTags: Set<String> = ["br", "hr", "img", "input", "link", "meta", "source", "col", "area", "base", "embed", "track", "wbr", "path", "circle", "rect"]
    static let htmlGlobalAttrs = words("id class style title lang dir hidden tabindex draggable contenteditable data- aria-label aria-hidden aria-describedby role onclick onchange onsubmit oninput autofocus")
    static let htmlTagAttrs: [String: String] = [
        "a": "href target rel download hreflang",
        "img": "src alt width height loading srcset sizes decoding",
        "input": "type name value placeholder required disabled readonly checked min max step pattern autocomplete maxlength minlength multiple accept for form",
        "button": "type name value disabled form",
        "form": "action method enctype novalidate autocomplete target",
        "label": "for form",
        "select": "name multiple required disabled size",
        "option": "value selected disabled",
        "textarea": "name rows cols placeholder required disabled readonly maxlength",
        "link": "rel href type media as crossorigin integrity",
        "script": "src type async defer crossorigin integrity nomodule",
        "meta": "name content charset http-equiv property",
        "iframe": "src width height allow allowfullscreen loading sandbox title",
        "video": "src controls autoplay loop muted poster preload playsinline width height",
        "audio": "src controls autoplay loop muted preload",
        "td": "colspan rowspan headers",
        "th": "colspan rowspan scope",
        "svg": "viewBox xmlns fill stroke width height",
        "path": "d fill stroke stroke-width stroke-linecap stroke-linejoin",
    ]
    static let htmlAttrValues: [String: String] = [
        "type": "text password email number checkbox radio file hidden date datetime-local time tel url search color range submit reset button module text/javascript text/css",
        "target": "_blank _self _parent _top",
        "rel": "stylesheet noopener noreferrer nofollow icon preload prefetch canonical alternate",
        "method": "get post dialog",
        "autocomplete": "on off email username current-password new-password name tel",
        "loading": "lazy eager",
        "enctype": "multipart/form-data application/x-www-form-urlencoded text/plain",
        "crossorigin": "anonymous use-credentials",
        "dir": "ltr rtl auto",
        "role": "button navigation main banner dialog alert list listitem menu tab tabpanel img presentation",
        "scope": "row col rowgroup colgroup",
        "preload": "none metadata auto",
        "as": "style script font image fetch",
        "decoding": "async sync auto",
        "contenteditable": "true false",
        "draggable": "true false",
        "name": "viewport description keywords author robots theme-color",
    ]
    static let vueAttrs = words("""
    v-if v-else-if v-else v-for v-model v-show v-html v-text v-bind: v-on: v-slot: v-once v-pre v-cloak v-memo \
    @click @input @change @submit.prevent @keydown.enter @keyup @focus @blur @mouseenter @mouseleave :key :class :style :src :href :disabled :value ref key is #default #header #footer
    """)

    // MARK: CSS

    static let cssProperties = words("""
    align-content align-items align-self animation animation-delay animation-duration animation-name animation-timing-function appearance aspect-ratio \
    backdrop-filter backface-visibility background background-attachment background-clip background-color background-image background-position background-repeat background-size \
    border border-bottom border-bottom-color border-bottom-left-radius border-bottom-right-radius border-bottom-width border-collapse border-color border-left border-radius border-right border-spacing border-style \
    border-top border-top-left-radius border-top-right-radius border-width bottom box-shadow box-sizing caret-color clear clip-path color column-gap columns content cursor \
    display filter flex flex-basis flex-direction flex-flow flex-grow flex-shrink flex-wrap float font font-family font-size font-style font-variant font-weight gap grid grid-area \
    grid-auto-columns grid-auto-flow grid-auto-rows grid-column grid-gap grid-row grid-template grid-template-areas grid-template-columns grid-template-rows height inset isolation \
    justify-content justify-items justify-self left letter-spacing line-height list-style list-style-type margin margin-bottom margin-left margin-right margin-top max-height max-width \
    min-height min-width mix-blend-mode object-fit object-position opacity order outline outline-offset overflow overflow-x overflow-y padding padding-bottom padding-left padding-right padding-top \
    place-content place-items pointer-events position resize right row-gap scroll-behavior scroll-snap-type tab-size table-layout text-align text-decoration text-decoration-color text-indent \
    text-overflow text-shadow text-transform top transform transform-origin transition transition-delay transition-duration transition-property transition-timing-function user-select \
    vertical-align visibility white-space width will-change word-break word-spacing word-wrap writing-mode z-index
    """)
    static let cssValues: [String: String] = [
        "display": "block inline inline-block flex inline-flex grid inline-grid none contents table flow-root",
        "position": "static relative absolute fixed sticky",
        "flex-direction": "row row-reverse column column-reverse",
        "flex-wrap": "nowrap wrap wrap-reverse",
        "justify-content": "flex-start flex-end center space-between space-around space-evenly start end stretch",
        "align-items": "stretch flex-start flex-end center baseline start end",
        "align-self": "auto stretch flex-start flex-end center baseline",
        "align-content": "stretch flex-start flex-end center space-between space-around",
        "overflow": "visible hidden scroll auto clip",
        "overflow-x": "visible hidden scroll auto clip",
        "overflow-y": "visible hidden scroll auto clip",
        "text-align": "left right center justify start end",
        "cursor": "pointer default text move not-allowed grab grabbing crosshair wait help zoom-in zoom-out",
        "font-weight": "normal bold bolder lighter 100 200 300 400 500 600 700 800 900",
        "font-style": "normal italic oblique",
        "text-decoration": "none underline line-through overline",
        "text-transform": "none uppercase lowercase capitalize",
        "white-space": "normal nowrap pre pre-wrap pre-line break-spaces",
        "visibility": "visible hidden collapse",
        "box-sizing": "border-box content-box",
        "float": "none left right",
        "clear": "none left right both",
        "background-repeat": "repeat no-repeat repeat-x repeat-y space round",
        "background-size": "auto cover contain",
        "background-position": "center top bottom left right",
        "object-fit": "fill contain cover none scale-down",
        "list-style": "none disc circle square decimal",
        "list-style-type": "none disc circle square decimal",
        "border-style": "none solid dashed dotted double groove ridge",
        "border": "none solid dashed dotted 1px",
        "outline": "none solid dashed 1px",
        "user-select": "none auto text all",
        "pointer-events": "none auto all",
        "word-break": "normal break-all keep-all break-word",
        "text-overflow": "clip ellipsis",
        "vertical-align": "baseline top middle bottom text-top text-bottom sub super",
        "transition-timing-function": "ease ease-in ease-out ease-in-out linear",
        "animation-timing-function": "ease ease-in ease-out ease-in-out linear",
        "resize": "none both horizontal vertical",
        "table-layout": "auto fixed",
        "border-collapse": "collapse separate",
        "scroll-behavior": "auto smooth",
        "appearance": "none auto",
        "isolation": "auto isolate",
        "writing-mode": "horizontal-tb vertical-rl vertical-lr",
        "width": "auto 100% 100vw fit-content max-content min-content",
        "height": "auto 100% 100vh fit-content max-content min-content",
        "margin": "auto 0",
        "padding": "0",
        "z-index": "auto 0 1 10 100 999",
        "opacity": "0 0.5 1",
        "color": "inherit currentColor transparent white black red green blue gray",
        "background": "none transparent white black",
        "background-color": "transparent white black currentColor",
        "border-color": "transparent currentColor",
        "content": "none normal \"\"",
    ]
    static let cssGlobalValues = words("inherit initial unset revert")
    static let cssAtRules = words("@media @import @font-face @keyframes @supports @layer @container @charset @namespace @page @property @apply @tailwind @screen @theme @config @plugin @include @mixin @use @forward @extend @function @return @if @else @each @for @while")
    static let cssPseudo = words(":hover :focus :active :visited :first-child :last-child :nth-child() :nth-of-type() :not() :is() :where() :has() :before :after ::before ::after ::placeholder ::selection :focus-within :focus-visible :disabled :checked :empty :root :first-of-type :last-of-type :only-child :target")

    // MARK: Blade

    /// "name|snippet" ("$0"-style LSP snippet; tab = indent).
    static let bladeDirectives = """
    if|@if($1)\\n\\t$0\\n@endif
    elseif|@elseif($1)
    else|@else
    endif|@endif
    unless|@unless($1)\\n\\t$0\\n@endunless
    isset|@isset($1)\\n\\t$0\\n@endisset
    empty|@empty($1)\\n\\t$0\\n@endempty
    foreach|@foreach($1 as $2)\\n\\t$0\\n@endforeach
    forelse|@forelse($1 as $2)\\n\\t$0\\n@empty\\n\\t\\n@endforelse
    for|@for($1)\\n\\t$0\\n@endfor
    while|@while($1)\\n\\t$0\\n@endwhile
    break|@break
    continue|@continue
    endforeach|@endforeach
    endforelse|@endforelse
    endfor|@endfor
    endwhile|@endwhile
    switch|@switch($1)\\n\\t@case($2)\\n\\t\\t$0\\n\\t\\t@break\\n\\t@default\\n@endswitch
    case|@case($1)
    default|@default
    section|@section('$1')\\n\\t$0\\n@endsection
    endsection|@endsection
    yield|@yield('$1')
    show|@show
    parent|@parent
    extends|@extends('$1')
    include|@include('$1')
    includeIf|@includeIf('$1')
    includeWhen|@includeWhen($1, '$2')
    includeFirst|@includeFirst(['$1'])
    each|@each('$1', $2, '$3')
    component|@component('$1')\\n\\t$0\\n@endcomponent
    slot|@slot('$1')\\n\\t$0\\n@endslot
    props|@props(['$1'])
    push|@push('$1')\\n\\t$0\\n@endpush
    endpush|@endpush
    stack|@stack('$1')
    prepend|@prepend('$1')\\n\\t$0\\n@endprepend
    once|@once\\n\\t$0\\n@endonce
    auth|@auth\\n\\t$0\\n@endauth
    endauth|@endauth
    guest|@guest\\n\\t$0\\n@endguest
    endguest|@endguest
    can|@can('$1')\\n\\t$0\\n@endcan
    cannot|@cannot('$1')\\n\\t$0\\n@endcannot
    canany|@canany(['$1'])\\n\\t$0\\n@endcanany
    csrf|@csrf
    method|@method('$1')
    error|@error('$1')\\n\\t$0\\n@enderror
    enderror|@enderror
    env|@env('$1')\\n\\t$0\\n@endenv
    production|@production\\n\\t$0\\n@endproduction
    php|@php\\n\\t$0\\n@endphp
    endphp|@endphp
    json|@json($1)
    class|@class([$1])
    style|@style([$1])
    checked|@checked($1)
    selected|@selected($1)
    disabled|@disabled($1)
    required|@required($1)
    readonly|@readonly($1)
    vite|@vite(['$1'])
    livewire|@livewire('$1')
    livewireStyles|@livewireStyles
    livewireScripts|@livewireScripts
    inertia|@inertia
    inertiaHead|@inertiaHead
    routes|@routes
    lang|@lang('$1')
    dd|@dd($1)
    dump|@dump($1)
    verbatim|@verbatim\\n\\t$0\\n@endverbatim
    session|@session('$1')\\n\\t$0\\n@endsession
    teleport|@teleport('$1')\\n\\t$0\\n@endteleport
    fragment|@fragment('$1')\\n\\t$0\\n@endfragment
    """
}
