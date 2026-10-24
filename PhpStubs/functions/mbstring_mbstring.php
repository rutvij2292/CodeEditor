<?php

/**
 * Perform case folding on a string
 * @param string $string The string being converted.
 * @param int $mode The mode of the conversion. It can be one of MB_CASE_UPPER, MB_CASE_LOWER, or MB_CASE_TITLE.
 * @param string|null $encoding [optional]
 * @return string A case folded version of string converted in the way specified by mode.
 */
function mb_convert_case(string $string, int $mode, ?string $encoding = null): string {}

/**
 * Make a string uppercase
 * @param string $string The string being uppercased.
 * @param string|null $encoding [optional]
 * @return string str with all alphabetic characters converted to uppercase.
 */
function mb_strtoupper(string $string, ?string $encoding = null): string {}

/**
 * Make a string lowercase
 * @param string $string The string being lowercased.
 * @param string|null $encoding [optional]
 * @return string str with all alphabetic characters converted to lowercase.
 */
function mb_strtolower(string $string, ?string $encoding = null): string {}

/**
 * Set/Get current language
 * @param string|null $language [optional] Used for encoding e-mail messages. Valid languages are "Japanese", "ja","English","en" and "uni" (UTF-8). mb_send_mail uses this setting to encode e-mail. Language and its setting is ISO-2022-JP/Base64 for Japanese, UTF-8/Base64 for uni, ISO-8859-1/quoted ...
 * @return bool|string If language is set and language is valid, it returns true. Otherwise, it returns false. When language is omitted, it returns the language name as a string. If no language is set previously, it then returns false.
 */
function mb_language(?string $language = null): string|bool {}

/**
 * Set/Get internal character encoding
 * @param string|null $encoding [optional] encoding is the character encoding name used for the HTTP input character encoding conversion, HTTP output character encoding conversion, and the default character encoding for string functions defined by the mbstring module.
 * @return bool|string If encoding is set, then true on success or false on failure. If encoding is omitted, then the current character encoding name is returned.
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the value of encoding is an invalid encoding. Prior to PHP 8.0.0, a E_WARNING was emitted instead.
 */
function mb_internal_encoding(?string $encoding = null): string|bool {}

/**
 * Detect HTTP input character encoding
 * @param string|null $type [optional] Input string specifies the input type. "G" for GET, "P" for POST, "C" for COOKIE, "S" for string, "L" for list, and "I" for the whole list (will return array). If type is omitted, it returns the last input type processed.
 * @return array|false|string The character encoding name, as per the type. If mb_http_input does not process specified HTTP input, it returns false.
 * @throws \ValueError Throws a ValueError if type is invalid.
 */
function mb_http_input(?string $type = null): array|string|false {}

/**
 * Set/Get HTTP output character encoding
 * @param string|null $encoding [optional] If encoding is set, mb_http_output sets the HTTP output character encoding to encoding. If encoding is omitted, mb_http_output returns the current HTTP output character encoding.
 * @return bool|string If encoding is omitted, mb_http_output returns the current HTTP output character encoding. Otherwise, true on success or false on failure.
 * @throws \ValueError Throws a ValueError if encoding contains null bytes.
 */
function mb_http_output(?string $encoding = null): string|bool {}

/**
 * Set/Get character encoding detection order
 * @param array|string|null $encoding [optional] encoding_list is an array or comma separated list of character encoding. ("auto" is expanded to "ASCII, JIS, UTF-8, EUC-JP, SJIS") If encoding_list is omitted, it returns the current character encoding detection order as array. This setting affects ...
 * @return bool|string[] When setting the encoding detection order, true is returned on success or FALSE on failure. When getting the encoding detection order, an ordered array of the encodings is returned.
 */
function mb_detect_order(array|string|null $encoding = null): array|bool {}

/**
 * Set/Get substitution character
 * @param string|int|null $substitute_character [optional] Specify the Unicode value as an integer, or as one of the following strings: "none" : no output "long": Output character code value (Example: U+3000, JIS+7E7E) "entity": Output character entity (Example: Ȁ)
 * @return bool|int|string If substchar is set, it returns true for success, otherwise returns false. If substchar is not set, it returns the Unicode value, or "none" or "long".
 */
function mb_substitute_character(string|int|null $substitute_character = null): string|int|bool {}

/**
 * Parse GET/POST/COOKIE data and set global variable
 * @param string $string The URL encoded data.
 * @param array &$result An array containing decoded and character encoded converted values.
 * @return bool true on success or false on failure.
 */
function mb_parse_str(string $string, &$result): bool {}

/**
 * Callback function converts character encoding in output buffer
 * @param string $string The contents of the output buffer.
 * @param int $status The status of the output buffer.
 * @return string The converted string.
 */
function mb_output_handler(string $string, int $status): string {}

/**
 * Get MIME charset string
 * @param string $encoding The encoding being checked.
 * @return string|false The MIME charset string for character encoding encoding.
 */
function mb_preferred_mime_name(string $encoding): string|false {}

/**
 * Get string length
 * @param string $string The string being checked for length.
 * @param string|null $encoding [optional]
 * @return int|false the number of characters in string str having character encoding encoding. A multi-byte character is counted as 1.
 */
function mb_strlen(string $string, string|null $encoding = null): int {}

/**
 * Find position of first occurrence of string in a string
 * @param string $haystack The string being checked.
 * @param string $needle The position counted from the beginning of haystack.
 * @param int<0,max> $offset [optional] The search offset. If it is not specified, 0 is used.
 * @param string|null $encoding [optional]
 * @return int<0,max>|false the numeric position of the first occurrence of needle in the haystack string. If needle is not found, it returns false.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function mb_strpos(string $haystack, string $needle, int $offset = 0, ?string $encoding = null): int|false {}

/**
 * Find position of last occurrence of a string in a string
 * @param string $haystack The string being checked, for the last occurrence of needle
 * @param string $needle The string to find in haystack.
 * @param int $offset [optional] May be specified to begin searching an arbitrary number of characters into the string. Negative values will stop searching at an arbitrary point prior to the end of the string.
 * @param string|null $encoding [optional]
 * @return int|false the numeric position of the last occurrence of needle in the haystack string. If needle is not found, it returns false.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function mb_strrpos(string $haystack, string $needle, int $offset = 0, ?string $encoding = null): int|false {}

/**
 * Finds position of first occurrence of a string within another, case insensitive
 * @param string $haystack The string from which to get the position of the first occurrence of needle
 * @param string $needle The string to find in haystack
 * @param int $offset [optional] The position in haystack to start searching
 * @param string|null $encoding [optional] Character encoding name to use. If it is omitted, internal character encoding is used.
 * @return int|false Return the numeric position of the first occurrence of needle in the haystack string, or false if needle is not found.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function mb_stripos(string $haystack, string $needle, int $offset = 0, ?string $encoding = null): int|false {}

/**
 * Finds position of last occurrence of a string within another, case insensitive
 * @param string $haystack The string from which to get the position of the last occurrence of needle
 * @param string $needle The string to find in haystack
 * @param int $offset [optional] The position in haystack to start searching
 * @param string|null $encoding [optional] Character encoding name to use. If it is omitted, internal character encoding is used.
 * @return int|false Return the numeric position of the last occurrence of needle in the haystack string, or false if needle is not found.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function mb_strripos(string $haystack, string $needle, int $offset = 0, ?string $encoding = null): int|false {}

/**
 * Finds first occurrence of a string within another
 * @param string $haystack The string from which to get the first occurrence of needle
 * @param string $needle The string to find in haystack
 * @param bool $before_needle [optional] Determines which portion of haystack this function returns. If set to true, it returns all of haystack from the beginning to the first occurrence of needle. If set to false, it returns all of haystack from the first occurrence of needle to the end,
 * @param string|null $encoding [optional] Character encoding name to use. If it is omitted, internal character encoding is used.
 * @return string|false the portion of haystack, or false if needle is not found.
 */
function mb_strstr(string $haystack, string $needle, bool $before_needle = false, ?string $encoding = null): string|false {}

/**
 * Finds the last occurrence of a character in a string within another
 * @param string $haystack The string from which to get the last occurrence of needle
 * @param string $needle The string to find in haystack
 * @param bool $before_needle [optional] Determines which portion of haystack this function returns. If set to true, it returns all of haystack from the beginning to the last occurrence of needle. If set to false, it returns all of haystack from the last occurrence of needle to the end,
 * @param string|null $encoding [optional] Character encoding name to use. If it is omitted, internal character encoding is used.
 * @return string|false the portion of haystack. or false if needle is not found.
 */
function mb_strrchr(string $haystack, string $needle, bool $before_needle = false, ?string $encoding = null): string|false {}

/**
 * Finds first occurrence of a string within another, case insensitive
 * @param string $haystack The string from which to get the first occurrence of needle
 * @param string $needle The string to find in haystack
 * @param bool $before_needle [optional] Determines which portion of haystack this function returns. If set to true, it returns all of haystack from the beginning to the first occurrence of needle. If set to false, it returns all of haystack from the first occurrence of needle to the end,
 * @param string|null $encoding [optional] Character encoding name to use. If it is omitted, internal character encoding is used.
 * @return string|false the portion of haystack, or false if needle is not found.
 */
function mb_stristr(string $haystack, string $needle, bool $before_needle = false, ?string $encoding = null): string|false {}

/**
 * Finds the last occurrence of a character in a string within another, case insensitive
 * @param string $haystack The string from which to get the last occurrence of needle
 * @param string $needle The string to find in haystack
 * @param bool $before_needle [optional] Determines which portion of haystack this function returns. If set to true, it returns all of haystack from the beginning to the last occurrence of needle. If set to false, it returns all of haystack from the last occurrence of needle to the end,
 * @param string|null $encoding [optional] Character encoding name to use. If it is omitted, internal character encoding is used.
 * @return string|false the portion of haystack. or false if needle is not found.
 */
function mb_strrichr(string $haystack, string $needle, bool $before_needle = false, ?string $encoding = null): string|false {}

/**
 * Count the number of substring occurrences
 * @param string $haystack The string being checked.
 * @param string $needle The string being found.
 * @param string|null $encoding [optional]
 * @return int The number of times the needle substring occurs in the haystack string.
 */
function mb_substr_count(string $haystack, string $needle, ?string $encoding = null): int {}

/**
 * Get part of string
 * @param string $string The string being checked.
 * @param int $start The first position used in str.
 * @param int|null $length [optional] The maximum length of the returned string.
 * @param string|null $encoding [optional]
 * @return string mb_substr returns the portion of str specified by the start and length parameters.
 */
function mb_substr(string $string, int $start, ?int $length = null, ?string $encoding = null): string {}

/**
 * Get part of string
 * @param string $string The string being cut.
 * @param int $start The position that begins the cut.
 * @param int|null $length [optional] The string being decoded.
 * @param string|null $encoding [optional]
 * @return string mb_strcut returns the portion of str specified by the start and length parameters.
 */
function mb_strcut(string $string, int $start, ?int $length = null, ?string $encoding = null): string {}

/**
 * Return width of string
 * @param string $string The string being decoded.
 * @param string|null $encoding [optional]
 * @return int The width of string str.
 */
function mb_strwidth(string $string, ?string $encoding = null): int {}

/**
 * Get truncated string with specified width
 * @param string $string The string being decoded.
 * @param int $start The start position offset. Number of characters from the beginning of string. (First character is 0)
 * @param int $width The width of the desired trim.
 * @param string $trim_marker A string that is added to the end of string when string is truncated.
 * @param string|null $encoding [optional]
 * @return string The truncated string. If trimmarker is set, trimmarker is appended to the return value.
 */
function mb_strimwidth(string $string, int $start, int $width, string $trim_marker = '', ?string $encoding = null): string {}

/**
 * Convert character encoding
 * @param string|array $string The string being encoded.
 * @param string $to_encoding The type of encoding that str is being converted to.
 * @param string|string[]|null $from_encoding [optional] Is specified by character code names before conversion. It is either an array, or a comma separated enumerated list. If from_encoding is not specified, the internal encoding will be used. "auto" may be used, which expands to ...
 * @return array|string|false The encoded string.
 * @throws \ValueError As of PHP 8.0.0, a ValueError is thrown if the value of to_encoding or from_encoding is an invalid encoding. Prior to PHP 8.0.0, a E_WARNING was emitted instead.
 */
function mb_convert_encoding(array|string $string, string $to_encoding, array|string|null $from_encoding = null): array|string|false {}

/**
 * Detect character encoding
 * @param string $string The string being detected.
 * @param string|string[]|null $encodings [optional] encoding_list is list of character encoding. Encoding order may be specified by array or comma separated list string. If encoding_list is omitted, detect_order is used.
 * @param bool $strict [optional] strict specifies whether to use the strict encoding detection or not. Default is false.
 * @return string|false The detected character encoding or false if the encoding cannot be detected from the given string.
 */
function mb_detect_encoding(string $string, array|string|null $encodings = null, bool $strict = false): string|false {}

/**
 * Returns an array of all supported encodings
 * @return string[] a numerically indexed array.
 */
function mb_list_encodings(): array {}

/**
 * Get aliases of a known encoding type
 * @param string $encoding The encoding type being checked, for aliases.
 * @return string[]|false a numerically indexed array of encoding aliases on success, or FALSE on failure
 * @throws \ValueError Throws a ValueError if encoding is unknown.
 */
function mb_encoding_aliases(string $encoding): array {}

/**
 * Convert "kana" one from another ("zen-kaku", "han-kaku" and more)
 * @param string $string The string being converted.
 * @param string $mode [optional] The conversion option. Specify with a combination of following options. Applicable Conversion Options Option Meaning r Convert "zen-kaku" alphabets to "han-kaku" R Convert "han-kaku" alphabets to "zen-kaku" n Convert "zen-kaku" numbers to "han-kaku" N Convert ...
 * @param string|null $encoding [optional]
 * @return string The converted string.
 * @throws \ValueError Throws a ValueError if the combination of different modes is invalid. For example "sS".
 */
function mb_convert_kana(string $string, string $mode = 'KV', ?string $encoding = null): string {}

/**
 * Encode string for MIME header
 * @param string $string The string being encoded.
 * @param string|null $charset [optional] charset specifies the name of the character set in which str is represented in. The default value is determined by the current NLS setting (mbstring.language). mb_internal_encoding should be set to same encoding.
 * @param string|null $transfer_encoding [optional] transfer_encoding specifies the scheme of MIME encoding. It should be either "B" (Base64) or "Q" (Quoted-Printable). Falls back to "B" if not given.
 * @param string $newline [optional] linefeed specifies the EOL (end-of-line) marker with which mb_encode_mimeheader performs line-folding (a RFC term, the act of breaking a line longer than a certain length into multiple lines. The length is currently hard-coded to 74 characters). Falls back to ...
 * @param int $indent Indentation of the first line (number of characters in the header before str).
 * @return string A converted version of the string represented in ASCII.
 */
function mb_encode_mimeheader(string $string, ?string $charset = null, ?string $transfer_encoding = null, string $newline = "\r\n", int $indent = 0): string {}

/**
 * Decode string in MIME header field
 * @param string $string The string being decoded.
 * @return string The decoded string in internal character encoding.
 */
function mb_decode_mimeheader(string $string): string {}

/**
 * Convert character code in variable(s)
 * @param string $to_encoding The encoding that the string is being converted to.
 * @param string|string[] $from_encoding from_encoding is specified as an array or comma separated string, it tries to detect encoding from from-coding. When from_encoding is omitted, detect_order is used.
 * @param string|array|object &$var var is the reference to the variable being converted.
 * @param string|array|object &...$vars vars is the other references to the variables being converted. String, Array and Object are accepted. mb_convert_variables assumes all parameters have the same encoding.
 * @return string|false The character encoding before conversion for success, or false for failure.
 */
function mb_convert_variables(
    string $to_encoding,
    array|string $from_encoding,
    mixed &$var,
    mixed &...$vars
): string|false {}

/**
 * Encode character to HTML numeric string reference
 * @param string $string The string being encoded.
 * @param int[] $map convmap is array specifies code area to convert.
 * @param null|string $encoding The encoding parameter is the character encoding. If it is omitted or null, the internal character encoding value will be used.
 * @param bool $hex [optional]
 * @return string The converted string.
 * @throws \ValueError Throws a ValueError if map is not a list of integers.
 */
function mb_encode_numericentity(string $string, array $map, ?string $encoding = null, bool $hex = false): string {}

/**
 * Decode HTML numeric string reference to character
 * @param string $string The string being decoded.
 * @param int[] $map convmap is an array that specifies the code area to convert.
 * @param null|string $encoding The encoding parameter is the character encoding. If it is omitted or null, the internal character encoding value will be used.
 * @param bool $is_hex [optional] this parameter is not used.
 * @return string|false|null The converted string.
 * @throws \ValueError Throws a ValueError if map is not a list of integers.
 */
function mb_decode_numericentity(string $string, array $map, ?string $encoding = null): string {}

/**
 * Send encoded mail
 * @param string $to The mail addresses being sent to. Multiple recipients may be specified by putting a comma between each address in to. This parameter is not automatically encoded.
 * @param string $subject The subject of the mail.
 * @param string $message The message of the mail.
 * @param string|array $additional_headers String or array to be inserted at the end of the email header. Since 7.2.0 accepts an array. Its keys are the header names and its values are the respective header values. This is typically used to add extra headers. Multiple extra headers are separated with ...
 * @param string|null $additional_params [optional] additional_parameter is a MTA command line parameter. It is useful when setting the correct Return-Path header when using sendmail.
 * @return bool true on success or false on failure.
 */
function mb_send_mail(string $to, string $subject, string $message, array|string $additional_headers = [], ?string $additional_params = null): bool {}

/**
 * Get internal settings of mbstring
 * @param string $type [optional] If type isn't specified or is specified to "all", an array having the elements "internal_encoding", "http_output", "http_input", "func_overload", "mail_charset", "mail_header_encoding", "mail_body_encoding" will be returned. If type is specified as "http_output", ...
 * @return array|string|int|false An array of type information if type is not specified, otherwise a specific type.
 */
function mb_get_info(string $type = 'all'): array|string|int|false|null {}

/**
 * Check if the string is valid for the specified encoding
 * @param string|string[]|null $value [optional] The byte stream to check. If it is omitted, this function checks all the input from the beginning of the request.
 * @param string|null $encoding [optional] The expected encoding.
 * @return bool true on success or false on failure.
 * @since 5.1
 */
function mb_check_encoding(array|string|null $value = null, ?string $encoding = null): bool {}

/**
 * Returns current encoding for multibyte regex as string
 * @param string|null $encoding [optional]
 * @return bool|string If encoding is set, then Returns TRUE on success or FALSE on failure. In this case, the internal character encoding is NOT changed. If encoding is omitted, then the current character encoding name for a multibyte regex is returned.
 */
function mb_regex_encoding(?string $encoding = null): string|bool {}

/**
 * Set/Get the default options for mbregex functions
 * @param string|null $options [optional] The options to set.
 * @return string The previous options. If options is omitted, it returns the string that describes the current options.
 */
function mb_regex_set_options(?string $options = null): string {}

/**
 * Regular expression match with multibyte support
 * @param string $pattern The search pattern.
 * @param string $string The search string.
 * @param string[] &$matches [optional] Contains a substring of the matched string.
 * @return bool Returns whether pattern matches string.
 */
function mb_ereg(string $pattern, string $string, &$matches = null): bool {}

/**
 * Regular expression match ignoring case with multibyte support
 * @param string $pattern The regular expression pattern.
 * @param string $string The string being searched.
 * @param string[] &$matches [optional] Contains a substring of the matched string.
 * @return bool|int Returns whether pattern matches string.
 */
function mb_eregi(string $pattern, string $string, &$matches = null): bool {}

/**
 * Replace regular expression with multibyte support
 * @param string $pattern The regular expression pattern. Multibyte characters may be used in pattern.
 * @param string $replacement The replacement text.
 * @param string $string The string being checked.
 * @param string|null $options Matching condition can be set by option parameter. If i is specified for this parameter, the case will be ignored. If x is specified, white space will be ignored. If m is specified, match will be executed in multiline mode and line break will be included in '.'. If p is ...
 * @return string|false|null The resultant string on success, or false on error.
 */
function mb_ereg_replace(string $pattern, string $replacement, string $string, ?string $options = null): string|false|null {}

/**
 * Perform a regular expresssion seach and replace with multibyte support using a callback
 * @param string $pattern The regular expression pattern. Multibyte characters may be used in pattern.
 * @param callable $callback A callback that will be called and passed an array of matched elements in the  subject string. The callback should return the replacement string. You'll often need the callback function for a mb_ereg_replace_callback() in just one place. In this case you can use an ...
 * @param string $string The string being checked.
 * @param string $options Matching condition can be set by option parameter. If i is specified for this parameter, the case will be ignored. If x is specified, white space will be ignored. If m is specified, match will be executed in multiline mode and line break will be included in '.'. If p is ...
 * @return string|false|null The resultant string on success, or FALSE on error.
 * @since 5.4
 */
function mb_ereg_replace_callback(string $pattern, callable $callback, string $string, ?string $options = null): string|false|null {}

/**
 * Replace regular expression with multibyte support ignoring case
 * @param string $pattern The regular expression pattern. Multibyte characters may be used. The case will be ignored.
 * @param string $replacement The replacement text.
 * @param string $string The searched string.
 * @param string|null $options option has the same meaning as in mb_ereg_replace. PHP 7.1: The e modifier has been deprecated.
 * @return string|false|null The resultant string or false on error.
 */
function mb_eregi_replace(
    string $pattern,
    string $replacement,
    string $string,
    ?string $options = null
): string|false|null {}

/**
 * Split multibyte string using regular expression
 * @param string $pattern The regular expression pattern.
 * @param string $string The string being split.
 * @param int $limit [optional] If optional parameter limit is specified, it will be split in limit elements as maximum.
 * @return string[]|false The result as an array.
 */
function mb_split(string $pattern, string $string, int $limit = -1): array|false {}

/**
 * Regular expression match for multibyte string
 * @param string $pattern The regular expression pattern.
 * @param string $string The string being evaluated.
 * @param string|null $options [optional]
 * @return bool Returns true if string matches the regular expression pattern, false if not.
 */
function mb_ereg_match(string $pattern, string $string, ?string $options = null): bool {}

/**
 * Multibyte regular expression match for predefined multibyte string
 * @param string|null $pattern [optional] The search pattern.
 * @param string|null $options [optional] The search option.
 * @return bool mb_ereg_search returns true if the multibyte string matches with the regular expression, or false otherwise. The string for matching is set by mb_ereg_search_init. If pattern is not specified, the previous one is used.
 */
function mb_ereg_search(?string $pattern = null, ?string $options = null): bool {}

/**
 * Returns position and length of a matched part of the multibyte regular expression for a predefined multibyte string
 * @param string|null $pattern [optional] The search pattern.
 * @param string|null $options [optional] The search option.
 * @return int[]|false An array containing two elements. The first element is the offset, in bytes, where the match begins relative to the start of the search string, and the second element is the length in bytes of the match. If an error occurs, FALSE is returned.
 */
function mb_ereg_search_pos(?string $pattern = null, ?string $options = null): array|false {}

/**
 * Returns the matched part of a multibyte regular expression
 * @param string|null $pattern [optional] The search pattern.
 * @param string|null $options [optional] The search option.
 * @return string[]|false mb_ereg_search_regs() executes the multibyte regular expression match, and if there are some matched part, it returns an array including substring of matched part as first element, the first grouped part with brackets as second element, the second grouped part as third ...
 */
function mb_ereg_search_regs(?string $pattern = null, ?string $options = null): array|false {}

/**
 * Setup string and regular expression for a multibyte regular expression match
 * @param string $string The search string.
 * @param string|null $pattern [optional] The search pattern.
 * @param string|null $options [optional] The search option.
 * @return bool Returns true on success or false on failure.
 */
function mb_ereg_search_init(string $string, ?string $pattern = null, ?string $options = null): bool {}

/**
 * Retrieve the result from the last multibyte regular expression match
 * @return string[]|false An array including the sub-string of matched part by last mb_ereg_search(), mb_ereg_search_pos(), mb_ereg_search_regs(). If there are some matches, the first element will have the matched sub-string, the second element will have the first part grouped with brackets, the third ...
 */
function mb_ereg_search_getregs(): array|false {}

/**
 * Returns start point for next regular expression match
 * @return int mb_ereg_search_getpos returns the point to start regular expression match for mb_ereg_search, mb_ereg_search_pos, mb_ereg_search_regs. The position is represented by bytes from the head of string.
 */
function mb_ereg_search_getpos(): int {}

/**
 * Set start point of next regular expression match
 * @param int $offset The position to set.
 * @return bool Returns true on success or false on failure.
 */
function mb_ereg_search_setpos(int $offset): bool {}

/**
 * @param string|null $encoding [optional]
 * @see mb_regex_encoding
 * @removed 8.0
 * @deprecated
 */
function mbregex_encoding($encoding) {}

/**
 * @param string $pattern
 * @param string $string
 * @param array &$registers [optional]
 * @see mb_ereg
 * @removed 8.0
 * @deprecated
 */
function mbereg(string $pattern, string $string, array &$registers) {}

/**
 * @param string $pattern
 * @param string $string
 * @param array &$registers [optional]
 * @see mb_eregi
 * @removed 8.0
 * @deprecated
 */
function mberegi(string $pattern, string $string, array &$registers) {}

/**
 * @param string $pattern
 * @param string $replacement
 * @param string $string
 * @param $option [optional]
 * @see mb_ereg_replace
 * @removed 8.0
 * @deprecated
 */
function mbereg_replace($pattern, $replacement, $string, $option) {}

/**
 * @param string $pattern
 * @param string $replacement
 * @param string $string
 * @param string $option
 * @return string
 * @see mb_eregi_replace
 * @removed 8.0
 * @deprecated
 */
function mberegi_replace(
    $pattern,
    $replacement,
    $string,
    string $option = "msri"
): string {}

/**
 * @param string $pattern
 * @param string $string
 * @param int $limit [optional]
 * @see mb_split
 * @removed 8.0
 * @deprecated
 */
function mbsplit($pattern, $string, $limit) {}

/**
 * @param string $pattern
 * @param string $string
 * @param $option [optional]
 * @see mb_ereg_match
 * @removed 8.0
 * @deprecated
 */
function mbereg_match($pattern, $string, $option) {}

/**
 * @param string|null $pattern [optional]
 * @param $option [optional]
 * @see mb_ereg_search
 * @removed 8.0
 * @deprecated
 */
function mbereg_search($pattern, $option) {}

/**
 * @param string|null $pattern [optional]
 * @param $option [optional]
 * @see mb_ereg_search_pos
 * @removed 8.0
 * @deprecated
 */
function mbereg_search_pos($pattern, $option) {}

/**
 * @param string|null $pattern [optional]
 * @param $option [optional]
 * @see mb_ereg_search_regs
 * @removed 8.0
 * @deprecated
 */
function mbereg_search_regs($pattern, $option) {}

/**
 * @param string $string
 * @param string|null $pattern [optional]
 * @param $option [optional]
 * @see mb_ereg_search_init
 * @removed 8.0
 * @deprecated
 */
function mbereg_search_init($string, $pattern, $option) {}

/**
 * @see mb_ereg_search_getregs
 * @removed 8.0
 * @deprecated
 */
function mbereg_search_getregs() {}

/**
 * @see mb_ereg_search_getpos
 * @removed 8.0
 * @deprecated
 */
function mbereg_search_getpos() {}

/**
 * Get a specific character.
 * @param int $codepoint A Unicode codepoint value, e.g. 128024 for U+1F418 ELEPHANT
 * @param string|null $encoding [optional]
 * @return string|false specific character or FALSE on failure.
 * @since 7.2
 */
function mb_chr(int $codepoint, ?string $encoding = null): string|false {}

/**
 * Get code point of character
 * @param string $string A string
 * @param string|null $encoding [optional]
 * @return int|false code point of character or FALSE on failure.
 * @since 7.2
 */
function mb_ord(string $string, ?string $encoding = null): int|false {}

/**
 * Scrub broken multibyte strings.
 * @param string $string The input string.
 * @param string|null $encoding [optional]
 * @return string|false The string result with invalid byte sequences replaced.
 * @since 7.2
 */
function mb_scrub(string $string, ?string $encoding = null): string {}

/**
 * @param int $position
 * @see mb_ereg_search_setpos
 * @removed 8.0
 * @deprecated
 */
function mbereg_search_setpos($position) {}

/**
 * Function performs string splitting to an array of defined size chunks.
 * @param string $string The string to split into characters or chunks.
 * @param int $length [optional] If specified, each element of the returned array will be composed of multiple characters instead of a single character.
 * @param string|null $encoding [optional] Character encoding name to use. If it is omitted, internal character encoding is used.
 * @return string[]|false mb_str_split returns an array of strings.
 * @since 7.4
 */
function mb_str_split(string $string, int $length = 1, ?string $encoding = null): array {}

/**
 * Pad a multibyte string to a certain length with another multibyte string
 * @param string $string The input string.
 * @param int $length The desired length of the padded string, measured in Unicode codepoints. If the value is negative, less than, or equal to the length of the input string, no padding takes place.
 * @param string $pad_string [optional] The string to pad with. Default is a space.
 * @param int $pad_type [optional] Can be STR_PAD_RIGHT, STR_PAD_LEFT, or STR_PAD_BOTH.
 * @param string|null $encoding [optional] The character encoding. If omitted or null, the internal character encoding value will be used.
 * @return string The padded string.
 * @since 8.3
 */
function mb_str_pad(string $string, int $length, string $pad_string = " ", int $pad_type = STR_PAD_RIGHT, ?string $encoding = null): string {}

/**
 * Make a multibyte string's first character uppercase
 * @param string $string The input string.
 * @param string|null $encoding [optional] The character encoding. If omitted or null, the internal character encoding value will be used.
 * @return string The resulting string with the first character title-cased.
 * @since 8.4
 */
function mb_ucfirst(string $string, ?string $encoding = null): string {}

/**
 * Make a multibyte string's first character lowercase
 * @param string $string The input string.
 * @param string|null $encoding [optional] The character encoding. If omitted or null, the internal character encoding value will be used.
 * @return string The resulting string with the first character lowercased.
 * @since 8.4
 */
function mb_lcfirst(string $string, ?string $encoding = null): string {}

/**
 * Strip whitespace (or other characters) from the beginning and end of a multibyte string
 * @param string $string The string that will be trimmed.
 * @param string|null $characters [optional] The characters to be stripped. If omitted or null, the default whitespace characters are stripped, including ASCII whitespace and various Unicode space characters (NO-BREAK SPACE, OGHAM SPACE MARK, etc.).
 * @param string|null $encoding [optional] The character encoding. If omitted or null, the internal character encoding value will be used.
 * @return string The trimmed string.
 * @since 8.4
 */
function mb_trim(string $string, ?string $characters = null, ?string $encoding = null): string {}

/**
 * Strip whitespace (or other characters) from the beginning of a multibyte string
 * @param string $string The input string.
 * @param string|null $characters [optional] The characters to be stripped. If omitted or null, the default whitespace characters are stripped, including ASCII whitespace and various Unicode space characters (NO-BREAK SPACE, OGHAM SPACE MARK, etc.).
 * @param string|null $encoding [optional] The character encoding. If omitted or null, the internal character encoding value will be used.
 * @return string The trimmed string.
 * @since 8.4
 */
function mb_ltrim(string $string, ?string $characters = null, ?string $encoding = null): string {}

/**
 * Strip whitespace (or other characters) from the end of a multibyte string
 * @param string $string The input string.
 * @param string|null $characters [optional] The characters to be stripped. If omitted or null, the default whitespace characters are stripped, including ASCII whitespace and various Unicode space characters (NO-BREAK SPACE, OGHAM SPACE MARK, etc.).
 * @param string|null $encoding [optional] The character encoding. If omitted or null, the internal character encoding value will be used.
 * @return string The trimmed string.
 * @since 8.4
 */
function mb_rtrim(string $string, ?string $characters = null, ?string $encoding = null): string {}
