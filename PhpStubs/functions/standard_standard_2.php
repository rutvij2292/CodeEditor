<?php

/**
 * Query language and locale information
 * @param int $item item may be an integer value of the element or the constant name of the element. The following is a list of constant names for item that may be used and their description. Some of these constants may not be defined or hold no value for certain locales. nl_langinfo Constants ...
 * @return string|false the element as a string, or false if item is not valid.
 */
function nl_langinfo(int $item): string|false {}

/**
 * Calculate the soundex key of a string
 * @param string $string The input string.
 * @return string the soundex key as a string.
 */
function soundex(string $string): string {}

/**
 * Calculate Levenshtein distance between two strings
 * @param string $string1 One of the strings being evaluated for Levenshtein distance.
 * @param string $string2 One of the strings being evaluated for Levenshtein distance.
 * @param int $insertion_cost [optional] Defines the cost of insertion.
 * @param int $replacement_cost [optional] Defines the cost of replacement.
 * @param int $deletion_cost [optional] Defines the cost of deletion.
 * @return int This function returns the Levenshtein-Distance between the two argument strings or -1, if one of the argument strings is longer than the limit of 255 characters.
 */
function levenshtein(string $string1, string $string2, int $insertion_cost = 1, int $replacement_cost = 1, int $deletion_cost = 1): int {}

/**
 * Generate a single-byte string from a number
 * @param int $codepoint The ascii code.
 * @return string the specified character.
 */
function chr(int $codepoint): string {}

/**
 * Convert the first byte of a string to a value between 0 and 255
 * @param string $character A character.
 * @return int<0, 255> the ASCII value as an integer.
 */
function ord(string $character): int {}

/**
 * Parses the string into variables
 * @param string $string The input string.
 * @param array &$result If the second parameter arr is present, variables are stored in this variable as array elements instead. Since 7.2.0 this parameter is not optional.
 * @return void No value is returned.
 */
function parse_str(
    string $string,
    &$result
): void {}

/**
 * Parse a CSV string into an array
 * @param string $string The string to parse.
 * @param string $separator [optional] Set the field delimiter (one character only).
 * @param string $enclosure [optional] Set the field enclosure character (one character only).
 * @param string $escape [optional] Set the escape character (one character only). Defaults as a backslash (\)
 * @return array an indexed array containing the fields read.
 */
function str_getcsv(string $string, string $separator = ",", string $enclosure = '"', string $escape = "\\"): array {}

/**
 * Pad a string to a certain length with another string
 * @param string $string The input string.
 * @param int $length If the value of pad_length is negative, less than, or equal to the length of the input string, no padding takes place.
 * @param string $pad_string [optional] The pad_string may be truncated if the required number of padding characters can't be evenly divided by the pad_string's length.
 * @param int $pad_type [optional] Optional argument pad_type can be STR_PAD_RIGHT, STR_PAD_LEFT, or STR_PAD_BOTH. If pad_type is not specified it is assumed to be STR_PAD_RIGHT.
 * @return string the padded string.
 */
function str_pad(string $string, int $length, string $pad_string = " ", int $pad_type = STR_PAD_RIGHT): string {}

/**
 * Alias:
 * rtrim
 * @param string $string The input string.
 * @param string $characters [optional]
 * @return string the modified string.
 * @see rtrim()
 */
function chop(string $string, string $characters = " \n\r\t\v\0"): string {}

/**
 * Alias:
 * strstr
 * @param string $haystack The input string.
 * @param string $needle If needle is not a string, it is converted to an integer and applied as the ordinal value of a character.
 * @param bool $before_needle [optional] If TRUE, strstr() returns the part of the haystack before the first occurrence of the needle (excluding the needle).
 * @return string|false Returns the portion of string, or FALSE if needle is not found.
 */
function strchr(string $haystack, string $needle, bool $before_needle = false): string|false {}

/**
 * Return a formatted string
 * @param string $format The format string is composed of zero or more directives: ordinary characters (excluding %) that are copied directly to the result, and conversion specifications, each of which results in fetching its own parameter. This applies to both sprintf and printf. Each conversion ...
 * @param mixed ...$values
 * @return string a string produced according to the formatting string format.
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the number of arguments is zero. Prior to PHP 8.0.0, a E_WARNING was emitted instead. As of PHP 8.0.0, a ValueError is thrown if [width] is less than zero or bigger than PHP_INT_MAX. Prior to PHP 8.0.0, a E_WARNING was emitted instead. ...
 * @throws \ArgumentCountError As of PHP 8.0.0, a ArgumentCountError is thrown when less arguments are given than required. Prior to PHP 8.0.0, false was returned and a E_WARNING emitted instead.
 */
function sprintf(
    string $format,
    mixed ...$values
): string {}

/**
 * Output a formatted string
 * @param string $format See sprintf for a description of format.
 * @param string|int|float ...$values [optional]
 * @return int the length of the outputted string.
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the number of arguments is zero. Prior to PHP 8.0.0, a E_WARNING was emitted instead. As of PHP 8.0.0, a ValueError is thrown if [width] is less than zero or bigger than PHP_INT_MAX. Prior to PHP 8.0.0, a E_WARNING was emitted instead. ...
 * @throws \ArgumentCountError As of PHP 8.0.0, a ArgumentCountError is thrown when less arguments are given than required. Prior to PHP 8.0.0, false was returned and a E_WARNING emitted instead.
 */
function printf(string $format, mixed ...$values): int {}

/**
 * Output a formatted string
 * @param string $format See sprintf for a description of format.
 * @param array $values
 * @return int the length of the outputted string.
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the number of arguments is zero. Prior to PHP 8.0.0, a E_WARNING was emitted instead. As of PHP 8.0.0, a ValueError is thrown if [width] is less than zero or bigger than PHP_INT_MAX. Prior to PHP 8.0.0, a E_WARNING was emitted instead. ...
 */
function vprintf(string $format, array $values): int {}

/**
 * Return a formatted string
 * @param string $format See sprintf for a description of format.
 * @param array $values
 * @return string Return array values as a formatted string according to format (which is described in the documentation for sprintf).
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the number of arguments is zero. Prior to PHP 8.0.0, a E_WARNING was emitted instead. As of PHP 8.0.0, a ValueError is thrown if [width] is less than zero or bigger than PHP_INT_MAX. Prior to PHP 8.0.0, a E_WARNING was emitted instead. ...
 */
function vsprintf(string $format, array $values): string {}

/**
 * Write a formatted string to a stream
 * @param resource $stream &fs.file.pointer;
 * @param string $format See sprintf for a description of format.
 * @param mixed ...$values [optional]
 * @return int the length of the string written.
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the number of arguments is zero. Prior to PHP 8.0.0, a E_WARNING was emitted instead. As of PHP 8.0.0, a ValueError is thrown if [width] is less than zero or bigger than PHP_INT_MAX. Prior to PHP 8.0.0, a E_WARNING was emitted instead. ...
 * @throws \ArgumentCountError As of PHP 8.0.0, a ArgumentCountError is thrown when less arguments are given than required. Prior to PHP 8.0.0, false was returned and a E_WARNING emitted instead.
 */
function fprintf($stream, string $format, mixed ...$values): int {}

/**
 * Write a formatted string to a stream
 * @param resource $stream
 * @param string $format See sprintf for a description of format.
 * @param array $values
 * @return int the length of the outputted string.
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the number of arguments is zero. Prior to PHP 8.0.0, a E_WARNING was emitted instead. As of PHP 8.0.0, a ValueError is thrown if [width] is less than zero or bigger than PHP_INT_MAX. Prior to PHP 8.0.0, a E_WARNING was emitted instead. ...
 */
function vfprintf($stream, string $format, array $values): int {}

/**
 * Parses input from a string according to a format
 * @param string $string The input string being parsed.
 * @param string $format The interpreted format for str, which is described in the documentation for sprintf with following differences: Function is not locale-aware. F, g, G and b are not supported. D stands for decimal number. i stands for integer with base detection. n stands for number of ...
 * @param mixed &...$vars [optional]
 * @return array|int|null If only two parameters were passed to this function, the values parsed will be returned as an array. Otherwise, if optional parameters are passed, the function will return the number of assigned values. The optional parameters must be passed by reference.
 */
function sscanf(string $string, string $format, mixed &...$vars): array|int|null {}

/**
 * Parses input from a file according to a format
 * @param resource $stream &fs.file.pointer;
 * @param string $format The specified format as described in the sprintf documentation.
 * @param mixed &...$vars [optional]
 * @return array|int|false|null If only two parameters were passed to this function, the values parsed will be returned as an array. Otherwise, if optional parameters are passed, the function will return the number of assigned values. The optional parameters must be passed by reference.
 */
function fscanf($stream, string $format, mixed &...$vars): array|int|false|null {}

/**
 * Parse a URL and return its components
 * @param string $url The URL to parse. Invalid characters are replaced by _.
 * @param int $component [optional] Specify one of PHP_URL_SCHEME, PHP_URL_HOST, PHP_URL_PORT, PHP_URL_USER, PHP_URL_PASS, PHP_URL_PATH, PHP_URL_QUERY or PHP_URL_FRAGMENT to retrieve just a specific URL component as a string.
 * @return array|string|int|null|false On seriously malformed URLs, parse_url() may return FALSE. If the component parameter is omitted, an associative array is returned. At least one element will be present within the array. Potential keys within this array are: scheme - e.g. http host port user pass ...
 */
function parse_url(string $url, int $component = -1): array|string|int|false|null {}

/**
 * URL-encodes string
 * @param string $string The string to be encoded.
 * @return string a string in which all non-alphanumeric characters except -_. have been replaced with a percent (%) sign followed by two hex digits and spaces encoded as plus (+) signs. It is encoded the same way that the posted data from a WWW form is encoded, that is the same way as in ...
 */
function urlencode(string $string): string {}

/**
 * Decodes URL-encoded string
 * @param string $string The string to be decoded.
 * @return string the decoded string.
 */
function urldecode(string $string): string {}

/**
 * URL-encode according to RFC 3986
 * @param string $string The URL to be encoded.
 * @return string a string in which all non-alphanumeric characters except -_. have been replaced with a percent (%) sign followed by two hex digits. This is the encoding described in RFC 1738 for protecting literal characters from being interpreted as special URL delimiters, and for protecting URLs ...
 */
function rawurlencode(string $string): string {}

/**
 * Decode URL-encoded strings
 * @param string $string The URL to be decoded.
 * @return string the decoded URL, as a string.
 */
function rawurldecode(string $string): string {}

/**
 * Generate URL-encoded query string
 * @param object|array $data May be an array or object containing properties. If query_data is an array, it may be a simple one-dimensional structure, or an array of arrays (which in turn may contain other arrays). If query_data is an object, then only public properties will be incorporated into the ...
 * @param string $numeric_prefix [optional] If numeric indices are used in the base array and this parameter is provided, it will be prepended to the numeric index for elements in the base array only. This is meant to allow for legal variable names when the data is decoded by PHP or another CGI ...
 * @param string|null $arg_separator arg_separator.output is used to separate arguments, unless this parameter is specified, and is then used.
 * @param int $encoding_type By default, PHP_QUERY_RFC1738. If enc_type is PHP_QUERY_RFC1738, then encoding is performed per » RFC 1738 and the application/x-www-form-urlencoded media type, which implies that spaces are encoded as plus (+) signs. If enc_type is PHP_QUERY_RFC3986, then encoding is ...
 * @return string a URL-encoded string.
 */
function http_build_query(object|array $data, string $numeric_prefix = "", ?string $arg_separator = null, int $encoding_type = PHP_QUERY_RFC1738): string {}

/**
 * Returns the target of a symbolic link
 * @param string $path The symbolic link path.
 * @return string|false the contents of the symbolic link path or false on error.
 */
function readlink(string $path): string|false {}

/**
 * Gets information about a link
 * @param string $path Path to the link.
 * @return int|false linkinfo returns the st_dev field of the Unix C stat structure returned by the lstat system call. Returns 0 or false in case of error.
 */
function linkinfo(string $path): int|false {}

/**
 * Creates a symbolic link
 * @param string $target Target of the link.
 * @param string $link The link name.
 * @return bool true on success or false on failure.
 */
function symlink(string $target, string $link): bool {}

/**
 * Create a hard link
 * @param string $target Target of the link.
 * @param string $link The link name.
 * @return bool true on success or false on failure.
 */
function link(string $target, string $link): bool {}

/**
 * Deletes a file
 * @param string $filename Path to the file.
 * @param resource $context [optional]
 * @return bool true on success or false on failure.
 */
function unlink(string $filename, $context = null): bool {}

/**
 * Execute an external program
 * @param string $command The command that will be executed.
 * @param array &$output [optional] If the output argument is present, then the specified array will be filled with every line of output from the command. Trailing whitespace, such as \n, is not included in this array. Note that if the array already contains some elements, exec will append to the end ...
 * @param int &$result_code [optional] If the result_code argument is present along with the output argument, then the return status of the executed command will be written to this variable.
 * @return string|false The last line from the result of the command. If you need to execute a command and have all the data from the command passed directly back without any interference, use the passthru function. To get the output of the executed command, be sure to set and use the output parameter.
 * @throws \ValueError Emits an E_WARNING if exec is unable to execute the command. Throws a ValueError if command is empty or contains null bytes.
 */
function exec(string $command, &$output = null, &$result_code = null): string|false {}

/**
 * Execute an external program and display the output
 * @param string $command The command that will be executed.
 * @param int &$result_code [optional] If the result_code argument is present, then the return status of the executed command will be written to this variable.
 * @return string|false the last line of the command output on success, and false on failure.
 */
function system(string $command, &$result_code = null): string|false {}

/**
 * Escape shell metacharacters
 * @param string $command The command that will be escaped.
 * @return string The escaped string.
 */
function escapeshellcmd(string $command): string {}

/**
 * Escape a string to be used as a shell argument
 * @param string $arg The argument that will be escaped.
 * @return string The escaped string.
 */
function escapeshellarg(string $arg): string {}

/**
 * Execute an external program and display raw output
 * @param string $command The command that will be executed.
 * @param int &$result_code [optional] If the result_code argument is present, the return status of the Unix command will be placed here.
 * @return bool|null null on success or false on failure.
 * @throws \ValueError Will emit an E_WARNING if passthru is unable to execute the command. Throws a ValueError if command is empty or contains null bytes.
 */
function passthru(string $command, &$result_code = null): null|false {}

/**
 * Execute command via shell and return the complete output as a string
 * @param string $command The command that will be executed.
 * @return string|false|null A string containing the output from the executed command, false if the pipe cannot be established or null if an error occurs or the command produces no output.
 */
function shell_exec(string $command): string|false|null {}

/**
 * Execute a command and open file pointers for input/output
 * @param array|string $command Execute a command and open file pointers for input/output As of PHP 7.4.0, cmd may be passed as array of command parameters. In this case the process will be opened directly (without going through a shell) and PHP will take care of any necessary argument escaping.
 * @param array $descriptor_spec An indexed array where the key represents the descriptor number and the value represents how PHP will pass that descriptor to the child process. 0 is stdin, 1 is stdout, while 2 is stderr. Each element can be: An array describing the pipe to pass to the process. The ...
 * @param array &$pipes Will be set to an indexed array of file pointers that correspond to PHP's end of any pipes that are created.
 * @param string|null $cwd [optional] The initial working dir for the command. This must be an absolute directory path, or null if you want to use the default value (the working dir of the current PHP process)
 * @param array|null $env_vars [optional] An array with the environment variables for the command that will be run, or null to use the same environment as the current PHP process
 * @param array|null $options [optional] Allows you to specify additional options. Currently supported options include: suppress_errors (windows only): suppresses errors generated by this function when it's set to TRUE generated by this function when it's set to true bypass_shell (windows only): ...
 * @return resource|false a resource representing the process, which should be freed using proc_close when you are finished with it. On failure returns false.
 * @throws \ValueError As of PHP 8.3.0, throws a ValueError if command is an array without at least one non-empty element.
 */
function proc_open(array|string $command, array $descriptor_spec, &$pipes, ?string $cwd = null, ?array $env_vars = null, ?array $options = null) {}

/**
 * Close a process opened by proc_open and return the exit code of that process
 * @param resource $process The proc_open resource that will be closed.
 * @return int the termination status of the process that was run.
 */
function proc_close($process): int {}

/**
 * Kills a process opened by proc_open
 * @param resource $process The proc_open resource that will be closed.
 * @param int $signal [optional] This optional parameter is only useful on POSIX operating systems; you may specify a signal to send to the process using the kill(2) system call. The default is SIGTERM.
 * @return bool the termination status of the process that was run.
 */
function proc_terminate($process, int $signal = 15): bool {}

/**
 * Get information about a process opened by proc_open
 * @param resource $process The proc_open resource that will be evaluated.
 * @return array|false An array of collected information on success, and false on failure. The returned array contains the following elements: elementtypedescription command string The command string that was passed to proc_open. pid int process id running bool true if the process is still running, ...
 */
function proc_get_status($process): array {}

/**
 * Change the priority of the current process.
 *
 * Since 7.2.0 supported on Windows platforms.
 * @param int $priority The increment value of the priority change.
 * @return bool true on success or false on failure. If an error occurs, like the user lacks permission to change the priority, an error of level E_WARNING is also generated.
 */
function proc_nice(int $priority): bool {}

/**
 * Get port number associated with an Internet service and protocol
 * @param string $service The Internet service name, as a string.
 * @param string $protocol protocol is either "tcp" or "udp" (in lowercase).
 * @return int|false the port number, or false if service or protocol is not found.
 */
function getservbyname(string $service, string $protocol): int|false {}

/**
 * Get Internet service which corresponds to port and protocol
 * @param int $port The port number.
 * @param string $protocol protocol is either "tcp" or "udp" (in lowercase).
 * @return string|false the Internet service name as a string.
 */
function getservbyport(int $port, string $protocol): string|false {}

/**
 * Get protocol number associated with protocol name
 * @param string $protocol The protocol name.
 * @return int|false the protocol number or -1 if the protocol is not found.
 */
function getprotobyname(string $protocol): int|false {}

/**
 * Get protocol name associated with protocol number
 * @param int $protocol The protocol number.
 * @return string|false the protocol name as a string.
 */
function getprotobynumber(int $protocol): string|false {}

/**
 * Gets PHP script owner's UID
 * @return int|false the user ID of the current script, or false on error.
 */
function getmyuid(): int|false {}

/**
 * Get PHP script owner's GID
 * @return int|false the group ID of the current script, or false on error.
 */
function getmygid(): int|false {}

/**
 * Gets PHP's process ID
 * @return int|false the current PHP process ID, or false on error.
 */
function getmypid(): int|false {}

/**
 * Gets the inode of the current script
 * @return int|false the current script's inode as an integer, or false on error.
 */
function getmyinode(): int|false {}
