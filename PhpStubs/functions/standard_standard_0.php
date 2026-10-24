<?php

/**
 * Returns the value of a constant
 * @param string $name The constant name.
 * @return mixed the value of the constant.
 * @throws Error If the constant is not defined
 */
function constant(string $name): mixed {}

/**
 * Convert binary data into hexadecimal representation
 * @param string $string A string.
 * @return string the hexadecimal representation of the given string.
 */
function bin2hex(string $string): string {}

/**
 * Delays the program execution for the given number of seconds
 * @param int<0,max> $seconds Halt time in seconds (must be greater than or equal to 0).
 * @return int Returns zero on success. If the call was interrupted by a signal, sleep() returns a non-zero value. On Windows, this value will always be 192 (the value of the WAIT_IO_COMPLETION constant within the Windows API). On other platforms, the return value will be the number of seconds left to ...
 * @throws \ValueError If the specified number of seconds is negative, this function will throw a ValueError.
 */
function sleep(int $seconds): int {}

/**
 * Delay execution in microseconds
 * @param int<0,max> $microseconds Halt time in micro seconds. A micro second is one millionth of a second.
 * @return void No value is returned.
 */
function usleep(int $microseconds): void {}

/**
 * Delay for a number of seconds and nanoseconds
 * @param positive-int $seconds Must be a positive integer.
 * @param positive-int $nanoseconds Must be a positive integer less than 1 billion.
 * @return bool|array true on success or false on failure. If the delay was interrupted by a signal, an associative array will be returned with the components: seconds - number of seconds remaining in the delay nanoseconds - number of nanoseconds remaining in the delay
 */
function time_nanosleep(int $seconds, int $nanoseconds): array|bool {}

/**
 * Make the script sleep until the specified time
 * @param float $timestamp The timestamp when the script should wake.
 * @return bool true on success or false on failure.
 */
function time_sleep_until(float $timestamp): bool {}

/**
 * Parse a time/date generated with strftime
 * @param string $timestamp The string to parse (e.g. returned from strftime)
 * @param string $format The format used in date (e.g. the same as used in strftime). For more information about the format options, read the strftime page.
 * @return array|false an array or false on failure. The following parameters are returned in the array parameters Description "tm_sec" Seconds after the minute (0-61) "tm_min" Minutes after the hour (0-59) "tm_hour" Hour since midnight (0-23) "tm_mday" Day of the month (1-31) "tm_mon" Months since ...
 * @deprecated
 */
function strptime(string $timestamp, string $format): array|false {}

/**
 * Flush system output buffer
 * @return void No value is returned.
 */
function flush(): void {}

/**
 * Wraps a string to a given number of characters
 * @param string $string The input string.
 * @param int $width [optional] The number of characters at which the string will be wrapped.
 * @param string $break [optional] The line is broken using the optional break parameter.
 * @param bool $cut_long_words [optional] If the cut is set to true, the string is always wrapped at or before the specified width. So if you have a word that is larger than the given width, it is broken apart. (See second example).
 * @return string the given string wrapped at the specified length.
 * @throws \ValueError If break is an empty string, a ValueError is thrown.
 */
function wordwrap(string $string, int $width = 75, string $break = "\n", bool $cut_long_words = false): string {}

/**
 * Convert special characters to HTML entities
 * @param string $string The string being converted.
 * @param int $flags [optional] A bitmask of one or more of the following flags, which specify how to handle quotes, invalid code unit sequences and the used document type. The default is ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML401 (it was ENT_COMPAT | ENT_HTML401 prior to PHP 8.1). <caption>Available ...
 * @param string|null $encoding Defines encoding used in conversion. If omitted, the default value for this argument is ISO-8859-1 in versions of PHP prior to 5.4.0, and UTF-8 from PHP 5.4.0 onwards. For the purposes of this function, the encodings ISO-8859-1, ISO-8859-15, UTF-8, cp866, cp1251, ...
 * @param bool $double_encode [optional] When double_encode is turned off PHP will not encode existing html entities, the default is to convert everything.
 * @return string The converted string.
 */
function htmlspecialchars(string $string, int $flags = ENT_QUOTES|ENT_SUBSTITUTE|ENT_HTML401, ?string $encoding = null, bool $double_encode = true): string {}

/**
 * Convert all applicable characters to HTML entities
 * @param string $string The input string.
 * @param int $flags [optional] Like htmlspecialchars, the optional second flags parameter lets you define what will be done with 'single' and "double" quotes, invalid code unit sequences and the used document type. The default is ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML401 (it was ENT_COMPAT | ...
 * @param string|null $encoding [optional] Like htmlspecialchars, it takes an optional third argument charset which defines character set used in conversion. Presently, the ISO-8859-1 character set is used as the default.
 * @param bool $double_encode [optional] When double_encode is turned off PHP will not encode existing html entities. The default is to convert everything.
 * @return string the encoded string.
 */
function htmlentities(string $string, int $flags = ENT_QUOTES|ENT_SUBSTITUTE|ENT_HTML401, ?string $encoding = null, bool $double_encode = true): string {}

/**
 * Convert HTML entities  to their corresponding characters
 * @param string $string The input string.
 * @param int $flags [optional] The optional second flags parameter lets you define what will be done with 'single' and "double" quotes and which document type to use. The default is ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML401 (it was ENT_COMPAT | ENT_HTML401 prior to PHP 8.1): Available flags constants ...
 * @param string|null $encoding [optional] The ISO-8859-1 character set is used as default for the optional third charset. This defines the character set used in conversion.
 * @return string the decoded string.
 */
function html_entity_decode(string $string, int $flags = ENT_QUOTES|ENT_SUBSTITUTE|ENT_HTML401, ?string $encoding = null): string {}

/**
 * Convert special HTML entities back to characters
 * @param string $string The string to decode
 * @param int $flags [optional] A bitmask of one or more of the following flags, which specify how to handle quotes and which document type to use. The default is ENT_QUOTES | ENT_SUBSTITUTE | ENT_HTML401 (it was ENT_COMPAT | ENT_HTML401 prior to PHP 8.1): flags constants Constant Name Description ...
 * @return string the decoded string.
 */
function htmlspecialchars_decode(string $string, int $flags = ENT_QUOTES|ENT_SUBSTITUTE|ENT_HTML401): string {}

/**
 * Returns the translation table used by htmlspecialchars and htmlentities
 * @param int $table There are two new constants (HTML_ENTITIES, HTML_SPECIALCHARS) that allow you to specify the table you want.
 * @param int $flags [optional] Like the htmlspecialchars and htmlentities functions you can optionally specify the quote_style you are working with. See the description of these modes in htmlspecialchars.
 * @param string $encoding [optional] Encoding to use. If omitted, the default value for this argument is ISO-8859-1 in versions of PHP prior to 5.4.0, and UTF-8 from PHP 5.4.0 onwards. The following character sets are supported: <caption>Supported charsets</caption> Charset Aliases Description ...
 * @return array the translation table as an array.
 */
function get_html_translation_table(
    int $table = 0,
    int $flags = ENT_QUOTES|ENT_SUBSTITUTE|ENT_HTML401,
    string $encoding = "UTF-8"
): array {}

/**
 * Calculate the sha1 hash of a string
 * @param string $string The input string.
 * @param bool $binary [optional] If the optional binary is set to true, then the sha1 digest is instead returned in raw binary format with a length of 20, otherwise the returned value is a 40-character hexadecimal number.
 * @return string the sha1 hash as a string.
 */
function sha1(string $string, bool $binary = false): string {}

/**
 * Calculate the sha1 hash of a file
 * @param string $filename The filename
 * @param bool $binary [optional] When true, returns the digest in raw binary format with a length of 20.
 * @return string|false a string on success, false otherwise.
 */
function sha1_file(string $filename, bool $binary = false): string|false {}

/**
 * Calculate the md5 hash of a string
 * @param string $string The string.
 * @param bool $binary [optional] If the optional raw_output is set to true, then the md5 digest is instead returned in raw binary format with a length of 16.
 * @return string the hash as a 32-character hexadecimal number.
 */
function md5(string $string, bool $binary = false): string {}

/**
 * Calculates the md5 hash of a given file
 * @param string $filename The filename
 * @param bool $binary [optional] When true, returns the digest in raw binary format with a length of 16.
 * @return string|false a string on success, false otherwise.
 */
function md5_file(string $filename, bool $binary = false): string|false {}

/**
 * Calculates the crc32 polynomial of a string
 * @param string $string The data.
 * @return int the crc32 checksum of str as an integer..1
 */
function crc32(string $string): int {}

/**
 * Parse a binary IPTC block into single tags.
 * Note: This function does not require the GD image library.
 * @param string $iptc_block A binary IPTC block.
 * @return array|false an array using the tagmarker as an index and the value as the value. It returns false on error or if no IPTC data was found.
 */
function iptcparse(string $iptc_block): array|false {}

/**
 * Embeds binary IPTC data into a JPEG image.
 * Note: This function does not require the GD image library.
 * @param string $iptc_data The data to be written.
 * @param string $filename Path to the JPEG image.
 * @param int $spool Spool flag. If the spool flag is less than 2 then the JPEG will be returned as a string. Otherwise the JPEG will be printed to STDOUT.
 * @return string|bool If spool is less than 2, the JPEG will be returned, or false on failure. Otherwise returns true on success or false on failure.
 */
function iptcembed(string $iptc_data, string $filename, int $spool = 0): string|bool {}

/**
 * Get the size of an image
 * @param string $filename This parameter specifies the file you wish to retrieve information about. It can reference a local file or (configuration permitting) a remote file using one of the supported streams.
 * @param array &$image_info [optional] This optional parameter allows you to extract some extended information from the image file. Currently, this will return the different JPG APP markers as an associative array. Some programs use these APP markers to embed text information in images. A very common ...
 * @return array|false an array with 7 elements. Index 0 and 1 contains respectively the width and the height of the image. Some formats may contain no image or may contain multiple images. In these cases, getimagesize might not be able to properly determine the image size. getimagesize will return ...
 * @throws \ValueError If accessing the filename image is impossible getimagesize will generate an error of level E_WARNING. On read error, getimagesize will generate an error of level E_NOTICE. As of PHP 8.0.0, a ValueError is thrown if filename is empty.
 */
function getimagesize(string $filename, &$image_info = null): array|false {}

/**
 * Get Mime-Type for image-type returned by getimagesize, exif_read_data, exif_thumbnail, exif_imagetype
 * @param int $image_type One of the IMAGETYPE_XXX constants.
 * @return string The returned values are as follows Returned values Constants imagetype Returned value IMAGETYPE_GIF image/gif IMAGETYPE_JPEG image/jpeg IMAGETYPE_PNG image/png IMAGETYPE_SWF application/x-shockwave-flash IMAGETYPE_PSD image/psd IMAGETYPE_BMP image/bmp IMAGETYPE_TIFF_II (intel byte ...
 */
function image_type_to_mime_type(int $image_type): string {}

/**
 * Get file extension for image type
 * @param int $image_type One of the IMAGETYPE_XXX constant.
 * @param bool $include_dot [optional] Removed since 8.0. Whether to prepend a dot to the extension or not. Default to true.
 * @return string|false A string with the extension corresponding to the given image type, or false on failure.
 */
function image_type_to_extension(int $image_type, bool $include_dot = true): string|false {}

/**
 * Outputs information about PHP's configuration
 * @param int $flags [optional] The output may be customized by passing one or more of the following constants bitwise values summed together in the optional what parameter. One can also combine the respective constants or bitwise values together with the or operator. phpinfo options Name (constant) ...
 * @return bool true on success or false on failure.
 */
function phpinfo(int $flags = INFO_ALL): true {}

/**
 * Gets the current PHP version
 * @param string|null $extension [optional] An optional extension name.
 * @return string|false If the optional extension parameter is specified, phpversion returns the version of that extension, or false if there is no version information associated or the extension isn't enabled.
 */
function phpversion(?string $extension = null): string|false {}

/**
 * Prints out the credits for PHP
 * @param int $flags [optional] To generate a custom credits page, you may want to use the flags parameter. Pre-defined phpcredits flags name description CREDITS_ALL All the credits, equivalent to using: CREDITS_DOCS + CREDITS_GENERAL + CREDITS_GROUP + CREDITS_MODULES + CREDITS_FULLPAGE. It generates ...
 * @return bool true on success or false on failure.
 */
function phpcredits(int $flags = CREDITS_ALL): true {}

/**
 * Gets the logo guid
 * @removed 5.5
 * @return string PHPE9568F34-D428-11d2-A769-00AA001ACF42.
 */
function php_logo_guid(): string {}

/**
 * @removed 5.5
 */
function php_real_logo_guid() {}

/**
 * @removed 5.5
 */
function php_egg_logo_guid() {}

/**
 * Gets the Zend guid
 * @removed 5.5
 * @return string PHPE9568F35-D428-11d2-A769-00AA001ACF42.
 */
function zend_logo_guid(): string {}

/**
 * Returns the type of interface between web server and PHP
 * @return string|false the interface type, as a lowercase string, or false on failure. Although not exhaustive, the possible return values include aolserver, apache, apache2filter, apache2handler, caudium, cgi (until PHP 5.3), cgi-fcgi, cli, continuity, embed, isapi, litespeed, milter, nsapi, phttpd, ...
 */
function php_sapi_name(): string|false {}

/**
 * Returns information about the operating system PHP is running on
 * @param string $mode [optional] mode is a single character that defines what information is returned: 'a': This is the default. Contains all modes in the sequence "s n r v m".
 * @return string the description, as a string.
 */
function php_uname(string $mode = 'a'): string {}

/**
 * Return a list of .ini files parsed from the additional ini dir
 * @return string|false a comma-separated string of .ini files on success. Each comma is followed by a newline. If the directive --with-config-file-scan-dir wasn't set, false is returned. If it was set and the directory was empty, an empty string is returned. If a file is unrecognizable, the file will ...
 */
function php_ini_scanned_files(): string|false {}

/**
 * Retrieve a path to the loaded php.ini file
 * @return string|false The loaded "php.ini" path, or false if one is not loaded.
 * @since 5.2
 */
function php_ini_loaded_file(): string|false {}

/**
 * String comparisons using a "natural order" algorithm
 * @param string $string1 The first string.
 * @param string $string2 The second string.
 * @return int Similar to other string comparison functions, this one returns < 0 if str1 is less than str2; > 0 if str1 is greater than str2, and 0 if they are equal.
 */
function strnatcmp(string $string1, string $string2): int {}

/**
 * Case insensitive string comparisons using a "natural order" algorithm
 * @param string $string1 The first string.
 * @param string $string2 The second string.
 * @return int Similar to other string comparison functions, this one returns < 0 if str1 is less than str2 > 0 if str1 is greater than str2, and 0 if they are equal.
 */
function strnatcasecmp(string $string1, string $string2): int {}

/**
 * Count the number of substring occurrences
 * @param string $haystack The string to search in
 * @param string $needle The substring to search for
 * @param int $offset The offset where to start counting. If the offset is negative, counting starts from the end of the string.
 * @param int|null $length [optional] The maximum length after the specified offset to search for the substring. It outputs a warning if the offset plus the length is greater than the haystack length. A negative length counts from the end of haystack.
 * @return int<0,max> This functions returns an integer.
 */
function substr_count(string $haystack, string $needle, int $offset = 0, ?int $length = null): int {}

/**
 * Finds the length of the initial segment of a string consisting
 * entirely of characters contained within a given mask.
 * @param string $string The string to examine.
 * @param string $characters The list of allowable characters to include in counted segments.
 * @param int $offset The position in subject to start searching. If start is given and is non-negative, then strspn will begin examining subject at the start'th position. For instance, in the string 'abcdef', the character at position 0 is 'a', the character at position 2 is 'c', and so forth. If ...
 * @param int|null $length [optional] The length of the segment from subject to examine. If length is given and is non-negative, then subject will be examined for length characters after the starting position. If lengthis given and is negative, then subject will be examined from the starting position ...
 * @return int the length of the initial segment of str1 which consists entirely of characters in str2.
 */
function strspn(string $string, string $characters, int $offset = 0, ?int $length = null): int {}

/**
 * Find length of initial segment not matching mask
 * @param string $string The first string.
 * @param string $characters The second string.
 * @param int $offset The start position of the string to examine.
 * @param int|null $length [optional] The length of the string to examine.
 * @return int the length of the segment as an integer.
 */
function strcspn(string $string, string $characters, int $offset = 0, ?int $length = null): int {}

/**
 * Tokenize string
 * Note that only the first call to strtok uses the string argument.
 * Every subsequent call to strtok only needs the token to use, as it keeps track of where it is in the current string.
 * To start over, or to tokenize a new string you simply call strtok with the string argument again to initialize it.
 * Note that you may put multiple tokens in the token parameter.
 * The string will be tokenized when any one of the characters in the argument are found.
 * @param string $string The string being split up into smaller strings (tokens).
 * @param string|null $token The delimiter used when splitting up str.
 * @return string|false A string token.
 */
function strtok(
    string $string,
    ?string $token = null
): string|false {}
