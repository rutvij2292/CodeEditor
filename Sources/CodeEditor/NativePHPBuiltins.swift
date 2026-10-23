import Foundation

// Documentation-only tables for PHP built-ins (no source to jump to). Parsed lazily on first use, then ~30 KB resident.
// Format of a function line: name|signature|summary.

enum NPBuiltins {
    struct Fn { var name: String; var signature: String; var doc: String }

    static let functions: [String: Fn] = {
        var out: [String: Fn] = [:]
        for line in functionLines.split(separator: "\n") {
            let p = line.split(separator: "¦", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 3 else { continue }
            out[p[0].lowercased()] = Fn(name: p[0], signature: p[1], doc: p[2])
        }
        return out
    }()

    static let constants: [String: String] = {
        var out: [String: String] = [:]
        for line in constantLines.split(separator: "\n") {
            let p = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if p.count == 2 { out[p[0]] = p[1] }
        }
        return out
    }()

    /// Core classes/interfaces: name -> kind. Hover only.
    static let classes: [String: String] = {
        var out: [String: String] = [:]
        for n in ["stdClass", "Exception", "ErrorException", "Error", "TypeError", "ValueError", "ArgumentCountError", "ArithmeticError", "DivisionByZeroError",
                  "RuntimeException", "LogicException", "InvalidArgumentException", "DomainException", "LengthException", "OutOfRangeException",
                  "OutOfBoundsException", "RangeException", "OverflowException", "UnderflowException", "UnexpectedValueException", "BadFunctionCallException",
                  "BadMethodCallException", "JsonException", "DateTime", "DateTimeImmutable", "DateTimeZone", "DateInterval", "DatePeriod", "Closure",
                  "Generator", "ArrayObject", "ArrayIterator", "SplStack", "SplQueue", "SplObjectStorage", "SplFileInfo", "SplFixedArray", "PDO", "PDOException",
                  "PDOStatement", "WeakMap", "WeakReference", "ReflectionClass", "ReflectionMethod", "ReflectionProperty", "ReflectionFunction",
                  "ReflectionNamedType", "ReflectionObject", "ReflectionEnum", "Attribute", "SensitiveParameter", "Override", "ReturnTypeWillChange",
                  "AllowDynamicProperties", "NumberFormatter", "IntlDateFormatter", "Random\\Randomizer", "SimpleXMLElement", "DOMDocument"] { out[n] = "class" }
        for n in ["Throwable", "Traversable", "Iterator", "IteratorAggregate", "ArrayAccess", "Countable", "Stringable", "JsonSerializable", "Serializable",
                  "UnitEnum", "BackedEnum", "DateTimeInterface", "SeekableIterator", "OuterIterator", "RecursiveIterator", "SplObserver", "SplSubject"] { out[n] = "interface" }
        return out
    }()

    private static let constantLines = """
    PHP_EOL|`string` End-of-line marker for the platform ("\\n" on Unix).
    PHP_INT_MAX|`int` Largest integer supported.
    PHP_INT_MIN|`int` Smallest integer supported.
    PHP_INT_SIZE|`int` Size of an integer in bytes.
    PHP_FLOAT_EPSILON|`float` Smallest representable float difference.
    PHP_FLOAT_MAX|`float` Largest representable float.
    PHP_VERSION|`string` Current PHP version as a string.
    PHP_VERSION_ID|`int` Current PHP version as an integer (e.g. 80300).
    PHP_OS|`string` Operating system PHP was built for.
    PHP_OS_FAMILY|`string` Operating system family (Linux, Darwin, Windows...).
    DIRECTORY_SEPARATOR|`string` Directory separator for the platform.
    PATH_SEPARATOR|`string` Separator between paths in PATH-like strings.
    M_PI|`float` The value of pi.
    M_E|`float` Euler's number.
    NAN|`float` Not-a-number.
    INF|`float` Positive infinity.
    E_ALL|`int` All error reporting levels.
    E_ERROR|`int` Fatal run-time error.
    E_WARNING|`int` Run-time warning.
    E_NOTICE|`int` Run-time notice.
    E_DEPRECATED|`int` Deprecated-code notice.
    E_STRICT|`int` Strict standards suggestion.
    JSON_PRETTY_PRINT|`int` Pretty-print JSON output.
    JSON_THROW_ON_ERROR|`int` Throw JsonException on error.
    JSON_UNESCAPED_UNICODE|`int` Do not escape multibyte characters.
    JSON_UNESCAPED_SLASHES|`int` Do not escape slashes.
    JSON_ERROR_NONE|`int` No JSON error occurred.
    SORT_REGULAR|`int` Compare items normally.
    SORT_STRING|`int` Compare items as strings.
    SORT_NUMERIC|`int` Compare items numerically.
    COUNT_RECURSIVE|`int` Count recursively.
    ARRAY_FILTER_USE_KEY|`int` array_filter callback receives the key.
    ARRAY_FILTER_USE_BOTH|`int` array_filter callback receives value and key.
    LOCK_EX|`int` Exclusive lock for file_put_contents.
    FILE_APPEND|`int` Append to the file instead of overwriting.
    FILE_IGNORE_NEW_LINES|`int` Skip new line at the end of each array element.
    FILE_SKIP_EMPTY_LINES|`int` Skip empty lines.
    ENT_QUOTES|`int` Convert both double and single quotes.
    STR_PAD_LEFT|`int` Pad on the left side.
    STR_PAD_RIGHT|`int` Pad on the right side.
    PREG_SPLIT_NO_EMPTY|`int` Return only non-empty pieces.
    LC_ALL|`int` All locale categories.
    __DIR__|`string` Directory of the current file.
    __FILE__|`string` Full path of the current file.
    __LINE__|`int` Current line number.
    __CLASS__|`string` Current class name.
    __FUNCTION__|`string` Current function name.
    __METHOD__|`string` Current class method name.
    __NAMESPACE__|`string` Current namespace name.
    """

    private static let functionLines = """
    count¦count(Countable|array $value, int $mode = COUNT_NORMAL): int¦Counts all elements in an array or a Countable object.
    sizeof¦sizeof(Countable|array $value, int $mode = COUNT_NORMAL): int¦Alias of count().
    strlen¦strlen(string $string): int¦Returns the length of a string in bytes.
    mb_strlen¦mb_strlen(string $string, ?string $encoding = null): int¦Returns the number of characters in a string.
    substr¦substr(string $string, int $offset, ?int $length = null): string¦Returns part of a string.
    mb_substr¦mb_substr(string $string, int $start, ?int $length = null, ?string $encoding = null): string¦Returns part of a multibyte string.
    strpos¦strpos(string $haystack, string $needle, int $offset = 0): int|false¦Finds the position of the first occurrence of a substring.
    stripos¦stripos(string $haystack, string $needle, int $offset = 0): int|false¦Case-insensitive strpos().
    strrpos¦strrpos(string $haystack, string $needle, int $offset = 0): int|false¦Finds the position of the last occurrence of a substring.
    str_contains¦str_contains(string $haystack, string $needle): bool¦Determines if a string contains a given substring.
    str_starts_with¦str_starts_with(string $haystack, string $needle): bool¦Checks if a string starts with a given substring.
    str_ends_with¦str_ends_with(string $haystack, string $needle): bool¦Checks if a string ends with a given substring.
    str_replace¦str_replace(array|string $search, array|string $replace, string|array $subject, int &$count = null): string|array¦Replaces all occurrences of the search string with the replacement.
    str_repeat¦str_repeat(string $string, int $times): string¦Repeats a string.
    str_pad¦str_pad(string $string, int $length, string $pad_string = " ", int $pad_type = STR_PAD_RIGHT): string¦Pads a string to a certain length with another string.
    str_split¦str_split(string $string, int $length = 1): array¦Converts a string to an array.
    str_word_count¦str_word_count(string $string, int $format = 0, ?string $characters = null): array|int¦Returns information about words used in a string.
    strtolower¦strtolower(string $string): string¦Makes a string lowercase.
    strtoupper¦strtoupper(string $string): string¦Makes a string uppercase.
    ucfirst¦ucfirst(string $string): string¦Makes the first character uppercase.
    ucwords¦ucwords(string $string, string $separators = " \\t\\r\\n\\f\\v"): string¦Uppercases the first character of each word.
    lcfirst¦lcfirst(string $string): string¦Makes the first character lowercase.
    trim¦trim(string $string, string $characters = " \\n\\r\\t\\v\\x00"): string¦Strips whitespace (or other characters) from both ends of a string.
    ltrim¦ltrim(string $string, string $characters = " \\n\\r\\t\\v\\x00"): string¦Strips characters from the start of a string.
    rtrim¦rtrim(string $string, string $characters = " \\n\\r\\t\\v\\x00"): string¦Strips characters from the end of a string.
    explode¦explode(string $separator, string $string, int $limit = PHP_INT_MAX): array¦Splits a string by a string.
    implode¦implode(string $separator, ?array $array): string¦Joins array elements with a string.
    join¦join(string $separator, ?array $array): string¦Alias of implode().
    sprintf¦sprintf(string $format, mixed ...$values): string¦Returns a formatted string.
    printf¦printf(string $format, mixed ...$values): int¦Outputs a formatted string.
    number_format¦number_format(float $num, int $decimals = 0, ?string $decimal_separator = ".", ?string $thousands_separator = ","): string¦Formats a number with grouped thousands.
    nl2br¦nl2br(string $string, bool $use_xhtml = true): string¦Inserts HTML line breaks before all newlines.
    htmlspecialchars¦htmlspecialchars(string $string, int $flags = ENT_QUOTES, ?string $encoding = null, bool $double_encode = true): string¦Converts special characters to HTML entities.
    strip_tags¦strip_tags(string $string, array|string|null $allowed_tags = null): string¦Strips HTML and PHP tags from a string.
    addslashes¦addslashes(string $string): string¦Quotes a string with slashes.
    md5¦md5(string $string, bool $binary = false): string¦Calculates the md5 hash of a string.
    sha1¦sha1(string $string, bool $binary = false): string¦Calculates the sha1 hash of a string.
    hash¦hash(string $algo, string $data, bool $binary = false, array $options = []): string¦Generates a hash value.
    password_hash¦password_hash(string $password, string|int|null $algo, array $options = []): string¦Creates a password hash.
    password_verify¦password_verify(string $password, string $hash): bool¦Verifies that a password matches a hash.
    base64_encode¦base64_encode(string $string): string¦Encodes data with MIME base64.
    base64_decode¦base64_decode(string $string, bool $strict = false): string|false¦Decodes MIME base64 data.
    uniqid¦uniqid(string $prefix = "", bool $more_entropy = false): string¦Generates a unique ID based on the current time.
    random_int¦random_int(int $min, int $max): int¦Gets a cryptographically secure random integer.
    random_bytes¦random_bytes(int $length): string¦Gets cryptographically secure random bytes.
    rand¦rand(int $min, int $max): int¦Generates a random integer.
    mt_rand¦mt_rand(int $min, int $max): int¦Generates a random value via the Mersenne Twister.
    json_encode¦json_encode(mixed $value, int $flags = 0, int $depth = 512): string|false¦Returns the JSON representation of a value.
    json_decode¦json_decode(string $json, ?bool $associative = null, int $depth = 512, int $flags = 0): mixed¦Decodes a JSON string.
    serialize¦serialize(mixed $value): string¦Generates a storable representation of a value.
    unserialize¦unserialize(string $data, array $options = []): mixed¦Creates a PHP value from a stored representation.
    var_dump¦var_dump(mixed $value, mixed ...$values): void¦Dumps information about a variable.
    var_export¦var_export(mixed $value, bool $return = false): ?string¦Outputs or returns a parsable string representation of a variable.
    print_r¦print_r(mixed $value, bool $return = false): string|bool¦Prints human-readable information about a variable.
    isset¦isset(mixed $var, mixed ...$vars): bool¦Determines if a variable is declared and is not null (language construct).
    empty¦empty(mixed $var): bool¦Determines whether a variable is empty (language construct).
    is_null¦is_null(mixed $value): bool¦Finds whether a variable is null.
    is_array¦is_array(mixed $value): bool¦Finds whether a variable is an array.
    is_string¦is_string(mixed $value): bool¦Finds whether a variable is a string.
    is_int¦is_int(mixed $value): bool¦Finds whether a variable is an integer.
    is_numeric¦is_numeric(mixed $value): bool¦Finds whether a variable is a number or a numeric string.
    is_bool¦is_bool(mixed $value): bool¦Finds out whether a variable is a boolean.
    is_float¦is_float(mixed $value): bool¦Finds whether a variable is a float.
    is_object¦is_object(mixed $value): bool¦Finds whether a variable is an object.
    is_callable¦is_callable(mixed $value, bool $syntax_only = false, string &$callable_name = null): bool¦Verifies that a value can be called as a function.
    is_a¦is_a(mixed $object_or_class, string $class, bool $allow_string = false): bool¦Checks if the object is of a given class or has it as a parent.
    intval¦intval(mixed $value, int $base = 10): int¦Gets the integer value of a variable.
    floatval¦floatval(mixed $value): float¦Gets the float value of a variable.
    strval¦strval(mixed $value): string¦Gets the string value of a variable.
    boolval¦boolval(mixed $value): bool¦Gets the boolean value of a variable.
    gettype¦gettype(mixed $value): string¦Gets the type of a variable.
    get_class¦get_class(object $object = ?): string¦Returns the name of the class of an object.
    get_object_vars¦get_object_vars(object $object): array¦Gets the properties of the given object.
    method_exists¦method_exists(object|string $object_or_class, string $method): bool¦Checks if the class method exists.
    property_exists¦property_exists(object|string $object_or_class, string $property): bool¦Checks if the object or class has a property.
    class_exists¦class_exists(string $class, bool $autoload = true): bool¦Checks if the class has been defined.
    function_exists¦function_exists(string $function): bool¦Returns true if the given function has been defined.
    defined¦defined(string $constant_name): bool¦Checks whether a given named constant exists.
    define¦define(string $constant_name, mixed $value, bool $case_insensitive = false): bool¦Defines a named constant.
    array_map¦array_map(?callable $callback, array $array, array ...$arrays): array¦Applies the callback to the elements of the given arrays.
    array_filter¦array_filter(array $array, ?callable $callback = null, int $mode = 0): array¦Filters elements of an array using a callback function.
    array_reduce¦array_reduce(array $array, callable $callback, mixed $initial = null): mixed¦Iteratively reduces the array to a single value.
    array_merge¦array_merge(array ...$arrays): array¦Merges one or more arrays.
    array_merge_recursive¦array_merge_recursive(array ...$arrays): array¦Merges one or more arrays recursively.
    array_combine¦array_combine(array $keys, array $values): array¦Creates an array by using one array for keys and another for its values.
    array_keys¦array_keys(array $array, mixed $filter_value, bool $strict = false): array¦Returns all the keys or a subset of the keys of an array.
    array_values¦array_values(array $array): array¦Returns all the values of an array.
    array_key_exists¦array_key_exists(string|int $key, array $array): bool¦Checks if the given key or index exists in the array.
    array_key_first¦array_key_first(array $array): int|string|null¦Gets the first key of an array.
    array_key_last¦array_key_last(array $array): int|string|null¦Gets the last key of an array.
    array_search¦array_search(mixed $needle, array $haystack, bool $strict = false): int|string|false¦Searches the array for a given value and returns the first key.
    in_array¦in_array(mixed $needle, array $haystack, bool $strict = false): bool¦Checks if a value exists in an array.
    array_unique¦array_unique(array $array, int $flags = SORT_STRING): array¦Removes duplicate values from an array.
    array_reverse¦array_reverse(array $array, bool $preserve_keys = false): array¦Returns an array with elements in reverse order.
    array_slice¦array_slice(array $array, int $offset, ?int $length = null, bool $preserve_keys = false): array¦Extracts a slice of the array.
    array_splice¦array_splice(array &$array, int $offset, ?int $length = null, mixed $replacement = []): array¦Removes a portion of the array and replaces it.
    array_diff¦array_diff(array $array, array ...$arrays): array¦Computes the difference of arrays.
    array_intersect¦array_intersect(array $array, array ...$arrays): array¦Computes the intersection of arrays.
    array_diff_key¦array_diff_key(array $array, array ...$arrays): array¦Computes the difference of arrays using keys for comparison.
    array_flip¦array_flip(array $array): array¦Exchanges all keys with their associated values.
    array_column¦array_column(array $array, int|string|null $column_key, int|string|null $index_key = null): array¦Returns the values from a single column of the input array.
    array_chunk¦array_chunk(array $array, int $length, bool $preserve_keys = false): array¦Splits an array into chunks.
    array_fill¦array_fill(int $start_index, int $count, mixed $value): array¦Fills an array with values.
    array_pad¦array_pad(array $array, int $length, mixed $value): array¦Pads array to the specified length with a value.
    array_sum¦array_sum(array $array): int|float¦Calculates the sum of values in an array.
    array_product¦array_product(array $array): int|float¦Calculates the product of values in an array.
    array_push¦array_push(array &$array, mixed ...$values): int¦Pushes one or more elements onto the end of the array.
    array_pop¦array_pop(array &$array): mixed¦Pops the element off the end of the array.
    array_shift¦array_shift(array &$array): mixed¦Shifts an element off the beginning of the array.
    array_unshift¦array_unshift(array &$array, mixed ...$values): int¦Prepends elements to the beginning of an array.
    array_walk¦array_walk(array|object &$array, callable $callback, mixed $arg): bool¦Applies a user-supplied function to every member of an array.
    array_is_list¦array_is_list(array $array): bool¦Checks whether a given array is a list.
    range¦range(string|int|float $start, string|int|float $end, int|float $step = 1): array¦Creates an array containing a range of elements.
    compact¦compact(array|string $var_name, array|string ...$var_names): array¦Creates an array from variables and their values.
    extract¦extract(array &$array, int $flags = EXTR_OVERWRITE, string $prefix = ""): int¦Imports variables into the current symbol table from an array.
    sort¦sort(array &$array, int $flags = SORT_REGULAR): bool¦Sorts an array in ascending order.
    rsort¦rsort(array &$array, int $flags = SORT_REGULAR): bool¦Sorts an array in descending order.
    usort¦usort(array &$array, callable $callback): bool¦Sorts an array by values using a user-defined comparison function.
    uasort¦uasort(array &$array, callable $callback): bool¦Sorts an array with a user-defined comparison function, preserving keys.
    ksort¦ksort(array &$array, int $flags = SORT_REGULAR): bool¦Sorts an array by key in ascending order.
    asort¦asort(array &$array, int $flags = SORT_REGULAR): bool¦Sorts an array in ascending order and maintains index association.
    shuffle¦shuffle(array &$array): bool¦Shuffles an array.
    min¦min(mixed $value, mixed ...$values): mixed¦Finds the lowest value.
    max¦max(mixed $value, mixed ...$values): mixed¦Finds the highest value.
    abs¦abs(int|float $num): int|float¦Absolute value.
    ceil¦ceil(int|float $num): float¦Rounds fractions up.
    floor¦floor(int|float $num): float¦Rounds fractions down.
    round¦round(int|float $num, int $precision = 0, int $mode = PHP_ROUND_HALF_UP): float¦Rounds a float.
    sqrt¦sqrt(float $num): float¦Square root.
    pow¦pow(mixed $num, mixed $exponent): int|float|object¦Exponential expression.
    intdiv¦intdiv(int $num1, int $num2): int¦Integer division.
    fmod¦fmod(float $num1, float $num2): float¦Returns the floating point remainder of the division of the arguments.
    time¦time(): int¦Returns the current Unix timestamp.
    microtime¦microtime(bool $as_float = false): string|float¦Returns the current Unix timestamp with microseconds.
    date¦date(string $format, ?int $timestamp = null): string¦Formats a Unix timestamp as a date string.
    strtotime¦strtotime(string $datetime, ?int $baseTimestamp = null): int|false¦Parses an English textual datetime description into a Unix timestamp.
    mktime¦mktime(int $hour, ?int $minute = null, ?int $second = null, ?int $month = null, ?int $day = null, ?int $year = null): int|false¦Gets the Unix timestamp for a date.
    checkdate¦checkdate(int $month, int $day, int $year): bool¦Validates a Gregorian date.
    date_default_timezone_set¦date_default_timezone_set(string $timezoneId): bool¦Sets the default timezone.
    usleep¦usleep(int $microseconds): void¦Delays execution in microseconds.
    sleep¦sleep(int $seconds): int¦Delays execution.
    file_get_contents¦file_get_contents(string $filename, bool $use_include_path = false, ?resource $context = null, int $offset = 0, ?int $length = null): string|false¦Reads an entire file into a string.
    file_put_contents¦file_put_contents(string $filename, mixed $data, int $flags = 0, ?resource $context = null): int|false¦Writes data to a file.
    file_exists¦file_exists(string $filename): bool¦Checks whether a file or directory exists.
    is_file¦is_file(string $filename): bool¦Tells whether the filename is a regular file.
    is_dir¦is_dir(string $filename): bool¦Tells whether the filename is a directory.
    mkdir¦mkdir(string $directory, int $permissions = 0777, bool $recursive = false, ?resource $context = null): bool¦Makes a directory.
    unlink¦unlink(string $filename, ?resource $context = null): bool¦Deletes a file.
    basename¦basename(string $path, string $suffix = ""): string¦Returns the trailing name component of a path.
    dirname¦dirname(string $path, int $levels = 1): string¦Returns a parent directory's path.
    pathinfo¦pathinfo(string $path, int $flags = PATHINFO_ALL): array|string¦Returns information about a file path.
    realpath¦realpath(string $path): string|false¦Returns canonicalized absolute pathname.
    glob¦glob(string $pattern, int $flags = 0): array|false¦Finds pathnames matching a pattern.
    fopen¦fopen(string $filename, string $mode, bool $use_include_path = false, ?resource $context = null): resource|false¦Opens a file or URL.
    fclose¦fclose(resource $stream): bool¦Closes an open file pointer.
    preg_match¦preg_match(string $pattern, string $subject, array &$matches = null, int $flags = 0, int $offset = 0): int|false¦Performs a regular expression match.
    preg_match_all¦preg_match_all(string $pattern, string $subject, array &$matches = null, int $flags = 0, int $offset = 0): int|false¦Performs a global regular expression match.
    preg_replace¦preg_replace(string|array $pattern, string|array $replacement, string|array $subject, int $limit = -1, int &$count = null): string|array|null¦Performs a regular expression search and replace.
    preg_replace_callback¦preg_replace_callback(string|array $pattern, callable $callback, string|array $subject, int $limit = -1, int &$count = null, int $flags = 0): string|array|null¦Performs a regular expression search and replace using a callback.
    preg_split¦preg_split(string $pattern, string $subject, int $limit = -1, int $flags = 0): array|false¦Splits a string by a regular expression.
    preg_quote¦preg_quote(string $str, ?string $delimiter = null): string¦Quotes regular expression characters.
    call_user_func¦call_user_func(callable $callback, mixed ...$args): mixed¦Calls the callback given by the first parameter.
    call_user_func_array¦call_user_func_array(callable $callback, array $args): mixed¦Calls a callback with an array of parameters.
    func_get_args¦func_get_args(): array¦Returns an array comprising a function's argument list.
    spl_autoload_register¦spl_autoload_register(?callable $callback = null, bool $throw = true, bool $prepend = false): bool¦Registers a function as an __autoload() implementation.
    iterator_to_array¦iterator_to_array(Traversable $iterator, bool $preserve_keys = true): array¦Copies the iterator into an array.
    ini_set¦ini_set(string $option, string|int|float|bool|null $value): string|false¦Sets the value of a configuration option.
    error_reporting¦error_reporting(?int $error_level = null): int¦Sets which PHP errors are reported.
    set_error_handler¦set_error_handler(?callable $callback, int $error_levels = E_ALL): callable|null¦Sets a user-defined error handler function.
    trigger_error¦trigger_error(string $message, int $error_level = E_USER_NOTICE): bool¦Generates a user-level error/warning/notice message.
    error_log¦error_log(string $message, int $message_type = 0, ?string $destination = null, ?string $additional_headers = null): bool¦Sends an error message to the defined error handling routines.
    exit¦exit(string|int $status = 0): never¦Outputs a message and terminates the current script (language construct).
    die¦die(string|int $status = 0): never¦Equivalent to exit.
    header¦header(string $header, bool $replace = true, int $response_code = 0): void¦Sends a raw HTTP header.
    http_build_query¦http_build_query(array|object $data, string $numeric_prefix = "", ?string $arg_separator = null, int $encoding_type = PHP_QUERY_RFC1738): string¦Generates URL-encoded query string.
    parse_url¦parse_url(string $url, int $component = -1): int|string|array|null|false¦Parses a URL and returns its components.
    urlencode¦urlencode(string $string): string¦URL-encodes a string.
    filter_var¦filter_var(mixed $value, int $filter = FILTER_DEFAULT, array|int $options = 0): mixed¦Filters a variable with a specified filter.
    ctype_digit¦ctype_digit(mixed $text): bool¦Checks for numeric characters.
    mb_strtolower¦mb_strtolower(string $string, ?string $encoding = null): string¦Makes a string lowercase (multibyte).
    mb_strtoupper¦mb_strtoupper(string $string, ?string $encoding = null): string¦Makes a string uppercase (multibyte).
    mb_str_split¦mb_str_split(string $string, int $length = 1, ?string $encoding = null): array¦Splits a multibyte string into an array.
    iconv¦iconv(string $from_encoding, string $to_encoding, string $string): string|false¦Converts a string from one character encoding to another.
    """
}
