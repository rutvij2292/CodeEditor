<?php

/**
 * Gets time of last page modification
 * @return int|false the time of the last modification of the current page. The value returned is a Unix timestamp, suitable for feeding to date. Returns false on error.
 */
function getlastmod(): int|false {}

/**
 * Decodes data encoded with MIME base64
 * @param string $string The encoded data.
 * @param bool $strict [optional] Returns false if input contains character from outside the base64 alphabet.
 * @return string|false the original data or false on failure. The returned data may be binary.
 */
function base64_decode(string $string, bool $strict = false): string|false {}

/**
 * Encodes data with MIME base64
 * @param string $string The data to encode.
 * @return string The encoded data, as a string.
 */
function base64_encode(string $string): string {}

/**
 * Uuencode a string
 * @param string $string The data to be encoded.
 * @return string the uuencoded data.
 */
function convert_uuencode(string $string): string {}

/**
 * Decode a uuencoded string
 * @param string $string The uuencoded data.
 * @return string|false the decoded data as a string.
 */
function convert_uudecode(string $string): string|false {}

/**
 * Absolute value
 * @param int|float $num The numeric value to process
 * @return float|int The absolute value of number. If the argument number is of type float, the return type is also float, otherwise it is integer (as float usually has a bigger value range than integer).
 */
function abs(int|float $num): int|float {}

/**
 * Round fractions up
 * @param int|float $num The value to round
 * @return float|false value rounded up to the next highest integer. The return value of ceil is still of type float as the value range of float is usually bigger than that of integer.
 */
function ceil(int|float $num): float {}

/**
 * Round fractions down
 * @param int|float $num The numeric value to round
 * @return float|false value rounded to the next lowest integer. The return value of floor is still of type float because the value range of float is usually bigger than that of integer.
 */
function floor(int|float $num): float {}

/**
 * Returns the rounded value of val to specified precision (number of digits after the decimal point).
 * precision can also be negative or zero (default).
 * Note: PHP doesn't handle strings like "12,300.2" correctly by default. See converting from strings.
 * @param int|float $num The value to round
 * @param int $precision [optional] The optional number of decimal digits to round to.
 * @param int $mode [optional] One of PHP_ROUND_HALF_UP, PHP_ROUND_HALF_DOWN, PHP_ROUND_HALF_EVEN, or PHP_ROUND_HALF_ODD.
 * @return float The rounded value
 * @throws \ValueError The function throws a ValueError if mode is invalid. Prior to PHP 8.4.0, an invalid mode would silently default to PHP_ROUND_HALF_UP.
 */
function round(
    int|float $num,
    int $precision = 0,
    int $mode = 0
): float {}

/**
 * Sine
 * @param float $num A value in radians
 * @return float The sine of arg
 */
function sin(float $num): float {}

/**
 * Cosine
 * @param float $num An angle in radians
 * @return float The cosine of arg
 */
function cos(float $num): float {}

/**
 * Tangent
 * @param float $num The argument to process in radians
 * @return float The tangent of arg
 */
function tan(float $num): float {}

/**
 * Arc sine
 * @param float $num The argument to process
 * @return float The arc sine of arg in radians
 */
function asin(float $num): float {}

/**
 * Arc cosine
 * @param float $num The argument to process
 * @return float The arc cosine of arg in radians.
 */
function acos(float $num): float {}

/**
 * Arc tangent
 * @param float $num The argument to process
 * @return float The arc tangent of arg in radians.
 */
function atan(float $num): float {}

/**
 * Inverse hyperbolic tangent
 * @param float $num The argument to process
 * @return float Inverse hyperbolic tangent of arg
 */
function atanh(float $num): float {}

/**
 * Arc tangent of two variables
 * @param float $y Dividend parameter
 * @param float $x Divisor parameter
 * @return float The arc tangent of y/x in radians.
 */
function atan2(float $y, float $x): float {}

/**
 * Hyperbolic sine
 * @param float $num The argument to process
 * @return float The hyperbolic sine of arg
 */
function sinh(float $num): float {}

/**
 * Hyperbolic cosine
 * @param float $num The argument to process
 * @return float The hyperbolic cosine of arg
 */
function cosh(float $num): float {}

/**
 * Hyperbolic tangent
 * @param float $num The argument to process
 * @return float The hyperbolic tangent of arg
 */
function tanh(float $num): float {}

/**
 * Inverse hyperbolic sine
 * @param float $num The argument to process
 * @return float The inverse hyperbolic sine of arg
 */
function asinh(float $num): float {}

/**
 * Inverse hyperbolic cosine
 * @param float $num The value to process
 * @return float The inverse hyperbolic cosine of arg
 */
function acosh(float $num): float {}

/**
 * Returns exp(number) - 1, computed in a way that is accurate even
 * when the value of number is close to zero
 * @param float $num The argument to process
 * @return float 'e' to the power of arg minus one
 */
function expm1(float $num): float {}

/**
 * Returns log(1 + number), computed in a way that is accurate even when
 * the value of number is close to zero
 * @param float $num The argument to process
 * @return float log(1 + number)
 */
function log1p(float $num): float {}

/**
 * Get value of pi
 * @return float The value of pi as float.
 */
function pi(): float {}

/**
 * Finds whether a value is a legal finite number
 * @param float $num The value to check
 * @return bool true if val is a legal finite number within the allowed range for a PHP float on this platform, else false.
 */
function is_finite(float $num): bool {}

/**
 * Finds whether a value is not a number
 * @param float $num The value to check
 * @return bool true if val is 'not a number', else false.
 */
function is_nan(float $num): bool {}

/**
 * Integer division
 * @param int $num1 Number to be divided.
 * @param int $num2 Number which divides the dividend
 * @return int The integer quotient of the division of num1 by num2.
 * @since 7.0
 * @throws DivisionByZeroError if divisor is 0
 * @throws ArithmeticError if the dividend is PHP_INT_MIN and the divisor is -1
 */
function intdiv(int $num1, int $num2): int {}

/**
 * Finds whether a value is infinite
 * @param float $num The value to check
 * @return bool true if val is infinite, else false.
 */
function is_infinite(float $num): bool {}

/**
 * Exponential expression
 * @param mixed $num The base to use
 * @param mixed $exponent The exponent
 * @return object|int|float base raised to the power of exp. If the result can be represented as integer it will be returned as type integer, else it will be returned as type float. If the power cannot be computed false will be returned instead.
 */
function pow(mixed $num, mixed $exponent): object|int|float {}

/**
 * Calculates the exponent of e
 * @param float $num The argument to process
 * @return float 'e' raised to the power of arg
 */
function exp(float $num): float {}

/**
 * Natural logarithm
 * @param float $num The value to calculate the logarithm for
 * @param float $base [optional] The optional logarithmic base to use (defaults to 'e' and so to the natural logarithm).
 * @return float The logarithm of arg to base, if given, or the natural logarithm.
 */
function log(float $num, float $base = M_E): float {}

/**
 * Base-10 logarithm
 * @param float $num The argument to process
 * @return float The base-10 logarithm of arg
 */
function log10(float $num): float {}

/**
 * Square root
 * @param float $num The argument to process
 * @return float The square root of arg or the special value NAN for negative numbers.
 */
function sqrt(float $num): float {}

/**
 * Calculate the length of the hypotenuse of a right-angle triangle
 * @param float $x Length of first side
 * @param float $y Length of second side
 * @return float Calculated length of the hypotenuse
 */
function hypot(float $x, float $y): float {}

/**
 * Converts the number in degrees to the radian equivalent
 * @param float $num Angular value in degrees
 * @return float The radian equivalent of number
 */
function deg2rad(float $num): float {}

/**
 * Converts the radian number to the equivalent number in degrees
 * @param float $num A radian value
 * @return float The equivalent of number in degrees
 */
function rad2deg(float $num): float {}

/**
 * Binary to decimal
 * @param string $binary_string The binary string to convert
 * @return int|float The decimal value of binary_string
 */
function bindec(string $binary_string): int|float {}

/**
 * Hexadecimal to decimal
 * @param string $hex_string The hexadecimal string to convert
 * @return int|float The decimal representation of hex_string
 */
function hexdec(string $hex_string): int|float {}

/**
 * Octal to decimal
 * @param string $octal_string The octal string to convert
 * @return int|float The decimal representation of octal_string
 */
function octdec(string $octal_string): int|float {}

/**
 * Decimal to binary
 * @param int $num Decimal value to convert Range of inputs on 32-bit machines positive number negative number return value 0 0 1 1 2 10 ... normal progression ... 2147483646 1111111111111111111111111111110 2147483647 (largest signed integer) 1111111111111111111111111111111 (31 1's) 2147483648 ...
 * @return string Binary string representation of number
 */
function decbin(int $num): string {}

/**
 * Decimal to octal
 * @param int $num Decimal value to convert
 * @return string Octal string representation of number
 */
function decoct(int $num): string {}

/**
 * Decimal to hexadecimal
 * @param int $num Decimal value to convert
 * @return string Hexadecimal string representation of number
 */
function dechex(int $num): string {}

/**
 * Convert a number between arbitrary bases
 * @param string $num The number to convert
 * @param int $from_base The base number is in
 * @param int $to_base The base to convert number to
 * @return string number converted to base tobase
 */
function base_convert(string $num, int $from_base, int $to_base): string {}

/**
 * Format a number with grouped thousands
 * @param float $num The number being formatted.
 * @param int $decimals [optional] Sets the number of decimal points.
 * @param string|null $decimal_separator [optional]
 * @param string|null $thousands_separator [optional]
 * @return string A formatted version of number.
 */
function number_format(float $num, int $decimals = 0, ?string $decimal_separator = '.', ?string $thousands_separator = ','): string {}

/**
 * Returns the floating point remainder (modulo) of the division
 * of the arguments
 * @param float $num1 The dividend
 * @param float $num2 The divisor
 * @return float The floating point remainder of x/y
 */
function fmod(float $num1, float $num2): float {}

/**
 * Performs a floating-point division under
 * IEEE 754 semantics. Division by zero is considered well-defined and
 * will return one of Inf, -Inf or NaN.
 * @param float $num1 The dividend (numerator)
 * @param float $num2 The divisor
 * @return float The floating point result of num1/num2
 * @since 8.0
 */
function fdiv(float $num1, float $num2): float {}

/**
 * Converts a packed internet address to a human readable representation
 * @param string $ip A 32bit IPv4, or 128bit IPv6 address.
 * @return string|false a string representation of the address or false on failure.
 */
function inet_ntop(string $ip): string|false {}

/**
 * Converts a human readable IP address to its packed in_addr representation
 * @param string $ip A human readable IPv4 or IPv6 address.
 * @return string|false the in_addr representation of the given address
 */
function inet_pton(string $ip): string|false {}

/**
 * Converts a string containing an (IPv4) Internet Protocol dotted address into a long integer
 * @param string $ip A standard format address.
 * @return int|false the IPv4 address or false if ip_address is invalid.
 */
function ip2long(string $ip): int|false {}

/**
 * Converts an long integer address into a string in (IPv4) internet standard dotted format
 * @param int $ip A proper address representation.
 * @return string|false the Internet IP address as a string.
 */
function long2ip(int $ip): string|false {}

/**
 * Gets the value of an environment variable
 * @param string|null $name The variable name.
 * @param bool $local_only [optional] Set to true to only return local environment variables (set by the operating system or putenv).
 * @return string|array|false the value of the environment variable varname or an associative array with all environment variables if no variable name is provided, or false on an error.
 */
function getenv(
    ?string $name = null,
    bool $local_only = false
): array|string|false {}

/**
 * Sets the value of an environment variable
 * @param string $assignment The setting, like "FOO=BAR"
 * @return bool true on success or false on failure.
 */
function putenv(string $assignment): bool {}

/**
 * Gets options from the command line argument list
 * @param string $short_options Each character in this string will be used as option characters and matched against options passed to the script starting with a single hyphen (-). For example, an option string "x" recognizes an option -x. Only a-z, A-Z and 0-9 are allowed.
 * @param array $long_options An array of options. Each element in this array will be used as option strings and matched against options passed to the script starting with two hyphens (--). For example, an longopts element "opt" recognizes an option --opt. Prior to PHP5.3.0 this parameter was only ...
 * @param int &$rest_index [optional] If the optind parameter is present, then the index where argument parsing stopped will be written to this variable.
 * @return (string|false|string[]|false[])[]|false This function will return an array of option / argument pairs or false on failure.
 */
function getopt(
    string $short_options,
    array $long_options = [],
    &$rest_index = null
): array|false {}

/**
 * Gets system load average
 * @return array{float, float, float}|false an array with three samples (last 1, 5 and 15 minutes).
 * @since 5.1
 */
function sys_getloadavg(): array|false {}

/**
 * Return current Unix timestamp with microseconds
 * @param bool $as_float [optional] When called without the optional argument, this function returns the string "msec sec" where sec is the current time measured in the number of seconds since the Unix Epoch (0:00:00 January 1, 1970 GMT), and msec is the microseconds part. Both portions of the string ...
 * @return string|float By default, microtime returns a string in the form "msec sec", where sec is the number of seconds since the Unix epoch (0:00:00 January 1,1970 GMT), and msec measures microseconds that have elapsed since sec and is also expressed in seconds as a decimal fraction. If as_float is ...
 */
function microtime(bool $as_float = false): string|float {}

/**
 * Get current time
 * @param bool $as_float [optional] When set to true, a float instead of an array is returned.
 * @return int[]|float By default an array is returned. If return_float is set, then a float is returned. Array keys: "sec" - seconds since the Unix Epoch "usec" - microseconds "minuteswest" - minutes west of Greenwich "dsttime" - type of dst correction
 */
function gettimeofday(bool $as_float = false): array|float {}

/**
 * Gets the current resource usages
 * @param int $mode If mode is 1, getrusage will be called with RUSAGE_CHILDREN.
 * @return array|false an associative array containing the data returned from the system call. All entries are accessible by using their documented field names.
 */
function getrusage(int $mode = 0): array|false {}

/**
 * Generate a unique ID
 * @param string $prefix [optional] Can be useful, for instance, if you generate identifiers simultaneously on several hosts that might happen to generate the identifier at the same microsecond. With an empty prefix, the returned string will be 13 characters long. If more_entropy is true, it will be ...
 * @param bool $more_entropy [optional] If set to true, uniqid will add additional entropy (using the combined linear congruential generator) at the end of the return value, which should make the results more unique.
 * @return string the unique identifier, as a string.
 */
function uniqid(string $prefix = "", bool $more_entropy = false): string {}

/**
 * Convert a quoted-printable string to an 8 bit string
 * @param string $string The input string.
 * @return string the 8-bit binary string.
 */
function quoted_printable_decode(string $string): string {}

/**
 * Convert a 8 bit string to a quoted-printable string
 * @param string $string The input string.
 * @return string the encoded string.
 */
function quoted_printable_encode(string $string): string {}

/**
 * Convert from one Cyrillic character set to another
 * @param string $str The string to be converted.
 * @param string $from The source Cyrillic character set, as a single character.
 * @param string $to The target Cyrillic character set, as a single character.
 * @return string the converted string.
 * @removed 8.0
 * @see mb_convert_string()
 * @see iconv()
 * @see UConverter
 * @deprecated Us mb_convert_string(), iconv() or UConverter instead.
 */
function convert_cyr_string(string $str, string $from, string $to): string {}

/**
 * Gets the name of the owner of the current PHP script
 * @return string the username as a string.
 */
function get_current_user(): string {}

/**
 * Limits the maximum execution time
 * @param int $seconds The maximum execution time, in seconds. If set to zero, no time limit is imposed.
 * @return bool Returns TRUE on success, or FALSE on failure.
 */
function set_time_limit(int $seconds): bool {}

/**
 * Gets the value of a PHP configuration option
 * @param string $option The configuration option name.
 * @return array|string|false the current value of the PHP configuration variable specified by option, or false if an error occurs.
 */
function get_cfg_var(string $option): array|string|false {}

/**
 * Alias:
 * set_magic_quotes_runtime
 * @param bool $new_setting
 * @removed 7.0
 * @deprecated
 */
function magic_quotes_runtime(bool $new_setting) {}

/**
 * Sets the current active configuration setting of magic_quotes_runtime
 * @param bool $new_setting false for off, true for on.
 * @return bool true on success or false on failure.
 * @removed 7.0
 * @deprecated This function has been DEPRECATED as of PHP 5.4.0. Raises an E_CORE_ERROR
 */
function set_magic_quotes_runtime(bool $new_setting): bool {}

/**
 * Gets the current configuration setting of magic quotes gpc
 * @return int 0 if magic quotes gpc are off, 1 otherwise.
 * @removed 8.0
 * @deprecated
 */
function get_magic_quotes_gpc(): int {}

/**
 * Gets the current active configuration setting of magic_quotes_runtime
 * @return int 0 if magic quotes runtime is off, 1 otherwise.
 * @deprecated
 */
function get_magic_quotes_runtime(): int {}

/**
 * Import GET/POST/Cookie variables into the global scope
 * @param string $types Using the types parameter, you can specify which request variables to import. You can use 'G', 'P' and 'C' characters respectively for GET, POST and Cookie. These characters are not case sensitive, so you can also use any combination of 'g', 'p' and 'c'. POST includes the POST ...
 * @param string $prefix [optional] Variable name prefix, prepended before all variable's name imported into the global scope. So if you have a GET value named "userid", and provide a prefix "pref_", then you'll get a global variable named $pref_userid. Although the prefix parameter is optional, you ...
 * @return bool true on success or false on failure.
 * @removed 5.4
 * @deprecated This function has been DEPRECATED as of PHP 5.3.0
 */
function import_request_variables(string $types, $prefix = null): bool {}

/**
 * Send an error message to the defined error handling routines
 * @param string $message The error message that should be logged.
 * @param int $message_type Says where the error should go. The possible message types are as follows: error_log log types 0 message is sent to PHP's system logger, using the Operating System's system logging mechanism or a file, depending on what the error_log configuration directive is set to. This ...
 * @param string|null $destination [optional] The destination. Its meaning depends on the message_type parameter as described above.
 * @param string|null $additional_headers [optional] The extra headers. It's used when the message_type parameter is set to 1. This message type uses the same internal function as mail does.
 * @return bool true on success or false on failure.
 */
function error_log(string $message, int $message_type = 0, ?string $destination = null, ?string $additional_headers = null): bool {}

/**
 * Restrict a value to a given range
 * @param mixed $value
 * @param mixed $min
 * @param mixed $max
 * @return mixed
 * @since 8.6
 */
function clamp(mixed $value, mixed $min, mixed $max): mixed {}
