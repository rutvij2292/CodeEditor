<?php

/**
 * Returns the JSON representation of a value
 * @param mixed $value The value being encoded. Can be any type except a resource. All string data must be UTF-8 encoded. PHP implements a superset of JSON - it will also encode and decode scalar types and NULL. The JSON standard only supports these values when they are nested inside an array or an ...
 * @param int $flags [optional] Bitmask consisting of JSON_HEX_QUOT, JSON_HEX_TAG, JSON_HEX_AMP, JSON_HEX_APOS, JSON_NUMERIC_CHECK, JSON_PRETTY_PRINT, JSON_UNESCAPED_SLASHES, JSON_FORCE_OBJECT, JSON_UNESCAPED_UNICODE. JSON_THROW_ON_ERROR The behaviour of these constants is described on the JSON ...
 * @param int $depth [optional] Set the maximum depth. Must be greater than zero.
 * @return string|false a JSON encoded string on success or FALSE on failure.
 */
function json_encode(mixed $value, int $flags = 0, int $depth = 512): string|false {}

/**
 * Takes a JSON encoded string and converts it into a PHP value.
 * @param string $json The json string being decoded. This function only works with UTF-8 encoded strings. PHP implements a superset of JSON as specified by RFC 7159.
 * @param bool|null $associative When TRUE, JSON objects will be returned as associative arrays; when FALSE, JSON objects will be returned as objects. When NULL, JSON objects will be returned as associative arrays or objects depending on whether JSON_OBJECT_AS_ARRAY is set in the flags.
 * @param int $depth [optional] Maximum nesting depth of the structure being decoded. The value must be greater than 0, and less than or equal to 2147483647.
 * @param int $flags [optional] Bitmask of JSON decode options: JSON_BIGINT_AS_STRING decodes large integers as their original string value. JSON_INVALID_UTF8_IGNORE ignores invalid UTF-8 characters, JSON_INVALID_UTF8_SUBSTITUTE converts invalid UTF-8 characters to \0xfffd, Available as of PHP 7.2.0. ...
 * @return mixed Returns the value encoded in json as an appropriate PHP type. Unquoted values true, FALSE and NULL are returned as TRUE, FALSE and NULL respectively. NULL is returned if the json cannot be decoded or if the encoded data is deeper than the nesting limit.
 * @throws \ValueError If depth is outside the allowed range, a ValueError is thrown as of PHP 8.0.0, while previously, an error of level E_WARNING was raised.
 */
function json_decode(string $json, ?bool $associative = null, int $depth = 512, int $flags = 0): mixed {}

/**
 * Returns the last error occurred
 * @return int an integer, the value can be one of the following constants: Constant Meaning Availability JSON_ERROR_NONE No error has occurred JSON_ERROR_DEPTH The maximum stack depth has been exceeded JSON_ERROR_STATE_MISMATCH Invalid or malformed JSON JSON_ERROR_CTRL_CHAR Control character error, ...
 */
function json_last_error(): int {}

/**
 * Returns the error string of the last json_encode() or json_decode() call, which did not specify JSON_THROW_ON_ERROR.
 * @return string Returns the error message on success, "No error" if no error has occurred.
 * @since 5.5
 */
function json_last_error_msg(): string {}

/**
 * Checks if a string contains valid JSON
 *
 * Returns whether the given string is syntactically valid JSON. If json_validate returns true,
 * json_decode will successfully decode the given string when using the same depth and flags.
 * @since 8.3
 * @throws \ValueError If depth is outside the allowed range, a ValueError is thrown. If flags is not a valid flag, a ValueError is thrown.
 */
function json_validate(string $json, int $depth = 512, int $flags = 0): bool {}
