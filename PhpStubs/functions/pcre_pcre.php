<?php

/**
 * Perform a regular expression match
 * @param string $pattern The pattern to search for, as a string.
 * @param string $subject The input string.
 * @param null|string[] &$matches [optional] If matches is provided, then it is filled with the results of search. $matches[0] will contain the text that matched the full pattern, $matches[1] will have the text that matched the first captured parenthesized subpattern, and so on.
 * @param int $flags [optional] flags can be the following flag: PREG_OFFSET_CAPTURE If this flag is passed, for every occurring match the appendant string offset will also be returned. Note that this changes the value of matches into an array where every element is an array consisting of the matched ...
 * @param int $offset [optional] Normally, the search starts from the beginning of the subject string. The optional parameter offset can be used to specify the alternate place from which to start the search (in bytes). Using offset is not equivalent to passing substr($subject, $offset) to preg_match ...
 * @return int|false preg_match returns 1 if the pattern matches given subject, 0 if it does not, or FALSE if an error occurred.
 */
function preg_match(string $pattern, string $subject, ?array &$matches = null, int $flags = 0, int $offset = 0): int|false {}

/**
 * Perform a global regular expression match
 * @param string $pattern The pattern to search for, as a string.
 * @param string $subject The input string.
 * @param null|string[][] &$matches [optional] Array of all matches in multi-dimensional array ordered according to flags.
 * @param int $flags Can be a combination of the following flags (note that it doesn't make sense to use PREG_PATTERN_ORDER together with PREG_SET_ORDER): PREG_PATTERN_ORDER Orders results so that $matches[0] is an array of full pattern matches, $matches[1] is an array of strings matched by the first ...
 * @param int $offset [optional] Normally, the search starts from the beginning of the subject string. The optional parameter offset can be used to specify the alternate place from which to start the search (in bytes). Using offset is not equivalent to passing substr($subject, $offset) to ...
 * @return int|false|null the number of full pattern matches (which might be zero), or FALSE if an error occurred.
 */
function preg_match_all(string $pattern, string $subject, ?array &$matches = null, int $flags = 0, int $offset = 0): int|false {}

/**
 * Perform a regular expression search and replace
 * @param string|string[] $pattern The pattern to search for. It can be either a string or an array with strings. Several PCRE modifiers are also available, including the deprecated 'e' (PREG_REPLACE_EVAL), which is specific to this function.
 * @param string|string[] $replacement The string or an array with strings to replace. If this parameter is a string and the pattern parameter is an array, all patterns will be replaced by that string. If both pattern and replacement parameters are arrays, each pattern will be replaced by the ...
 * @param string|string[] $subject The string or an array with strings to search and replace. If subject is an array, then the search and replace is performed on every entry of subject, and the return value is an array as well.
 * @param int $limit [optional] The maximum possible replacements for each pattern in each subject string. Defaults to -1 (no limit).
 * @param int &$count [optional] If specified, this variable will be filled with the number of replacements done.
 * @return string|string[]|null preg_replace returns an array if the subject parameter is an array, or a string otherwise. If matches are found, the new subject will be returned, otherwise subject will be returned unchanged or NULL if an error occurred.
 */
function preg_replace(array|string $pattern, array|string $replacement, array|string $subject, int $limit = -1, &$count = null): array|string|null {}

/**
 * Perform a regular expression search and replace using a callback
 * @param string|string[] $pattern The pattern to search for. It can be either a string or an array with strings.
 * @param callable $callback A callback that will be called and passed an array of matched elements in the subject string. The callback should return the replacement string. This is the callback signature: stringhandler arraymatches You'll often need the callback function for a preg_replace_callback ...
 * @param string|string[] $subject The string or an array with strings to search and replace.
 * @param int $limit [optional] The maximum possible replacements for each pattern in each subject string. Defaults to -1 (no limit).
 * @param int &$count [optional] If specified, this variable will be filled with the number of replacements done.
 * @param int $flags [optional]
 * @return string|string[]|null preg_replace_callback returns an array if the subject parameter is an array, or a string otherwise. On errors the return value is NULL If matches are found, the new subject will be returned, otherwise subject will be returned unchanged.
 */
function preg_replace_callback(
    array|string $pattern,
    callable $callback,
    array|string $subject,
    int $limit = -1,
    &$count = null,
    int $flags = 0
): array|string|null {}

/**
 * Perform a regular expression search and replace using callbacks
 * @param callable[] $pattern An associative array mapping patterns (keys) to callbacks (values)
 * @param string|string[] $subject The string or an array with strings to search and replace.
 * @param int $limit [optional]
 * @param int &$count [optional]
 * @param int $flags [optional]
 * @return string|string[]|null  preg_replace_callback_array() returns an array if the subject parameter is an array, or a string otherwise. On errors the return value is NULL If matches are found, the new subject will be returned, otherwise subject will be returned unchanged.
 */
function preg_replace_callback_array(
    array $pattern,
    array|string $subject,
    int $limit = -1,
    &$count = null,
    int $flags = 0
): array|string|null {}

/**
 * Perform a regular expression search and replace
 * @param string|string[] $pattern
 * @param string|string[] $replacement
 * @param string|string[] $subject
 * @param int $limit [optional]
 * @param int &$count [optional]
 * @return string|string[]|null an array if the subject parameter is an array, or a string otherwise. If no matches are found or an error occurred, an empty array is returned when subject is an array or NULL otherwise.
 */
function preg_filter(array|string $pattern, array|string $replacement, array|string $subject, int $limit = -1, &$count = null): array|string|null {}

/**
 * Split string by a regular expression
 * @param string $pattern The pattern to search for, as a string.
 * @param string $subject The input string.
 * @param int $limit [optional] If specified, then only substrings up to limit are returned with the rest of the string being placed in the last substring. A limit of -1, 0 or NULL means "no limit" and, as is standard across PHP, you can use NULL to skip to the flags parameter.
 * @param int $flags [optional] flags can be any combination of the following flags (combined with the | bitwise operator): PREG_SPLIT_NO_EMPTY If this flag is set, only non-empty pieces will be returned by preg_split.
 * @return string[]|false an array containing substrings of subject split along boundaries matched by pattern, or FALSE if an error occurred.
 */
function preg_split(string $pattern, string $subject, int $limit = -1, int $flags = 0): array|false {}

/**
 * Quote regular expression characters
 * @param string $str The input string.
 * @param string|null $delimiter [optional] If the optional delimiter is specified, it will also be escaped. This is useful for escaping the delimiter that is required by the PCRE functions. The / is the most commonly used delimiter.
 * @return string the quoted (escaped) string.
 */
function preg_quote(string $str, ?string $delimiter = null): string {}

/**
 * Return array entries that match the pattern
 * @param string $pattern The pattern to search for, as a string.
 * @param array $array The input array.
 * @param int $flags [optional] If set to PREG_GREP_INVERT, this function returns the elements of the input array that do not match the given pattern.
 * @return array|false an array indexed using the keys from the input array or false when pattern cannot be compiled.
 */
function preg_grep(string $pattern, array $array, int $flags = 0): array|false {}

/**
 * Returns the error code of the last PCRE regex execution
 * @return int one of the following constants (explained on their own page): PREG_NO_ERROR PREG_INTERNAL_ERROR PREG_BACKTRACK_LIMIT_ERROR (see also pcre.backtrack_limit) PREG_RECURSION_LIMIT_ERROR (see also pcre.recursion_limit) PREG_BAD_UTF8_ERROR PREG_BAD_UTF8_OFFSET_ERROR (since PHP 5.3.0)
 */
function preg_last_error(): int {}

/**
 * Returns the error message of the last PCRE regex execution
 * @return string one of the error messages or "No error" if there is no error.
 * @since 8.0
 */
function preg_last_error_msg(): string {}
