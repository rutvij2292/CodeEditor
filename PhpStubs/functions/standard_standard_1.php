<?php

/**
 * Make a string uppercase
 * @param string $string The input string.
 * @return string the uppercased string.
 */
function strtoupper(string $string): string {}

/**
 * Make a string lowercase
 * @param string $string The input string.
 * @return string the lowercased string.
 */
function strtolower(string $string): string {}

/**
 * Find the position of the first occurrence of a substring in a string
 * @param string $haystack The string to search in
 * @param string $needle If needle is not a string, it is converted to an integer and applied as the ordinal value of a character.
 * @param int<0,max> $offset [optional] If specified, search will start this number of characters counted from the beginning of the string. Unlike strrpos() and strripos(), the offset cannot be negative.
 * @return int<0,max>|false Returns the position where the needle exists relative to the beginning of the haystack string (independent of search direction or offset). Also note that string positions start at 0, and not 1. Returns FALSE if the needle was not found.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function strpos(string $haystack, string $needle, int $offset = 0): int|false {}

/**
 * Find position of first occurrence of a case-insensitive string
 * @param string $haystack The string to search in
 * @param string $needle Note that the needle may be a string of one or more characters. If needle is not a string, it is converted to an integer and applied as the ordinal value of a character.
 * @param int $offset The optional offset parameter allows you to specify which character in haystack to start searching. The position returned is still relative to the beginning of haystack.
 * @return int|false If needle is not found, stripos will return boolean false.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function stripos(string $haystack, string $needle, int $offset = 0): int|false {}

/**
 * Find the position of the last occurrence of a substring in a string
 * @param string $haystack The string to search in.
 * @param string $needle If needle is not a string, it is converted to an integer and applied as the ordinal value of a character.
 * @param int $offset [optional] If specified, search will start this number of characters counted from the beginning of the string. If the value is negative, search will instead start from that many characters from the end of the string, searching backwards.
 * @return int|false Returns the position where the needle exists relative to the beginning of the haystack string (independent of search direction or offset). Also note that string positions start at 0, and not 1. Returns FALSE if the needle was not found.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function strrpos(string $haystack, string $needle, int $offset = 0): int|false {}

/**
 * Find position of last occurrence of a case-insensitive string in a string
 * @param string $haystack The string to search in
 * @param string $needle Note that the needle may be a string of one or more characters.
 * @param int $offset The offset parameter may be specified to begin searching an arbitrary number of characters into the string. Negative offset values will start the search at offset characters from the start of the string.
 * @return int|false the numerical position of the last occurrence of needle. Also note that string positions start at 0, and not 1. If needle is not found, false is returned.
 * @throws \ValueError If offset is greater than the length of haystack, a ValueError will be thrown.
 */
function strripos(string $haystack, string $needle, int $offset = 0): int|false {}

/**
 * Reverse a string
 * @param string $string The string to be reversed.
 * @return string the reversed string.
 */
function strrev(string $string): string {}

/**
 * Convert logical Hebrew text to visual text
 * @param string $string A Hebrew input string.
 * @param int $max_chars_per_line This optional parameter indicates maximum number of characters per line that will be returned.
 * @return string the visual string.
 */
function hebrev(string $string, int $max_chars_per_line = 0): string {}

/**
 * Convert logical Hebrew text to visual text with newline conversion
 * @param string $hebrew_text A Hebrew input string.
 * @param int $max_chars_per_line [optional] This optional parameter indicates maximum number of characters per line that will be returned.
 * @return string the visual string.
 * @removed 8.0
 * @deprecated
 */
function hebrevc(string $hebrew_text, $max_chars_per_line = 0): string {}

/**
 * Inserts HTML line breaks before all newlines in a string
 * @param string $string The input string.
 * @param bool $use_xhtml [optional] Whether to use XHTML compatible line breaks or not.
 * @return string the altered string.
 */
function nl2br(string $string, bool $use_xhtml = true): string {}

/**
 * Returns trailing name component of path
 * @param string $path A path. On Windows, both slash (/) and backslash (\) are used as directory separator character. In other environments, it is the forward slash (/).
 * @param string $suffix If the filename ends in suffix this will also be cut off.
 * @return string the base name of the given path.
 */
function basename(string $path, string $suffix = ''): string {}

/**
 * Returns a parent directory's path
 * @param string $path A path. On Windows, both slash (/) and backslash (\) are used as directory separator character. In other environments, it is the forward slash (/).
 * @param int $levels The number of parent directories to go up. This must be an integer greater than 0.
 * @return string the name of the directory. If there are no slashes in path, a dot ('.') is returned, indicating the current directory. Otherwise, the returned string is path with any trailing /component removed.
 */
function dirname(string $path, int $levels = 1): string {}

/**
 * Returns information about a file path
 * @param string $path The path being checked.
 * @param int $flags [optional] You can specify which elements are returned with optional parameter options. It composes from PATHINFO_DIRNAME, PATHINFO_BASENAME, PATHINFO_EXTENSION and PATHINFO_FILENAME. It defaults to return all elements.
 * @return string|array{dirname: string, basename: string, extension: string, filename: string} The following associative array elements are returned: dirname, basename, extension (if any), and filename. If options is used, this function will return a string if not all elements are requested.
 */
function pathinfo(string $path, int $flags = PATHINFO_ALL): array|string {}

/**
 * Un-quotes a quoted string
 * @param string $string The input string.
 * @return string a string with backslashes stripped off. (\' becomes ' and so on.) Double backslashes (\\) are made into a single backslash (\).
 */
function stripslashes(string $string): string {}

/**
 * Un-quote string quoted with addcslashes
 * @param string $string The string to be unescaped.
 * @return string the unescaped string.
 */
function stripcslashes(string $string): string {}

/**
 * Find the first occurrence of a string
 * @param string $haystack The input string.
 * @param string $needle If needle is not a string, it is converted to an integer and applied as the ordinal value of a character.
 * @param bool $before_needle [optional] If true, strstr returns the part of the haystack before the first occurrence of the needle.
 * @return string|false the portion of string, or false if needle is not found.
 */
function strstr(string $haystack, string $needle, bool $before_needle = false): string|false {}

/**
 * Case-insensitive strstr
 * @param string $haystack The string to search in
 * @param string $needle If needle is not a string, it is converted to an integer and applied as the ordinal value of a character.
 * @param bool $before_needle [optional] If true, stristr returns the part of the haystack before the first occurrence of the needle.
 * @return string|false the matched substring. If needle is not found, returns false.
 */
function stristr(string $haystack, string $needle, bool $before_needle = false): string|false {}

/**
 * Find the last occurrence of a character in a string
 * @param string $haystack The string to search in
 * @param string $needle If needle contains more than one character, only the first is used. This behavior is different from that of strstr(). If needle is not a string, it is converted to an integer and applied as the ordinal value of a character.
 * @param bool $before_needle Since 8.3 If true, strrchr() returns the part of the haystack before the last occurrence of the needle (excluding the needle).
 * @return string|false This function returns the portion of string, or FALSE if needle is not found.
 */
function strrchr(string $haystack, string $needle, bool $before_needle = false): string|false {}

/**
 * Randomly shuffles a string
 * @param string $string The input string.
 * @return string the shuffled string.
 */
function str_shuffle(string $string): string {}

/**
 * Return information about words used in a string
 * @param string $string The string
 * @param int $format [optional] Specify the return value of this function. The current supported values are: 0 - returns the number of words found
 * @param string|null $characters [optional] A list of additional characters which will be considered as 'word'
 * @return string[]|int an array or an integer, depending on the format chosen.
 */
function str_word_count(string $string, int $format = 0, ?string $characters = null): array|int {}

/**
 * Convert a string to an array
 * @param string $string The input string.
 * @param int $length [optional] Maximum length of the chunk.
 * @return string[]|false If the optional split_length parameter is specified, the returned array will be broken down into chunks with each being split_length in length, otherwise each chunk will be one character in length. FALSE is returned if split_length is less than 1. If the split_length length ...
 * @throws \ValueError If length is less than 1, a ValueError will be thrown.
 */
function str_split(string $string, int $length = 1): array {}

/**
 * Search a string for any of a set of characters
 * @param string $string The string where char_list is looked for.
 * @param string $characters This parameter is case sensitive.
 * @return string|false a string starting from the character found, or false if it is not found.
 */
function strpbrk(
    string $string,
    string $characters
): string|false {}

/**
 * Binary safe comparison of two strings from an offset, up to length characters
 * @param string $haystack The main string being compared.
 * @param string $needle The secondary string being compared.
 * @param int $offset The start position for the comparison. If negative, it starts counting from the end of the string.
 * @param int|null $length [optional] The length of the comparison.
 * @param bool $case_insensitive [optional] If case_insensitivity is true, comparison is case insensitive.
 * @return int if less than 0 if main_str from position offset is less than str, > 0 if it is greater than str, and 0 if they are equal. If offset is equal to or greater than the length of main_str or length is set and is less than 1, a ValueError is thrown. Prior to PHP 8.0, a warning was raised and ...
 */
function substr_compare(string $haystack, string $needle, int $offset, ?int $length = null, bool $case_insensitive = false): int {}

/**
 * Locale based string comparison
 * @param string $string1 The first string.
 * @param string $string2 The second string.
 * @return int if less than 0 if str1 is less than str2; > 0 if str1 is greater than str2, and 0 if they are equal.
 */
function strcoll(string $string1, string $string2): int {}

/**
 * Formats a number as a currency string
 * @param string $format The format specification consists of the following sequence: a % character
 * @param float $number The number to be formatted.
 * @return string|null the formatted string. Characters before and after the formatting string will be returned unchanged. Non-numeric number causes returning null and emitting E_WARNING.
 * @removed 8.0
 * @see NumberFormatter
 * @deprecated Use the NumberFormatter functionality
 */
function money_format(string $format, float $number): ?string {}

/**
 * Returns the portion of string specified by the offset and length parameters.
 * @param string $string The input string.
 * @param int $offset If offset is non-negative, the returned string will start at the offset'th position in string, counting from zero. For instance, in the string 'abcdef', the character at position 0 is 'a', the character at position 2 is 'c', and so forth. If offset is negative, the returned ...
 * @param int|null $length [optional] If length is given and is positive, the string returned will contain at most length characters beginning from offset (depending on the length of string). If length is given and is negative, then that many characters will be omitted from the end of string. If ...
 * @return string|false Returns the extracted part of string, or an empty string. (FALSE prior PHP 8.0) Basic usage: echo substr('abcdef', 1), PHP_EOL;     // bcdef echo substr("abcdef", 1, null), PHP_EOL; // bcdef; prior to PHP 8.0.0, empty string was returned echo substr('abcdef', 1, 3), PHP_EOL;  ...
 */
function substr(string $string, int $offset, ?int $length = null): string {}

/**
 * Replace text within a portion of a string
 * @param string[]|string $string The input string.
 * @param string[]|string $replace The replacement string.
 * @param int[]|int $offset If start is positive, the replacing will begin at the start'th offset into string. If start is negative, the replacing will begin at the start'th character from the end of string.
 * @param int[]|int $length [optional] If given and is positive, it represents the length of the portion of string which is to be replaced. If it is negative, it represents the number of characters from the end of string at which to stop replacing. If it is not given, then it will default to strlen( ...
 * @return string|string[] The result string is returned. If string is an array then array is returned.
 */
function substr_replace(array|string $string, array|string $replace, array|int $offset, array|int|null $length = null): array|string {}

/**
 * Quote meta characters
 * @param string $string The input string.
 * @return string the string with meta characters quoted.
 */
function quotemeta(string $string): string {}

/**
 * Make a string's first character uppercase
 * @param string $string The input string.
 * @return string the resulting string.
 */
function ucfirst(string $string): string {}

/**
 * Make a string's first character lowercase
 * @param string $string The input string.
 * @return string the resulting string.
 */
function lcfirst(string $string): string {}

/**
 * Uppercase the first character of each word in a string
 * @param string $string The input string.
 * @param string $separators [optional] The optional separators contains the word separator characters.
 * @return string the modified string.
 */
function ucwords(string $string, string $separators = " \t\r\n\f\v"): string {}

/**
 * Translate characters or replace substrings
 * @param string $string The string being translated.
 * @param string $from The string replacing from.
 * @param string $to The string being translated to to.
 * @return string This function returns a copy of str, translating all occurrences of each character in from to the corresponding character in to.
 */
function strtr(string $string, string $from, string $to): string {}

/**
 * Quote string with slashes
 * @param string $string The string to be escaped.
 * @return string the escaped string.
 */
function addslashes(string $string): string {}

/**
 * Quote string with slashes in a C style
 * @param string $string The string to be escaped.
 * @param string $characters A list of characters to be escaped. If characters contains characters \n, \r etc., they are converted in C-like style, while other non-alphanumeric characters with ASCII codes lower than 32 and higher than 126 converted to octal representation. When you define a sequence ...
 * @return string the escaped string. Example usage: <?php $not_escaped = "PHP isThirty\nYears Old!\tYay to the Elephant!\n"; $escaped = addcslashes($not_escaped, "\0..\37!@\177..\377"); echo $escaped; ?>
 */
function addcslashes(string $string, string $characters): string {}

/**
 * Strip whitespace (or other characters) from the end of a string.
 * Without the second parameter, rtrim() will strip these characters:
 *
 * " " (ASCII 32 (0x20)), an ordinary space.
 * "\t" (ASCII 9 (0x09)), a tab.
 * "\n" (ASCII 10 (0x0A)), a new line (line feed).
 * "\r" (ASCII 13 (0x0D)), a carriage return.
 * "\0" (ASCII 0 (0x00)), the NUL-byte.
 * "\x0B" (ASCII 11 (0x0B)), a vertical tab.
 * @param string $string The input string.
 * @param string $characters [optional] You can also specify the characters you want to strip, by means of the charlist parameter. Simply list all characters that you want to be stripped. With .. you can specify a range of characters.
 * @return string the modified string.
 */
function rtrim(string $string, string $characters = " \n\r\t\v\0"): string {}

/**
 * Replace all occurrences of the search string with the replacement string
 * @param string|string[] $search The value being searched for, otherwise known as the needle. An array may be used to designate multiple needles.
 * @param string|string[] $replace The replacement value that replaces found search values. An array may be used to designate multiple replacements.
 * @param string|string[] $subject The string or array being searched and replaced on, otherwise known as the haystack. If subject is an array, then the search and replace is performed with every entry of subject, and the return value is an array as well.
 * @param int &$count [optional] If passed, this will hold the number of matched and replaced needles.
 * @return string|string[] This function returns a string or an array with the replaced values.
 */
function str_replace(array|string $search, array|string $replace, array|string $subject, &$count = null): array|string {}

/**
 * Case-insensitive version of str_replace.
 * @param mixed $search Every replacement with search array is performed on the result of previous replacement.
 * @param array|string $replace
 * @param array|string $subject If subject is an array, then the search and replace is performed with every entry of subject, and the return value is an array as well.
 * @param int &$count [optional] The number of matched and replaced needles will be returned in count which is passed by reference.
 * @return string|string[] a string or an array of replacements.
 */
function str_ireplace(array|string $search, array|string $replace, array|string $subject, &$count = null): array|string {}

/**
 * Repeat a string
 * @param string $string The string to be repeated.
 * @param int $times Number of time the input string should be repeated. multiplier has to be greater than or equal to 0. If the multiplier is set to 0, the function will return an empty string.
 * @return string the repeated string.
 */
function str_repeat(string $string, int $times): string {}

/**
 * Return information about characters used in a string
 * @param string $string The examined string.
 * @param int $mode See return values.
 * @return int[]|string Depending on mode count_chars returns one of the following: 0 - an array with the byte-value as key and the frequency of every byte as value. 1 - same as 0 but only byte-values with a frequency greater than zero are listed. 2 - same as 0 but only byte-values with a frequency ...
 */
function count_chars(string $string, int $mode = 0): array|string {}

/**
 * Split a string into smaller chunks
 * @param string $string The string to be chunked.
 * @param int $length [optional] The chunk length.
 * @param string $separator [optional] The line ending sequence.
 * @return string the chunked string.
 */
function chunk_split(string $string, int $length = 76, string $separator = "\r\n"): string {}

/**
 * Strip whitespace (or other characters) from the beginning and end of a string
 * @param string $string The string that will be trimmed.
 * @param string $characters [optional] Optionally, the stripped characters can also be specified using the charlist parameter. Simply list all characters that you want to be stripped. With .. you can specify a range of characters.
 * @return string The trimmed string.
 */
function trim(string $string, string $characters = " \n\r\t\v\0"): string {}

/**
 * Strip whitespace (or other characters) from the beginning of a string
 * @param string $string The input string.
 * @param string $characters [optional] You can also specify the characters you want to strip, by means of the charlist parameter. Simply list all characters that you want to be stripped. With .. you can specify a range of characters.
 * @return string This function returns a string with whitespace stripped from the beginning of str. Without the second parameter, ltrim will strip these characters: " " (ASCII 32 (0x20)), an ordinary space. "\t" (ASCII 9 (0x09)), a tab. "\n" (ASCII 10 (0x0A)), a new line (line feed). "\r" (ASCII 13 ...
 */
function ltrim(string $string, string $characters = " \n\r\t\v\0"): string {}

/**
 * Strip HTML and PHP tags from a string
 * @param string $string The input string.
 * @param string[]|string|null $allowed_tags [optional] You can use the optional second parameter to specify tags which should not be stripped. HTML comments and PHP tags are also stripped. This is hardcoded and can not be changed with allowable_tags.
 * @return string the stripped string.
 */
function strip_tags(string $string, string[]|string|null $allowed_tags = null): string {}

/**
 * Calculate the similarity between two strings
 * @param string $string1 The first string.
 * @param string $string2 The second string.
 * @param float &$percent [optional] By passing a reference as third argument, similar_text will calculate the similarity in percent for you.
 * @return int the number of matching chars in both strings.
 */
function similar_text(string $string1, string $string2, &$percent = null): int {}

/**
 * Split a string by a string
 * @param string $separator The boundary string.
 * @param string $string The input string.
 * @param int $limit [optional] If limit is set and positive, the returned array will contain a maximum of limit elements with the last element containing the rest of string. If the limit parameter is negative, all components except the last -limit are returned. If the limit parameter is zero, then ...
 * @return string[]|false If separator is an empty string (""), explode will return false. If separator contains a value that is not contained in string and a negative limit is used, then an empty array will be returned. For any other limit, an array containing string will be returned.
 */
function explode(string $separator, string $string, int $limit = PHP_INT_MAX): string[] {}

/**
 * Join array elements with a string
 * @param array|string  $separator [optional] Defaults to an empty string. This is not the preferred usage of implode as glue would be the second parameter and thus, the bad prototype would be used.
 * @param array|null $array The array of strings to implode.
 * @return string a string containing a string representation of all the array elements in the same order, with the glue string between each element.
 */
function implode(array|string $separator = "", ?array $array = null): string {}

/**
 * Alias:
 * implode
 * @param array|string  $separator [optional] Defaults to an empty string. This is not the preferred usage of implode as glue would be the second parameter and thus, the bad prototype would be used.
 * @param array|null $array The array of strings to implode.
 * @return string a string containing a string representation of all the array elements in the same order, with the glue string between each element.
 */
function join(array|string $separator = "", ?array $array = null): string {}

/**
 * Set locale information
 * @param int $category category is a named constant specifying the category of the functions affected by the locale setting: LC_ALL for all of the below LC_COLLATE for string comparison, see strcoll() LC_CTYPE for character classification and conversion, for example strtoupper() LC_MONETARY for ...
 * @param string|string[]|int $locales If locale is null or the empty string "", the locale names will be set from the values of environment variables with the same names as the above categories, or from "LANG". If locale is "0", the locale setting is not affected, only the current setting is ...
 * @param string|string[] ...$rest Optional string parameters to try as locale settings until success.
 * @return string|false the new current locale, or false if the locale functionality is not implemented on your platform, the specified locale does not exist or the category name is invalid. An invalid category name also causes a warning message. Category/locale names can be found in RFC 1766 and ISO ...
 */
function setlocale(
    int $category,
    $locales,
    ...$rest
): string|false {}

/**
 * Get numeric formatting information
 * @return array localeconv returns data based upon the current locale as set by setlocale. The associative array that is returned contains the following fields: Array element Description decimal_point Decimal point character thousands_sep Thousands separator grouping Array containing numeric ...
 */
function localeconv(): array {}
