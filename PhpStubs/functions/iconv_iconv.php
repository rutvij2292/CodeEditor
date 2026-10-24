<?php

/**
 * Convert string to requested character encoding
 * @param string $from_encoding The input charset.
 * @param string $to_encoding The output charset. If you append the string //TRANSLIT to out_charset transliteration is activated. This means that when a character can't be represented in the target charset, it can be approximated through one or several similarly looking characters. If you append the ...
 * @param string $string The string to be converted.
 * @return string|false the converted string or FALSE on failure.
 */
function iconv(string $from_encoding, string $to_encoding, string $string): string|false {}

/**
 * Convert character encoding as output buffer handler
 * @param string $contents
 * @param int $status
 * @return string See ob_start for information about this handler return values.
 */
function ob_iconv_handler(string $contents, int $status): string {}

/**
 * Retrieve internal configuration variables of iconv extension
 * @param string $type [optional] The value of the optional type can be: all input_encoding output_encoding internal_encoding
 * @return string|string[]|false the current value of the internal configuration variable if successful or FALSE on failure. If type is omitted or set to "all", iconv_get_encoding returns an array that stores all these variables.
 */
function iconv_get_encoding(string $type = "all"): array|string|false {}

/**
 * Set current setting for character encoding conversion
 * @param string $type The value of type can be any one of these: input_encoding output_encoding internal_encoding
 * @param string $encoding The character set.
 * @return bool TRUE on success or FALSE on failure.
 */
function iconv_set_encoding(string $type, string $encoding): bool {}

/**
 * Returns the character count of string
 * @param string $string The string.
 * @param string|null $encoding If charset parameter is omitted, str is assumed to be encoded in iconv.internal_encoding.
 * @return int|false the character count of str, as an integer. False on error.
 */
function iconv_strlen(string $string, ?string $encoding = null): int|false {}

/**
 * Cut out part of a string
 * @param string $string The original string.
 * @param int $offset If offset is non-negative, iconv_substr cuts the portion out of str beginning at offset'th character, counting from zero. If offset is negative, iconv_substr cuts out the portion beginning at the position, offset characters away from the end of str.
 * @param int|null $length [optional] If length is given and is positive, the return value will contain at most length characters of the portion that begins at offset (depending on the length of string). If negative length is passed, iconv_substr cuts the portion out of str from the offset'th ...
 * @param string|null $encoding If charset parameter is omitted, string are assumed to be encoded in iconv.internal_encoding. Note that offset and length parameters are always deemed to represent offsets that are calculated on the basis of the character set determined by charset, whilst the ...
 * @return string|false the portion of str specified by the offset and length parameters. If str is shorter than offset characters long, FALSE will be returned.
 */
function iconv_substr(string $string, int $offset, ?int $length = null, ?string $encoding = null): string|false {}

/**
 * Finds position of first occurrence of a needle within a haystack
 * @param string $haystack The entire string.
 * @param string $needle The searched substring.
 * @param int $offset [optional] The optional offset parameter specifies the position from which the search should be performed.
 * @param string|null $encoding If charset parameter is omitted, string are assumed to be encoded in iconv.internal_encoding.
 * @return int<0,max>|false the numeric position of the first occurrence of needle in haystack. If needle is not found, iconv_strpos will return FALSE.
 */
function iconv_strpos(string $haystack, string $needle, int $offset = 0, ?string $encoding = null): int|false {}

/**
 * Finds the last occurrence of a needle within a haystack
 * @param string $haystack The entire string.
 * @param string $needle The searched substring.
 * @param string|null $encoding If charset parameter is omitted, string are assumed to be encoded in iconv.internal_encoding.
 * @return int|false the numeric position of the last occurrence of needle in haystack. If needle is not found, iconv_strrpos will return FALSE.
 */
function iconv_strrpos(string $haystack, string $needle, ?string $encoding = null): int|false {}

/**
 * Composes a MIME header field
 * @param string $field_name The field name.
 * @param string $field_value The field value.
 * @param array $options You can control the behaviour of iconv_mime_encode by specifying an associative array that contains configuration items to the optional third parameter preferences. The items supported by iconv_mime_encode are listed below. Note that item names are treated case-sensitive. ...
 * @return string|false an encoded MIME field on success, or FALSE if an error occurs during the encoding.
 */
function iconv_mime_encode(string $field_name, string $field_value, array $options = []): string|false {}

/**
 * Decodes a MIME header field
 * @param string $string The encoded header, as a string.
 * @param int $mode [optional] mode determines the behaviour in the event iconv_mime_decode encounters a malformed MIME header field. You can specify any combination of the following bitmasks. Bitmasks acceptable to iconv_mime_decode Value Constant Description 1 ICONV_MIME_DECODE_STRICT If set, the ...
 * @param string|null $encoding The optional charset parameter specifies the character set to represent the result by. If omitted, iconv.internal_encoding will be used.
 * @return string|false a decoded MIME field on success, or FALSE if an error occurs during the decoding.
 */
function iconv_mime_decode(string $string, int $mode = 0, ?string $encoding = null): string|false {}

/**
 * Decodes multiple MIME header fields at once
 * @param string $headers The encoded headers, as a string.
 * @param int $mode [optional] mode determines the behaviour in the event iconv_mime_decode_headers encounters a malformed MIME header field. You can specify any combination of the following bitmasks. Bitmasks acceptable to iconv_mime_decode_headers Value Constant Description 1 ...
 * @param string|null $encoding The optional charset parameter specifies the character set to represent the result by. If omitted, iconv.internal_encoding will be used.
 * @return array|false an associative array that holds a whole set of MIME header fields specified by encoded_headers on success, or FALSE if an error occurs during the decoding. Each key of the return value represents an individual field name and the corresponding element represents a field value. If ...
 */
function iconv_mime_decode_headers(string $headers, int $mode = 0, ?string $encoding = null): array|false {}
