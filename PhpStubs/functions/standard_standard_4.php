<?php

/**
 * Get the last occurred error
 * @return array|null an associative array describing the last error with keys "type", "message", "file" and "line". Returns null if there hasn't been an error yet.
 */
function error_get_last(): ?array {}

/**
 * Call the callback given by the first parameter
 * @param callable $callback The function to be called. Class methods may also be invoked statically using this function by passing array($classname, $methodname) to this parameter. Additionally class methods of an object instance may be called by passing array($objectinstance, $methodname) to this ...
 * @param mixed ...$args [optional] Zero or more parameters to be passed to the function. Note that the parameters for call_user_func are not passed by reference. call_user_func example and references
 * @return mixed the function result, or false on error.
 */
function call_user_func(callable $callback, mixed ...$args): mixed {}

/**
 * Call a callback with an array of parameters
 * @param callable $callback The function to be called.
 * @param array $args The parameters to be passed to the function, as an indexed array.
 * @return mixed the function result, or false on error.
 */
function call_user_func_array(callable $callback, array $args): mixed {}

/**
 * Call a user method on an specific object
 * @param string $method_name The method name being called.
 * @param object &$obj The object that method_name is being called on.
 * @param mixed ...$parameter [optional]
 * @return mixed
 * @removed 7.0
 * @see call_user_func()
 * @deprecated use call_user_func() instead
 */
function call_user_method(string $method_name, object &$obj, ...$parameter): mixed {}

/**
 * Call a user method given with an array of parameters
 * @param string $method_name The method name being called.
 * @param object &$obj The object that method_name is being called on.
 * @param array $params An array of parameters.
 * @return mixed
 * @removed 7.0
 * @see call_user_func()
 * @deprecated use call_user_func() instead
 */
function call_user_method_array(string $method_name, object &$obj, array $params): mixed {}

/**
 * Call a static method
 * @param callable $callback The function or method to be called. This parameter may be an array, with the name of the class, and the method, or a string, with a function name.
 * @param mixed ...$args [optional] Zero or more parameters to be passed to the function.
 * @return mixed the function result, or false on error.
 */
function forward_static_call(callable $callback, mixed ...$args): mixed {}

/**
 * Call a static method and pass the arguments as array
 * @param callable $callback The function or method to be called. This parameter may be an array, with the name of the class, and the method, or a string, with a function name.
 * @param array $args One parameter, gathering all the method parameter in one array. Note that the parameters for forward_static_call_array are not passed by reference.
 * @return mixed the function result, or false on error.
 */
function forward_static_call_array(callable $callback, array $args): mixed {}

/**
 * Generates a storable representation of a value
 * @param mixed $value The value to be serialized. serialize handles all types, except the resource-type. You can even serialize arrays that contain references to itself. Circular references inside the array/object you are serializing will also be stored. Any other reference will be lost. When ...
 * @return string a string containing a byte-stream representation of value that can be stored anywhere.
 */
function serialize(mixed $value): string {}

/**
 * Creates a PHP value from a stored representation
 * @param string $data The serialized string. If the variable being unserialized is an object, after successfully reconstructing the object PHP will automatically attempt to call the __wakeup member function (if it exists). unserialize_callback_func directive It's possible to set a callback-function ...
 * @param array $options [optional] Any options to be provided to unserialize(), as an associative array. The 'allowed_classes' option key may be set to a value that is either an array of class names which should be accepted, FALSE to accept no classes, or TRUE to accept all classes. If this option is ...
 * @return mixed The converted value is returned, and can be a boolean, integer, float, string, array or object. In case the passed string is not unserializeable, false is returned and E_NOTICE is issued.
 * @throws \TypeError As of PHP 8.4.0, if the allowed_classes element of options is not an array of class names, unserialize throws TypeErrors and ValueErrors.
 * @throws \ValueError As of PHP 8.4.0, if the allowed_classes element of options is not an array of class names, unserialize throws TypeErrors and ValueErrors.
 */
function unserialize(string $data, array $options = []): mixed {}

/**
 * Dumps information about a variable
 * @param mixed $value The variable you want to export.
 * @param mixed ...$values [optional]
 * @return void
 */
function var_dump(mixed $value, mixed ...$values): void {}

/**
 * Outputs or returns a parsable string representation of a variable
 * @param mixed $value The variable you want to export.
 * @param bool $return [optional] If used and set to true, var_export will return the variable representation instead of outputting it.
 * @return string|null the variable representation when the return parameter is used and evaluates to true. Otherwise, this function will return null.
 */
function var_export(mixed $value, bool $return = false): ?string {}

/**
 * Dumps a string representation of an internal zend value to output
 * @param mixed $value The variable being evaluated.
 * @param mixed ...$values The other variable being evaluated.
 * @return void No value is returned.
 */
function debug_zval_dump(
    mixed $value,
    mixed ...$values
): void {}

/**
 * Prints human-readable information about a variable
 * @param mixed $value The expression to be printed.
 * @param bool $return [optional] If you would like to capture the output of print_r, use the return parameter. If this parameter is set to true, print_r will return its output, instead of printing it (which it does by default).
 * @return string|bool If given a string, integer or float, the value itself will be printed. If given an array, values will be presented in a format that shows keys and elements. Similar notation is used for objects.
 */
function print_r(mixed $value, bool $return = false): string|bool {}

/**
 * Returns the amount of memory allocated to PHP
 * @param bool $real_usage [optional] Set this to true to get the real size of memory allocated from system. If not set or false only the memory used by emalloc() is reported.
 * @return int the memory amount in bytes.
 */
function memory_get_usage(bool $real_usage = false): int {}

/**
 * Returns the peak of memory allocated by PHP
 * @param bool $real_usage [optional] Set this to true to get the real size of memory allocated from system. If not set or false only the memory used by emalloc() is reported.
 * @return int the memory peak in bytes.
 */
function memory_get_peak_usage(bool $real_usage = false): int {}

/**
 * Reset the peak memory usage
 *
 * Resets the peak memory usage returned by the memory_get_peak_usage function.
 * @since 8.2
 */
function memory_reset_peak_usage(): void {}

/**
 * Register a function for execution on shutdown
 * @param callable $callback The shutdown function to register. The shutdown functions are called as the part of the request so that it's possible to send the output from them. There is currently no way to process the data with output buffering functions in the shutdown function. Shutdown functions ...
 * @param mixed ...$args [optional] It is possible to pass parameters to the shutdown function by passing additional parameters.
 */
function register_shutdown_function(callable $callback, mixed ...$args): void {}

/**
 * Register a function for execution on each tick
 * @param callable $callback The function name as a string, or an array consisting of an object and a method.
 * @param mixed ...$args [optional]
 * @return bool true on success or false on failure.
 */
function register_tick_function(callable $callback, mixed ...$args): bool {}

/**
 * De-register a function for execution on each tick
 * @param callable $callback The function name as a string, or an array consisting of an object and a method.
 * @return void No value is returned.
 */
function unregister_tick_function(callable $callback): void {}

/**
 * Syntax highlighting of a file
 * @param string $filename Path to the PHP file to be highlighted.
 * @param bool $return [optional] Set this parameter to true to make this function return the highlighted code.
 * @return string|bool If return is set to true, returns the highlighted code as a string instead of printing it out. Otherwise, it will return true on success, false on failure.
 */
function highlight_file(string $filename, bool $return = false): string|bool {}

/**
 * Alias:
 * highlight_file
 * @param string $filename
 * @param bool $return [optional]
 * @return string|bool
 */
function show_source(string $filename, bool $return = false): string|bool {}

/**
 * Syntax highlighting of a string
 * @param string $string The PHP code to be highlighted. This should include the opening tag.
 * @param bool $return [optional] Set this parameter to true to make this function return the highlighted code.
 * @return string|bool If return is set to true, returns the highlighted code as a string instead of printing it out. Otherwise, it will return true on success, false on failure.
 */
function highlight_string(string $string, bool $return = false): string|bool {}

/**
 * Get the system's high resolution time
 * @param bool $as_number Whether the high resolution time should be returned as array or number.
 * @since 7.3
 * @return int[]|int|float|false Returns an array of integers in the form [seconds, nanoseconds], if the parameter get_as_number is false. Otherwise the nanoseconds are returned as integer (64bit platforms) or float (32bit platforms).
 */
function hrtime(bool $as_number = false): array|int|float|false {}

/**
 * Return source with stripped comments and whitespace
 * @param string $filename Path to the PHP file.
 * @return string The stripped source code will be returned on success, or an empty string on failure. This function works as described as of PHP 5.0.1. Before this it would only return an empty string. For more information on this bug and its prior behavior, see bug report #29606.
 */
function php_strip_whitespace(string $filename): string {}

/**
 * Gets the value of a configuration option
 * @param string $option The configuration option name.
 * @return string|false the value of the configuration option as a string on success, or an empty string on failure or for null values.
 */
function ini_get(string $option): string|false {}

/**
 * Gets all configuration options
 * @param string|null $extension [optional] An optional extension name. If set, the function return only options specific for that extension.
 * @param bool $details [optional] Retrieve details settings or only the current value for each setting. Default is true (retrieve details).
 * @return array|false an associative array with directive name as the array key. When details is true (default) the array will contain global_value (set in "php.ini"), local_value (perhaps set with ini_set or ".htaccess"), and access (the access level). When details is false the value will be the ...
 */
function ini_get_all(?string $extension = null, bool $details = true): array|false {}

/**
 * Sets the value of a configuration option
 * @param string $option Not all the available options can be changed using ini_set. There is a list of all available options in the appendix.
 * @param string $value The new value for the option.
 * @return string|false the old value on success, false on failure.
 */
function ini_set(string $option, string|int|float|bool|null $value): string|false {}

/**
 * Alias:
 * ini_set
 * @param string $option
 * @param string $value
 * @return string|false
 */
function ini_alter(string $option, string|int|float|bool|null $value): string|false {}

/**
 * Restores the value of a configuration option
 * @param string $option The configuration option name.
 * @return void No value is returned.
 */
function ini_restore(string $option): void {}

/**
 * Get interpreted size from ini shorthand syntax
 *
 * Returns the interpreted size in bytes on success from an ini shorthand.
 * @param string $shorthand Ini shorthand to parse, must be a number followed by an optional multiplier. The following multipliers are supported: k/K (1024), m/M (1048576), g/G (1073741824). The number can be a decimal, hex (prefixed with 0x or 0X), octal (prefixed with 0o, 0O or 0) or binary ...
 * @return int Returns the interpreted size in bytes as an integer.
 * @since 8.2
 */
function ini_parse_quantity(string $shorthand): int {}

/**
 * Gets the current include_path configuration option
 * @return string|false the path, as a string.
 */
function get_include_path(): string|false {}

/**
 * Sets the include_path configuration option
 * @param string $include_path The new value for the include_path
 * @return string|false the old include_path on success or false on failure.
 */
function set_include_path(string $include_path): string|false {}

/**
 * Restores the value of the include_path configuration option
 * @return void No value is returned.
 * @removed 8.0
 * @deprecated
 */
function restore_include_path() {}

/**
 * Send a cookie
 * @param string $name The name of the cookie.
 * @param string $value [optional] The value of the cookie. This value is stored on the clients computer; do not store sensitive information. Assuming the name is 'cookiename', this value is retrieved through $_COOKIE['cookiename']
 * @param int $expires_or_options [optional] The time the cookie expires. This is a Unix timestamp so is in number of seconds since the epoch. In other words, you'll most likely set this with the time function plus the number of seconds before you want it to expire. Or you might use mktime. ...
 * @param string $path [optional] The path on the server in which the cookie will be available on. If set to '/', the cookie will be available within the entire domain. If set to '/foo/', the cookie will only be available within the /foo/ directory and all sub-directories such as /foo/bar/ of domain. ...
 * @param string $domain [optional] The domain that the cookie is available. To make the cookie available on all subdomains of example.com then you'd set it to '.example.com'. The . is not required but makes it compatible with more browsers. Setting it to www.example.com will make the cookie only ...
 * @param bool $secure [optional] Indicates that the cookie should only be transmitted over a secure HTTPS connection from the client. When set to true, the cookie will only be set if a secure connection exists. On the server-side, it's on the programmer to send this kind of cookie only on secure ...
 * @param bool $httponly [optional] When true the cookie will be made accessible only through the HTTP protocol. This means that the cookie won't be accessible by scripting languages, such as JavaScript. This setting can effectively help to reduce identity theft through XSS attacks (although it is not ...
 * @return bool If output exists prior to calling this function, setcookie will fail and return false. If setcookie successfully runs, it will return true. This does not indicate whether the user accepted the cookie. Example: $value = 'something from somewhere'; setcookie("TestCookie", $value); ...
 */
function setcookie(string $name, string $value = "", int $expires_or_options = 0, string $path = "", string $domain = "", bool $secure = false, bool $httponly = false): bool {}

/**
 * Send a cookie without urlencoding the cookie value
 * @param string $name
 * @param string $value [optional]
 * @param int $expires_or_options [optional]
 * @param string $path [optional]
 * @param string $domain [optional]
 * @param bool $secure [optional]
 * @param bool $httponly [optional]
 * @return bool true on success or false on failure.
 */
function setrawcookie(string $name, $value = '', $expires_or_options = 0, $path = "", $domain = "", $secure = false, $httponly = false): bool {}

/**
 * Send a raw HTTP header
 * @param string $header The header string. There are two special-case header calls. The first is a header that starts with the string "HTTP/" (case is not significant), which will be used to figure out the HTTP status code to send. For example, if you have configured Apache to use a PHP script to ...
 * @param bool $replace [optional] The optional replace parameter indicates whether the header should replace a previous similar header, or add a second header of the same type. By default it will replace, but if you pass in false as the second argument you can force multiple headers of the same type. ...
 * @param int $response_code Forces the HTTP response code to the specified value. Note that this parameter only has an effect if the header is not empty.
 * @return void No value is returned.
 */
function header(string $header, bool $replace = true, int $response_code = 0): void {}

/**
 * Remove previously set headers
 * @param string|null $name [optional] The header name to be removed. This parameter is case-insensitive.
 * @return void No value is returned.
 */
function header_remove(?string $name = null): void {}

/**
 * Checks if or where headers have been sent
 * @param string &$filename [optional] If the optional file and line parameters are set, headers_sent will put the PHP source file name and line number where output started in the file and line variables.
 * @param int &$line [optional] The line number where the output started.
 * @return bool headers_sent will return false if no HTTP headers have already been sent or true otherwise.
 */
function headers_sent(&$filename = null, &$line = null): bool {}

/**
 * Returns a list of response headers sent (or ready to send)
 * @return array a numerically indexed array of headers.
 */
function headers_list(): array {}

/**
 * Fetches all HTTP request headers from the current request
 * @return array|false An associative array of all the HTTP headers in the current request, or FALSE on failure.
 */
function apache_request_headers(): false|array {}

/**
 * Fetches all HTTP headers from the current request.
 * This function is an alias for apache_request_headers(). Please read the apache_request_headers() documentation for more information on how this function works.
 * @return array|false An associative array of all the HTTP headers in the current request, or FALSE on failure.
 */
function getallheaders(): false|array {}

/**
 * Check whether client disconnected
 * @return int 1 if client disconnected, 0 otherwise.
 */
function connection_aborted(): int {}

/**
 * Returns connection status bitfield
 * @return int the connection status bitfield, which can be used against the CONNECTION_XXX constants to determine the connection status.
 */
function connection_status(): int {}

/**
 * Set whether a client disconnect should abort script execution
 * @param bool|null $enable [optional] If set, this function will set the ignore_user_abort ini setting to the given value. If not, this function will only return the previous setting without changing it.
 * @return int the previous setting, as an integer.
 */
function ignore_user_abort(?bool $enable = null): int {}

/**
 * Parse a configuration file
 * @param string $filename The filename of the ini file being parsed.
 * @param bool $process_sections [optional] By setting the process_sections parameter to true, you get a multidimensional array, with the section names and settings included. The default for process_sections is false
 * @param int $scanner_mode [optional] Can either be INI_SCANNER_NORMAL (default) or INI_SCANNER_RAW. If INI_SCANNER_RAW is supplied, then option values will not be parsed. As of PHP 5.6.1 can also be specified as INI_SCANNER_TYPED. In this mode boolean, null and integer types are preserved when ...
 * @return array|false The settings are returned as an associative array on success, and false on failure.
 */
function parse_ini_file(string $filename, bool $process_sections = false, int $scanner_mode = INI_SCANNER_NORMAL): array|false {}

/**
 * Parse a configuration string
 * @param string $ini_string The contents of the ini file being parsed.
 * @param bool $process_sections [optional] By setting the process_sections parameter to true, you get a multidimensional array, with the section names and settings included. The default for process_sections is false
 * @param int $scanner_mode [optional] Can either be INI_SCANNER_NORMAL (default) or INI_SCANNER_RAW. If INI_SCANNER_RAW is supplied, then option values will not be parsed.
 * @return array|false The settings are returned as an associative array on success, and false on failure.
 */
function parse_ini_string(string $ini_string, bool $process_sections = false, int $scanner_mode = INI_SCANNER_NORMAL): array|false {}

/**
 * Tells whether the file was uploaded via HTTP POST
 * @param string $filename The filename being checked.
 * @return bool true on success or false on failure.
 */
function is_uploaded_file(string $filename): bool {}

/**
 * Moves an uploaded file to a new location
 * @param string $from The filename of the uploaded file.
 * @param string $to The destination of the moved file.
 * @return bool If filename is not a valid upload file, then no action will occur, and move_uploaded_file will return false. If filename is a valid upload file, but cannot be moved for some reason, no action will occur, and move_uploaded_file will return false. Additionally, a warning will be issued.
 */
function move_uploaded_file(string $from, string $to): bool {}

/**
 * Get network interfaces
 *
 * Returns an enumeration of network interfaces (adapters) on the local machine.
 * @return array|false Returns an associative array where the key is the name of the interface and the value an associative array of interface attributes, or false on failure. Each interface associative array contains: Interface attributes Name Description description Optional string value for ...
 * @since 7.3
 */
function net_get_interfaces(): array|false {}

/**
 * Get the Internet host name corresponding to a given IP address
 * @param string $ip The host IP address.
 * @return string|false the host name or the unmodified ip_address on failure.
 */
function gethostbyaddr(string $ip): string|false {}

/**
 * Get the IPv4 address corresponding to a given Internet host name
 * @param string $hostname The host name.
 * @return string the IPv4 address or a string containing the unmodified hostname on failure.
 */
function gethostbyname(string $hostname): string {}

/**
 * Get a list of IPv4 addresses corresponding to a given Internet host
 * name
 * @param string $hostname The host name.
 * @return array|false an array of IPv4 addresses or false if hostname could not be resolved.
 */
function gethostbynamel(string $hostname): array|false {}

/**
 * Gets the host name
 * @return string|false a string with the hostname on success, otherwise false is returned.
 */
function gethostname(): string|false {}

/**
 * Alias:
 * checkdnsrr
 * @param string $hostname host may either be the IP address in dotted-quad notation or the host name.
 * @param string $type [optional] type may be any one of: A, MX, NS, SOA, PTR, CNAME, AAAA, A6, SRV, NAPTR, TXT or ANY.
 * @return bool Returns TRUE if any records are found; returns FALSE if no records were found or if an error occurred.
 */
function dns_check_record(string $hostname, string $type = 'MX'): bool {}

/**
 * Check DNS records corresponding to a given Internet host name or IP address
 * @param string $hostname host may either be the IP address in dotted-quad notation or the host name.
 * @param string $type [optional] type may be any one of: A, MX, NS, SOA, PTR, CNAME, AAAA, A6, SRV, NAPTR, TXT or ANY.
 * @return bool true if any records are found; returns false if no records were found or if an error occurred.
 */
function checkdnsrr(string $hostname, string $type = 'MX'): bool {}

/**
 * Alias:
 * getmxrr
 * @param string $hostname
 * @param array &$hosts
 * @param array &$weights [optional]
 * @return bool
 */
function dns_get_mx(string $hostname, &$hosts, &$weights = null): bool {}

/**
 * Get MX records corresponding to a given Internet host name
 * @param string $hostname The Internet host name.
 * @param array &$hosts A list of the MX records found is placed into the array mxhosts.
 * @param array &$weights [optional] If the weight array is given, it will be filled with the weight information gathered.
 * @return bool true if any records are found; returns false if no records were found or if an error occurred.
 */
function getmxrr(string $hostname, &$hosts, &$weights = null): bool {}

/**
 * Fetch DNS Resource Records associated with a hostname
 * @param string $hostname hostname should be a valid DNS hostname such as "www.example.com". Reverse lookups can be generated using in-addr.arpa notation, but gethostbyaddr is more suitable for the majority of reverse lookups. Per DNS standards, email addresses are given in user.host format (for ...
 * @param int $type [optional] By default, dns_get_record will search for any resource records associated with hostname. To limit the query, specify the optional type parameter. May be any one of the following: DNS_A, DNS_CNAME, DNS_HINFO, DNS_MX, DNS_NS, DNS_PTR, DNS_SOA, DNS_TXT, DNS_AAAA, DNS_SRV, ...
 * @param array &$authoritative_name_servers [optional] Passed by reference and, if given, will be populated with Resource Records for the Authoritative Name Servers.
 * @param array &$additional_records [optional] Passed by reference and, if given, will be populated with any Additional Records.
 * @param bool $raw [optional] In case of raw mode, we query only the requested type instead of looping type by type before going with the additional info stuff.
 * @return array|false This function returns an array of associative arrays. Each associative array contains at minimum the following keys: Basic DNS attributes Attribute Meaning host The record in the DNS namespace to which the rest of the associated data refers. class dns_get_record only returns ...
 */
function dns_get_record(string $hostname, int $type = DNS_ANY, &$authoritative_name_servers = null, &$additional_records = null, bool $raw = false): array|false {}
