<?php

/**
 * All < and > are converted to \u003C and \u003E.
 */
const JSON_HEX_TAG = 1;

/**
 * All &s are converted to \u0026.
 */
const JSON_HEX_AMP = 2;

/**
 * All ' are converted to \u0027.
 */
const JSON_HEX_APOS = 4;

/**
 * All " are converted to \u0022.
 */
const JSON_HEX_QUOT = 8;

/**
 * Outputs an object rather than an array when a non-associative array is
 * used. Especially useful when the recipient of the output is expecting
 * an object and the array is empty.
 */
const JSON_FORCE_OBJECT = 16;

/**
 * Encodes numeric strings as numbers.
 * @since 5.3
 */
const JSON_NUMERIC_CHECK = 32;

/**
 * Don't escape /.
 * @since 5.4
 */
const JSON_UNESCAPED_SLASHES = 64;

/**
 * Use whitespace in returned data to format it.
 * @since 5.4
 */
const JSON_PRETTY_PRINT = 128;

/**
 * Encode multibyte Unicode characters literally (default is to escape as \uXXXX).
 * @since 5.4
 */
const JSON_UNESCAPED_UNICODE = 256;

const JSON_PARTIAL_OUTPUT_ON_ERROR = 512;

/**
 * Occurs with underflow or with the modes mismatch.
 */
const JSON_ERROR_STATE_MISMATCH = 2;

/**
 * Control character error, possibly incorrectly encoded.
 */
const JSON_ERROR_CTRL_CHAR = 3;

/**
 * Malformed UTF-8 characters, possibly incorrectly encoded. This
 * constant is available as of PHP 5.3.3.
 */
const JSON_ERROR_UTF8 = 5;

/**
 * The object or array passed to json_encode include
 * recursive references and cannot be encoded.
 * If the JSON_PARTIAL_OUTPUT_ON_ERROR option was
 * given, NULL will be encoded in the place of the recursive reference.
 *
 * This constant is available as of PHP 5.5.0.
 */
const JSON_ERROR_RECURSION = 6;

/**
 * The value passed to json_encode includes either
 * NAN
 * or INF.
 * If the JSON_PARTIAL_OUTPUT_ON_ERROR option was
 * given, 0 will be encoded in the place of these
 * special numbers.
 *
 * This constant is available as of PHP 5.5.0.
 */
const JSON_ERROR_INF_OR_NAN = 7;

/**
 * A value of an unsupported type was given to
 * json_encode, such as a resource.
 * If the JSON_PARTIAL_OUTPUT_ON_ERROR option was
 * given, NULL will be encoded in the place of the unsupported value.
 *
 * This constant is available as of PHP 5.5.0.
 */
const JSON_ERROR_UNSUPPORTED_TYPE = 8;

/**
 * No error has occurred.
 */
const JSON_ERROR_NONE = 0;

/**
 * The maximum stack depth has been exceeded.
 */
const JSON_ERROR_DEPTH = 1;

/**
 * Syntax error.
 */
const JSON_ERROR_SYNTAX = 4;

/**
 * Decodes JSON objects as PHP array.
 * @since 5.4
 */
const JSON_OBJECT_AS_ARRAY = 1;

const JSON_PARSER_NOTSTRICT = 4;

/**
 * Decodes large integers as their original string value.
 * @since 5.4
 */
const JSON_BIGINT_AS_STRING = 2;

/**
 * Ensures that float values are always encoded as a float value.
 * @since 5.6
 */
const JSON_PRESERVE_ZERO_FRACTION = 1024;

/**
 * The line terminators are kept unescaped when JSON_UNESCAPED_UNICODE is supplied.
 * It uses the same behaviour as it was before PHP 7.1 without this constant. Available since PHP 7.1.0.
 * @since 7.1
 */
const JSON_UNESCAPED_LINE_TERMINATORS = 2048;

/**
 * Ignore invalid UTF-8 characters.
 * @since 7.2
 */
const JSON_INVALID_UTF8_IGNORE = 1048576;

/**
 * Convert invalid UTF-8 characters to \0xfffd (Unicode Character 'REPLACEMENT CHARACTER').
 * @since 7.2
 */
const JSON_INVALID_UTF8_SUBSTITUTE = 2097152;

/**
 * A key starting with \u0000 character was in the string passed to json_decode() when decoding a JSON object into a PHP object.
 * Available since PHP 7.0.0.
 * @since 7.0
 */
const JSON_ERROR_INVALID_PROPERTY_NAME = 9;

/**
 * Single unpaired UTF-16 surrogate in unicode escape contained in the JSON string passed to json_encode().
 * Available since PHP 7.0.0.
 * @since 7.0
 */
const JSON_ERROR_UTF16 = 10;

/**
 * Throws JsonException if an error occurs instead of setting the global error state
 * that is retrieved with json_last_error() and json_last_error_msg().
 *
 * JSON_PARTIAL_OUTPUT_ON_ERROR takes precedence over JSON_THROW_ON_ERROR.
 * @since 7.3
 */
const JSON_THROW_ON_ERROR = 4194304;

/**
 * @since 8.1
 */
const JSON_ERROR_NON_BACKED_ENUM = 11;
